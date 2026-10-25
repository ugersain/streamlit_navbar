"""Account management: profile details, password, devices, calendar link, weight log, plan recalculation, stats."""
from __future__ import annotations

import secrets
import datetime as dt
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .connectors import require_password
from .db import ActivityLog, ProfileRow, Record, SessionToken, User, get_session, utcnow
from .plan import build_plan
from .security import bearer, current_user, hash_password, token_digest, verify_password
from .state import as_utc, load_snapshot

router = APIRouter(prefix="/v1", tags=["account"])
EMAIL = r"^[^@\s]+@[^@\s]+\.[^@\s]+$"


class AccountPatch(BaseModel):
    name: str | None = Field(default=None, max_length=100)
    email: str | None = Field(default=None, max_length=254, pattern=EMAIL)
    current_password: str | None = Field(default=None, alias="currentPassword", max_length=200)
    model_config = {"populate_by_name": True}


class PasswordChange(BaseModel):
    current_password: str = Field(alias="currentPassword", min_length=1, max_length=200)
    new_password: str = Field(alias="newPassword", min_length=8, max_length=200)
    model_config = {"populate_by_name": True}


class WeightBody(BaseModel):
    kg: float = Field(ge=20, le=400)
    date: dt.date | None = None


@router.patch("/account")
def patch_account(body: AccountPatch, user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    if body.email and body.email.lower() != user.email:
        # Changing the sign-in email needs the password, so a stolen session can't take over the account.
        if not body.current_password:
            raise HTTPException(403, "Enter your password to change your email.")
        require_password(user, body.current_password)
        user.email = body.email.lower().strip()
    if body.name is not None:
        user.name = body.name.strip()
        row = db.get(ProfileRow, user.id)
        if row is not None:
            row.data = {**row.data, "name": user.name}
            row.updated_at = utcnow()
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "An account with this email already exists")
    return {"email": user.email, "name": user.name}


@router.post("/account/password", status_code=204)
def change_password(body: PasswordChange, token: str = Depends(bearer), user: User = Depends(current_user),
                    db: Session = Depends(get_session)) -> Response:
    require_password(user, body.current_password)
    user.password_hash = hash_password(body.new_password)
    # Every other device has to sign in again with the new password.
    db.execute(delete(SessionToken).where(SessionToken.user_id == user.id,
                                          SessionToken.token_hash != token_digest(token)))
    db.commit()
    return Response(status_code=204)


@router.get("/sessions")
def list_sessions(token: str = Depends(bearer), user: User = Depends(current_user),
                  db: Session = Depends(get_session)) -> dict:
    mine = token_digest(token)
    rows = db.scalars(select(SessionToken).where(SessionToken.user_id == user.id)
                      .order_by(SessionToken.created_at.desc())).all()
    return {"sessions": [{
        "device": r.device or "Unknown device", "current": r.token_hash == mine,
        "createdAt": r.created_at.isoformat(), "lastUsedAt": r.last_used_at.isoformat() if r.last_used_at else None,
    } for r in rows]}


@router.post("/sessions/revoke-others", status_code=204)
def revoke_others(token: str = Depends(bearer), user: User = Depends(current_user),
                  db: Session = Depends(get_session)) -> Response:
    db.execute(delete(SessionToken).where(SessionToken.user_id == user.id, SessionToken.token_hash != token_digest(token)))
    db.commit()
    return Response(status_code=204)


