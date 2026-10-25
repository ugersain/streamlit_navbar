from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class UserContext(BaseModel):
    """Small snapshot of the user's day, so answers are specific."""
    calorie_goal: int = 2000
    calories_eaten: int = 0
    protein_goal: int = 120
    protein_eaten: float = 0
    diet: str | None = None
    workout_today: str | None = None


class Turn(BaseModel):
    role: Literal["user", "assistant"]
    text: str


class AssistRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    context: UserContext = UserContext()
    history: list[Turn] = Field(default_factory=list, max_length=12)


class FoodItem(BaseModel):
    name: str
    quantity: float
    unit: str
    calories: int
    protein: float
    carbs: float
    fat: float
    confident: bool


class Action(BaseModel):
    type: Literal["log_meal", "add_reminder", "none"]
    items: list[FoodItem] = Field(default_factory=list)
    title: str | None = None
    minutes_from_now: int | None = None
    needs_confirmation: bool = False


class AssistResponse(BaseModel):
    reply: str
    actions: list[Action]
    provider: str
    notice: str | None = None     # for example: your API key was rejected
