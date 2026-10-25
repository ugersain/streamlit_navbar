from __future__ import annotations

import json
import secrets
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import ics, insights, recipes
from .api_models import (AuthResponse, LoginRequest, OnboardingRequest, SignupRequest,
                         SnapshotModel)
from .db import ActivityLog, ProfileRow, Record, SessionToken, User, get_session, utcnow
from .plan import build_plan, build_reminders, build_workout_days
from .providers import LocalProvider, Provider, configured_providers, get_provider
from .schemas import AssistRequest, AssistResponse, UserContext
from .security import (create_session, current_user, bearer, hash_password, login_limiter,
                       revoke_session, verify_password)
from .service import assist
from .state import load_snapshot, merge_snapshot

app = FastAPI(title="Pulse API", version="0.2.0")


def provider_dependency() -> Provider:
    return get_provider()


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}


def _client_key(request: Request, email: str) -> str:
    return f"{request.client.host if request.client else '?'}|{email.lower()}"


# ---------------------------------------------------------------- accounts

@app.post("/v1/auth/signup", response_model=AuthResponse)
def signup(body: SignupRequest, request: Request, db: Session = Depends(get_session)) -> AuthResponse:
    login_limiter.check(_client_key(request, body.email))
    user = User(id=str(uuid.uuid4()), email=body.email.lower().strip(), name=body.name.strip(),
                password_hash=hash_password(body.password), calendar_token=secrets.token_urlsafe(24))
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "An account with this email already exists")
    return AuthResponse(token=create_session(db, user.id), user_id=user.id, email=user.email, name=user.name)


@app.post("/v1/auth/login", response_model=AuthResponse)
def login(body: LoginRequest, request: Request, db: Session = Depends(get_session)) -> AuthResponse:
    login_limiter.check(_client_key(request, body.email))
    user = db.scalar(select(User).where(User.email == body.email.lower().strip()))
    # Same error for unknown email and wrong password, so accounts can't be probed.
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(401, "Incorrect email or password")
    return AuthResponse(token=create_session(db, user.id), user_id=user.id, email=user.email, name=user.name)


@app.post("/v1/auth/logout", status_code=204)
def logout(token: str = Depends(bearer), user: User = Depends(current_user),
           db: Session = Depends(get_session)) -> Response:
    revoke_session(db, token)
    return Response(status_code=204)


@app.get("/v1/me")
def me(user: User = Depends(current_user)) -> dict:
    return {"userId": user.id, "email": user.email, "name": user.name,
            "calendarToken": user.calendar_token}


@app.delete("/v1/account", status_code=204)
def delete_account(user: User = Depends(current_user), db: Session = Depends(get_session)) -> Response:
    """Permanently deletes the account and every record, session and log."""
    for table in (ActivityLog, Record, ProfileRow, SessionToken):
        db.execute(delete(table).where(table.user_id == user.id))
    db.execute(delete(User).where(User.id == user.id))
    db.commit()
    return Response(status_code=204)


@app.get("/v1/export")
def export(user: User = Depends(current_user), db: Session = Depends(get_session)) -> Response:
    logs = db.scalars(select(ActivityLog).where(ActivityLog.user_id == user.id)).all()
    body = {
        "exportedAt": utcnow().isoformat(),
        "account": {"email": user.email, "name": user.name, "createdAt": user.created_at.isoformat()},
        "data": load_snapshot(db, user.id),
        "activityLog": [{"kind": l.kind, "day": l.day, "label": l.label, "value": l.value} for l in logs],
    }
    return Response(json.dumps(body, indent=2), media_type="application/json",
                    headers={"Content-Disposition": 'attachment; filename="pulse-export.json"'})


# ---------------------------------------------------------------- sync

