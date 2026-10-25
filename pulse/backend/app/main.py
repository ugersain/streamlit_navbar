from __future__ import annotations

import json
import os
import secrets
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import account, connectors, ics, insights, recipes
from .api_models import (AuthResponse, LoginRequest, OnboardingRequest, SignupRequest,
                         SnapshotModel)
from .db import ActivityLog, Connector, ProfileRow, Record, SessionToken, User, get_session, utcnow
from .plan import build_plan, build_reminders, build_workout_days
from .providers import PROVIDER_CLASSES, LocalProvider, Provider, configured_providers, get_provider
from .schemas import AssistRequest, AssistResponse, UserContext
from .security import (RateLimiter, create_session, current_user, bearer, hash_password, login_limiter,
                       revoke_session, verify_password)
from .service import assist
from .state import load_snapshot, merge_snapshot

app = FastAPI(title="Pulse API", version="0.3.0")
app.include_router(connectors.router)
app.include_router(account.router)

CSP = ("default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
       "font-src https://fonts.gstatic.com; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; "
       "base-uri 'none'; form-action 'self'; object-src 'none'")
MAX_BODY = 1_000_000


@app.middleware("http")
async def security_headers(request: Request, call_next):
    """Strict headers on everything, and no caching of API responses (they hold personal data)."""
    length = request.headers.get("content-length")
    if length and length.isdigit() and int(length) > MAX_BODY:
        return Response("Request too large", status_code=413)
    response = await call_next(request)
    response.headers["Content-Security-Policy"] = CSP
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "microphone=(self), camera=(), geolocation=()"
    if request.url.path.startswith("/v1/"):
        response.headers["Cache-Control"] = "no-store"
    if request.url.scheme == "https" or request.headers.get("x-forwarded-proto") == "https":
        response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
    return response


@app.exception_handler(RequestValidationError)
async def validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
    """FastAPI's default error repeats the submitted value. That would echo API keys and passwords back,
    so report only which field is wrong and why."""
    errors = [{"loc": [str(p) for p in e.get("loc", []) if p != "body"], "msg": e.get("msg", "Invalid value"),
               "type": e.get("type", "value_error")} for e in exc.errors()]
    return JSONResponse(status_code=422, content={"detail": errors})


def provider_dependency(client: httpx.AsyncClient = Depends(connectors.http_client)) -> Provider:
    return get_provider(client=client)


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
    return AuthResponse(token=create_session(db, user.id, request.headers.get("user-agent")), user_id=user.id, email=user.email, name=user.name)


@app.post("/v1/auth/login", response_model=AuthResponse)
def login(body: LoginRequest, request: Request, db: Session = Depends(get_session)) -> AuthResponse:
    login_limiter.check(_client_key(request, body.email))
    user = db.scalar(select(User).where(User.email == body.email.lower().strip()))
    # Same error for unknown email and wrong password, so accounts can't be probed.
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(401, "Incorrect email or password")
    return AuthResponse(token=create_session(db, user.id, request.headers.get("user-agent")), user_id=user.id, email=user.email, name=user.name)


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
    for table in (ActivityLog, Record, ProfileRow, SessionToken, Connector):
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
        # Which providers you connected. The keys themselves are never exported, by design.
        "aiConnectors": [{"provider": c.provider, "last4": c.last4, "addedAt": c.created_at.isoformat()}
                         for c in db.scalars(select(Connector).where(Connector.user_id == user.id))],
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


assist_limiter = RateLimiter(attempts=30, window_seconds=60)
SERVER_KEY_DAILY_LIMIT = int(os.environ.get("PULSE_SERVER_KEY_DAILY_LIMIT", "200"))
_daily_use: dict[str, tuple[str, int]] = {}


def _over_daily_limit(user_id: str) -> bool:
    """Requests that use the server's own key are capped per user per day, to protect its cost."""
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    day, count = _daily_use.get(user_id, (today, 0))
    if day != today:
        count = 0
    _daily_use[user_id] = (today, count + 1)
    return count + 1 > SERVER_KEY_DAILY_LIMIT


@app.post("/v1/assist", response_model=AssistResponse)
async def assist_endpoint(req: AssistRequest, user: User = Depends(current_user),
                          db: Session = Depends(get_session),
                          provider: Provider = Depends(provider_dependency),
                          client: httpx.AsyncClient = Depends(connectors.http_client)) -> AssistResponse:
    assist_limiter.check(user.id)
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
    notice = None
    own = connectors.resolve_own_provider(db, user, chosen, client)
    if own:
        provider = own.provider                      # the user's own key always wins
    else:
        is_default = type(provider) in (LocalProvider, *PROVIDER_CLASSES.values())
        if is_default and chosen in configured_providers():
            provider = get_provider(chosen, client)  # the user's pick, when the server has that key
        if provider.name != "local" and _over_daily_limit(user.id):
            provider = LocalProvider()
            notice = "You've reached today's limit for the shared assistant. Add your own API key in Profile to keep going."

    try:
        result = await assist(req, provider)
        if own:
            connectors.mark_used(db, own.row)
            result.provider = f"{own.row.provider} (your key)"
    except httpx.HTTPStatusError as exc:
        result = await assist(req, LocalProvider())
        result.provider = "local (fallback)"
        if own and exc.response.status_code in (401, 403):
            connectors.mark_rejected(db, own.row)
            notice = f"Your {own.row.provider} key was rejected, so Pulse used the built-in parser. Update the key in Profile."
        elif own and exc.response.status_code == 429:
            notice = "Your AI provider is rate limiting you right now, so Pulse used the built-in parser."
    except Exception as exc:  # provider outage: degrade to the rule-based parser
        result = await assist(req, LocalProvider())
        result.provider = f"local (fallback after {type(exc).__name__})"
    result.notice = notice
    return result


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
