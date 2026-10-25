"""Wire format shared with the Swift apps (camelCase JSON, ISO-8601 UTC timestamps)."""
from __future__ import annotations

from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel


class Camel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="ignore")


def norm_dt(value: str | None) -> str | None:
    """Normalise to 'YYYY-MM-DDTHH:MM:SSZ', which Swift's .iso8601 strategy reads."""
    if not value:
        return None
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def norm_id(value: str) -> str:
    return value.upper()


class SetModel(Camel):
    id: str
    weight_kg: float
    reps: int
    done_on: str | None = None


class ExerciseModel(Camel):
    id: str
    name: str
    rest_seconds: int = 90
    sets: list[SetModel]


class WorkoutDayModel(Camel):
    id: str
    weekday: int = Field(ge=1, le=7)
    title: str
    start_minutes: int = Field(ge=0, lt=1440)
    exercises: list[ExerciseModel]


class ReminderModel(Camel):
    id: str
    title: str
    minutes: int = Field(ge=0, lt=1440)
    last_completed: str | None = None
    snoozed_until: str | None = None
    one_off: bool = False


class MealModel(Camel):
    id: str
    name: str
    quantity: float = 1
    unit: str = "serving"
    calories: int = Field(ge=0, le=10000)
    protein: float = 0
    carbs: float = 0
    fat: float = 0
    date: str
    source: str = "manual"


class ProfileModel(Camel):
    name: str = ""
    calorie_goal: int = 2000
    protein_goal: int = 120
    carbs_goal: int = 220
    fat_goal: int = 60
    active_goal: int = 600
    diet: str = "Vegetarian"
    quiet_start: int = 22 * 60 + 30
    quiet_end: int = 6 * 60
    onboarded: bool = False
    # Extras used by the web app. The Swift apps ignore them and the server keeps them.
    timezone: str = "UTC"
    allergies: list[str] = []
    sex: str = "unspecified"
    age: int = 28
    height_cm: float = 175
    weight_kg: float = 75
    target_kg: float = 72
    goal: str = "lose"
    activity: str = "light"
    days_per_week: int = 4
    wake_minutes: int = 390
    bed_minutes: int = 1350
    workout_minutes: int = 1110
    ai_provider: str = ""


class SnapshotModel(Camel):
    profile: ProfileModel = ProfileModel()
    meals: list[MealModel] = []
    plan: list[WorkoutDayModel] = []
    reminders: list[ReminderModel] = []
    updated_at: str = "1970-01-01T00:00:00Z"
    deleted_ids: list[str] = []


class SignupRequest(Camel):
    email: str = Field(min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    password: str = Field(min_length=8, max_length=200)
    name: str = Field(default="", max_length=100)


class LoginRequest(Camel):
    email: str
    password: str


class AuthResponse(Camel):
    token: str
    user_id: str
    email: str
    name: str


class OnboardingRequest(Camel):
    name: str = Field(min_length=1, max_length=100)
    sex: str = "unspecified"
    age: int = Field(default=28, ge=13, le=90)
    height_cm: float = Field(default=175, ge=120, le=220)
    weight_kg: float = Field(default=75, ge=35, le=250)
    target_kg: float = Field(default=72, ge=35, le=250)
    goal: str = "lose"
    activity: str = "light"
    days_per_week: int = Field(default=4, ge=1, le=6)
    diet: str = "Vegetarian"
    allergies: list[str] = []
    wake_minutes: int = Field(default=390, ge=0, lt=1440)
    bed_minutes: int = Field(default=1350, ge=0, lt=1440)
    workout_minutes: int = Field(default=1110, ge=0, lt=1440)
    timezone: str = "UTC"