@app.get("/v1/state")
def get_state(user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    return load_snapshot(db, user.id)


@app.put("/v1/state")
def put_state(snapshot: SnapshotModel, user: User = Depends(current_user),
              db: Session = Depends(get_session)) -> dict:
    return merge_snapshot(db, user.id, snapshot)


@app.post("/v1/onboarding")
def onboarding(body: OnboardingRequest, user: User = Depends(current_user),
               db: Session = Depends(get_session)) -> dict:
    """Turns the onboarding answers into targets, a workout split and a routine."""
    result = build_plan(body.sex, body.age, body.height_cm, body.weight_kg, body.activity, body.goal)
    try:
        ZoneInfo(body.timezone)
        tz = body.timezone
    except (ZoneInfoNotFoundError, ValueError):
        tz = "UTC"
    row = db.get(ProfileRow, user.id) or ProfileRow(user_id=user.id, data={})
    row.data = {
        **row.data,
        "name": body.name, "calorieGoal": result.calories, "proteinGoal": result.protein_g,
        "carbsGoal": result.carbs_g, "fatGoal": result.fat_g, "diet": body.diet,
        "quietStart": body.bed_minutes, "quietEnd": max(body.wake_minutes - 30, 0), "onboarded": True,
        "timezone": tz, "allergies": body.allergies, "sex": body.sex, "age": body.age,
        "heightCm": body.height_cm, "weightKg": body.weight_kg, "targetKg": body.target_kg,
        "goal": body.goal, "activity": body.activity, "daysPerWeek": body.days_per_week,
        "wakeMinutes": body.wake_minutes, "bedMinutes": body.bed_minutes,
        "workoutMinutes": body.workout_minutes,
    }
    row.updated_at = utcnow()
    db.merge(row)
    from .state import _replace
    _replace(db, user.id, "plan", {d["id"]: d for d in build_workout_days(body.days_per_week, body.workout_minutes)})
    _replace(db, user.id, "reminder", {r["id"]: r for r in build_reminders(body.wake_minutes, body.bed_minutes)})
    user.name = body.name
    db.commit()
    snapshot = load_snapshot(db, user.id)
    snapshot["summary"] = {"weeklyChangeKg": result.weekly_change_kg}
    return snapshot


# ---------------------------------------------------------------- food, plans, insights

def _profile(db: Session, user: User) -> dict:
    return load_snapshot(db, user.id)["profile"]


@app.get("/v1/recipes")
def list_recipes(meal: str | None = None, max_minutes: int | None = Query(default=None, ge=1),
                 max_kcal: int | None = Query(default=None, ge=1),
                 user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    profile = _profile(db, user)
    found = recipes.suggest(profile["diet"], profile["allergies"], meal, max_minutes, max_kcal)
    return {"recipes": found}


class OverrideBody(BaseModel):
    date: str
    meal: str
    recipe_id: str


@app.get("/v1/meal-plan")
def meal_plan(start: date | None = None, user: User = Depends(current_user),
              db: Session = Depends(get_session)) -> dict:
    profile = _profile(db, user)
    overrides = {r.rid: r.data["recipeId"] for r in db.scalars(select(Record).where(
        Record.user_id == user.id, Record.kind == "mealplan", Record.deleted.is_(False)))}
    monday = start or _local_today(profile["timezone"])
    plan = recipes.week_plan(monday, profile["diet"], profile["allergies"], profile["calorieGoal"], overrides)
    plan["shopping"] = recipes.shopping_list(plan)
    return plan


@app.put("/v1/meal-plan/override", status_code=204)
def override_meal(body: OverrideBody, user: User = Depends(current_user),
                  db: Session = Depends(get_session)) -> Response:
    profile = _profile(db, user)
    recipe = recipes.get_recipe(body.recipe_id)
    if recipe is None or body.meal not in recipes.MEALS:
        raise HTTPException(404, "Unknown recipe or meal")
    if not recipes.allowed(recipe, profile["diet"], profile["allergies"]):
        raise HTTPException(422, "That recipe doesn't fit your diet or allergies")
    rid = f"{body.date}|{body.meal}"
    row = db.get(Record, (user.id, "mealplan", rid))
    if row is None:
        db.add(Record(user_id=user.id, kind="mealplan", rid=rid, day=body.date, data={"recipeId": recipe["id"]}))
    else:
        row.data, row.deleted = {"recipeId": recipe["id"]}, False
    db.commit()
    return Response(status_code=204)


def _local_today(tz_name: str) -> date:
    try:
        zone = ZoneInfo(tz_name)
    except (ZoneInfoNotFoundError, ValueError):
        zone = timezone.utc
    today = datetime.now(zone).date()
    return today - timedelta(days=today.weekday())


@app.get("/v1/insights")
def get_insights(days: int = Query(default=30, ge=7, le=180), user: User = Depends(current_user),
                 db: Session = Depends(get_session)) -> dict:
    snapshot = load_snapshot(db, user.id)
    tz = snapshot["profile"]["timezone"]
    try:
        today = datetime.now(ZoneInfo(tz)).date()
    except ZoneInfoNotFoundError:
        today = datetime.now(timezone.utc).date()
    return insights.compute(db, user.id, snapshot["profile"], snapshot["reminders"], snapshot["plan"], today, days)


@app.get("/v1/calendar/{token}.ics")
def calendar_feed(token: str, db: Session = Depends(get_session)) -> Response:
    """Subscribe in Apple Calendar or Google Calendar. The secret token in the URL is the login."""
    user = db.scalar(select(User).where(User.calendar_token == token))
    if user is None:
        raise HTTPException(404, "Not found")
    snapshot = load_snapshot(db, user.id)
    body = ics.build_calendar(user.id, snapshot["plan"], snapshot["profile"]["timezone"])
    return PlainTextResponse(body, media_type="text/calendar; charset=utf-8")


# ---------------------------------------------------------------- assistant

@app.get("/v1/providers")
def providers(user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    """Which AI providers this server can use, and which one this user picked."""
    chosen = _profile(db, user).get("aiProvider", "")
    available = configured_providers()
    active = chosen if chosen in available else get_provider().name
    return {"available": available, "chosen": chosen, "active": active}


@app.post("/v1/assist", response_model=AssistResponse)
async def assist_endpoint(req: AssistRequest, user: User = Depends(current_user),
                          db: Session = Depends(get_session),
                          provider: Provider = Depends(provider_dependency)) -> AssistResponse:
    snapshot = load_snapshot(db, user.id)
    profile = snapshot["profile"]
    tz = profile["timezone"]
    today = datetime.now(ZoneInfo(tz) if tz else timezone.utc).strftime("%Y-%m-%d")
    todays = [m for m in snapshot["meals"] if m["date"] and _day(m["date"], tz) == today]
    # The server knows the user's real day, so don't trust numbers sent by the client.
    req.context = UserContext(
        calorie_goal=profile["calorieGoal"], calories_eaten=sum(m["calories"] for m in todays),
        protein_goal=profile["proteinGoal"], protein_eaten=sum(m["protein"] for m in todays),
        diet=profile["diet"], workout_today=_todays_workout(snapshot["plan"], tz))
    chosen = profile.get("aiProvider", "")
    if chosen in configured_providers() and isinstance(provider, type(get_provider())):
        provider = get_provider(chosen)   # the user's own pick, when the server has its key
    try:
        return await assist(req, provider)
    except Exception as exc:  # provider outage: degrade to the rule-based parser
        fallback = await assist(req, LocalProvider())
        fallback.provider = f"local (fallback after {type(exc).__name__})"
        return fallback


def _day(iso: str, tz: str) -> str:
    from .state import local_day
    return local_day(iso, tz)


def _todays_workout(plan: list[dict], tz: str) -> str | None:
    try:
        now = datetime.now(ZoneInfo(tz))
    except ZoneInfoNotFoundError:
        now = datetime.now(timezone.utc)
    weekday = (now.weekday() + 2 - 1) % 7 + 1  # Monday=0 -> calendar weekday 2
    return next((d["title"] for d in plan if d["weekday"] == weekday), None)


# ---------------------------------------------------------------- web app (static)

WEB_DIR = Path(__file__).resolve().parents[2] / "web"
if WEB_DIR.exists():
    @app.get("/", include_in_schema=False)
    def index() -> FileResponse:
        return FileResponse(WEB_DIR / "index.html")

    app.mount("/", StaticFiles(directory=WEB_DIR), name="web")
