"""Calorie plan, workout split and routine. Mirrors apple/Shared/PlanBuilder.swift.

General guidance only, never medical advice.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass

ACTIVITY_FACTOR = {"sitting": 1.2, "light": 1.375, "active": 1.55, "veryActive": 1.725}
GOAL_ADJUSTMENT = {"lose": -500, "build": 300, "maintain": 0, "healthier": 0}
SEX_TERM = {"male": 5, "female": -161, "unspecified": -78}


@dataclass
class PlanResult:
    calories: int
    protein_g: int
    carbs_g: int
    fat_g: int
    weekly_change_kg: float


def build_plan(sex: str, age: int, height_cm: float, weight_kg: float,
               activity: str, goal: str) -> PlanResult:
    bmr = 10 * weight_kg + 6.25 * height_cm - 5 * age + SEX_TERM.get(sex, -78)
    tdee = bmr * ACTIVITY_FACTOR.get(activity, 1.375)
    adjustment = GOAL_ADJUSTMENT.get(goal, 0)
    floor = max(1200, bmr * 0.9)  # never plan below a conservative minimum
    calories = max(tdee + adjustment, floor)
    protein_per_kg = 1.8 if goal in ("lose", "build") else 1.4
    protein = round(weight_kg * protein_per_kg)
    fat = round(calories * 0.25 / 9)
    carbs = max(0, round((calories - protein * 4 - fat * 9) / 4))
    return PlanResult(
        calories=int(round(calories / 10) * 10),
        protein_g=protein, carbs_g=carbs, fat_g=fat,
        weekly_change_kg=round((calories - tdee) * 7 / 7700, 1),
    )


def workout_weekdays(days_per_week: int) -> list[int]:
    """Calendar weekdays, 1 = Sunday. Spread out, avoiding back-to-back days where possible."""
    table = {
        1: [4], 2: [2, 5], 3: [2, 4, 6], 4: [2, 4, 6, 7],
        5: [2, 3, 5, 6, 7], 6: [2, 3, 4, 6, 7, 1],
    }
    return table[min(max(days_per_week, 1), 6)]


def _exercise(name: str, kg: float, reps: int, sets: int = 3, rest: int = 90) -> dict:
    return {
        "id": str(uuid.uuid4()).upper(), "name": name, "restSeconds": rest,
        "sets": [{"id": str(uuid.uuid4()).upper(), "weightKg": kg, "reps": reps} for _ in range(sets)],
    }


def upper_body() -> list[dict]:
    return [
        _exercise("Bench press", 40, 8, sets=4),
        _exercise("Overhead press", 25, 10),
        _exercise("Incline dumbbell press", 14, 10),
        _exercise("Seated cable row", 45, 12),
        _exercise("Triceps pushdown", 20, 12),
    ]


def lower_body() -> list[dict]:
    return [
        _exercise("Back squat", 50, 8, sets=4),
        _exercise("Romanian deadlift", 50, 10),
        _exercise("Leg press", 100, 12),
        _exercise("Calf raise", 40, 15),
    ]


def build_workout_days(days_per_week: int, start_minutes: int) -> list[dict]:
    days = []
    for index, weekday in enumerate(workout_weekdays(days_per_week)):
        upper = index % 2 == 0
        days.append({
            "id": str(uuid.uuid4()).upper(), "weekday": weekday,
            "title": "Upper body" if upper else "Lower body",
            "startMinutes": start_minutes,
            "exercises": upper_body() if upper else lower_body(),
        })
    return days


def build_reminders(wake: int, bed: int) -> list[dict]:
    items = [
        ("Brush teeth and stretch", wake + 5),
        ("Breakfast", wake + 45),
        ("Drink water", 10 * 60 + 30),
        ("Lunch", 13 * 60),
        ("Drink water", 15 * 60 + 30),
        ("Dinner", 19 * 60 + 30),
        ("Wind down", max(bed - 30, 0)),
    ]
    return [
        {"id": str(uuid.uuid4()).upper(), "title": title, "minutes": minutes % 1440, "oneOff": False}
        for title, minutes in items
    ]