@router.post("/calendar/rotate")
def rotate_calendar(user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    """New secret link. The old one stops working immediately."""
    user.calendar_token = secrets.token_urlsafe(24)
    db.commit()
    return {"calendarToken": user.calendar_token}


# ---------------------------------------------------------------- weight log

def _tz(profile: dict):
    try:
        return ZoneInfo(profile.get("timezone", "UTC"))
    except ZoneInfoNotFoundError:
        return timezone.utc


@router.post("/weights")
def log_weight(body: WeightBody, user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    profile = load_snapshot(db, user.id)["profile"]
    day = (body.date or datetime.now(_tz(profile)).date()).isoformat()
    row = db.get(Record, (user.id, "weight", day))
    if row is None:
        db.add(Record(user_id=user.id, kind="weight", rid=day, day=day, data={"kg": body.kg}))
    else:
        row.data, row.deleted, row.updated_at = {"kg": body.kg}, False, utcnow()
    # Keep the profile in step when the newest entry is logged. This does not touch the sync clock.
    latest = _latest_weight(db, user.id, extra=(day, body.kg))
    prow = db.get(ProfileRow, user.id)
    if prow is not None and latest is not None:
        prow.data = {**prow.data, "weightKg": latest}
    db.commit()
    return {"date": day, "kg": body.kg}


def _latest_weight(db: Session, user_id: str, extra: tuple[str, float] | None = None) -> float | None:
    rows = {r.day: r.data["kg"] for r in db.scalars(select(Record).where(
        Record.user_id == user_id, Record.kind == "weight", Record.deleted.is_(False)))}
    if extra:
        rows[extra[0]] = extra[1]
    return rows[max(rows)] if rows else None


@router.get("/weights")
def list_weights(user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    rows = db.scalars(select(Record).where(Record.user_id == user.id, Record.kind == "weight",
                                           Record.deleted.is_(False)).order_by(Record.day)).all()
    return {"weights": [{"date": r.day, "kg": r.data["kg"]} for r in rows]}


@router.delete("/weights/{day}", status_code=204)
def delete_weight(day: dt.date, user: User = Depends(current_user), db: Session = Depends(get_session)) -> Response:
    row = db.get(Record, (user.id, "weight", day.isoformat()))
    if row is not None:
        row.deleted = True
        db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- plan + stats

@router.post("/plan/recalculate")
def recalculate(user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    """Recompute calorie and macro targets from the saved body details and goal."""
    prow = db.get(ProfileRow, user.id)
    if prow is None or not prow.data.get("onboarded"):
        raise HTTPException(409, "Finish setup first.")
    d = prow.data
    result = build_plan(d.get("sex", "unspecified"), d.get("age", 28), d.get("heightCm", 175),
                        d.get("weightKg", 75), d.get("activity", "light"), d.get("goal", "lose"))
    prow.data = {**d, "calorieGoal": result.calories, "proteinGoal": result.protein_g,
                 "carbsGoal": result.carbs_g, "fatGoal": result.fat_g}
    prow.updated_at = utcnow()
    db.commit()
    snapshot = load_snapshot(db, user.id)
    snapshot["summary"] = {"weeklyChangeKg": result.weekly_change_kg}
    return snapshot


@router.get("/profile/stats")
def profile_stats(user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    profile = load_snapshot(db, user.id)["profile"]
    today = datetime.now(_tz(profile)).date()
    active_days = {r.day for r in db.scalars(select(Record).where(
        Record.user_id == user.id, Record.kind == "meal", Record.deleted.is_(False))) if r.day}
    logs = db.scalars(select(ActivityLog).where(ActivityLog.user_id == user.id)).all()
    set_days = {l.day for l in logs if l.kind == "set"}
    active_days |= {l.day for l in logs}
    # Streak: consecutive days up to today (or yesterday, if today is still empty) with anything logged.
    cursor = today if today.isoformat() in active_days else today - timedelta(days=1)
    streak = 0
    while cursor.isoformat() in active_days:
        streak += 1
        cursor -= timedelta(days=1)
    weights = list_weights(user, db)["weights"]
    change = round(weights[-1]["kg"] - weights[0]["kg"], 1) if len(weights) >= 2 else 0.0
    return {"streak": streak, "workouts": len(set_days), "weightChangeKg": change,
            "memberSince": as_utc(user.created_at).strftime("%Y-%m-%d")}
