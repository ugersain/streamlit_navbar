"""Trends for the Insights screen, computed from meals and the activity log."""
from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import ActivityLog, Record


def compute(db: Session, user_id: str, profile: dict, reminders: list[dict], plan: list[dict],
            today: date, days: int = 30) -> dict:
    start = today - timedelta(days=days - 1)
    first = start.isoformat()

    meal_rows = db.scalars(select(Record).where(
        Record.user_id == user_id, Record.kind == "meal", Record.deleted.is_(False),
        Record.day >= first)).all()
    totals: dict[str, dict] = defaultdict(lambda: {"calories": 0, "protein": 0.0, "carbs": 0.0, "fat": 0.0})
    for row in meal_rows:
        t = totals[row.day]
        t["calories"] += row.data.get("calories", 0)
        t["protein"] += row.data.get("protein", 0)
        t["carbs"] += row.data.get("carbs", 0)
        t["fat"] += row.data.get("fat", 0)

    logs = db.scalars(select(ActivityLog).where(ActivityLog.user_id == user_id, ActivityLog.day >= first)).all()
    sets_by_day: dict[str, dict] = defaultdict(lambda: {"sets": 0, "volume": 0.0, "title": ""})
    habits_by_day: dict[str, int] = defaultdict(int)
    for log in logs:
        if log.kind == "set":
            entry = sets_by_day[log.day]
            entry["sets"] += 1
            entry["volume"] += log.value
            entry["title"] = log.label
        else:
            habits_by_day[log.day] += 1

    daily = []
    for offset in range(days):
        day = (start + timedelta(days=offset)).isoformat()
        t = totals.get(day, {"calories": 0, "protein": 0.0, "carbs": 0.0, "fat": 0.0})
        s = sets_by_day.get(day, {"sets": 0, "volume": 0.0, "title": ""})
        daily.append({
            "date": day, "calories": t["calories"], "protein": round(t["protein"], 1),
            "carbs": round(t["carbs"], 1), "fat": round(t["fat"], 1),
            "sets": s["sets"], "volume": round(s["volume"]), "workout": s["title"],
            "habits": habits_by_day.get(day, 0),
        })

    logged = [d for d in daily if d["calories"] > 0]
    protein_goal = profile.get("proteinGoal", 120)
    daily_habits = len([r for r in reminders if not r.get("oneOff")]) or 1
    sessions = [d for d in daily if d["sets"] > 0]

    weeks: dict[str, dict] = {}
    for d in daily:
        monday = date.fromisoformat(d["date"])
        monday -= timedelta(days=monday.weekday())
        w = weeks.setdefault(monday.isoformat(), {"week": monday.isoformat(), "sessions": 0, "volume": 0})
        if d["sets"] > 0:
            w["sessions"] += 1
        w["volume"] += d["volume"]

    planned_per_week = len(plan)
    weeks_in_range = max(days / 7, 1)
    return {
        "days": daily,
        "weeks": sorted(weeks.values(), key=lambda w: w["week"]),
        "summary": {
            "avgCalories": round(sum(d["calories"] for d in logged) / len(logged)) if logged else 0,
            "avgProtein": round(sum(d["protein"] for d in logged) / len(logged)) if logged else 0,
            "daysLogged": len(logged),
            "proteinDaysOnTarget": sum(1 for d in logged if d["protein"] >= protein_goal * 0.9),
            "workoutsDone": len(sessions),
            "workoutsPlanned": round(planned_per_week * weeks_in_range),
            "habitRate": round(100 * sum(d["habits"] for d in daily) / (daily_habits * days)),
            "calorieGoal": profile.get("calorieGoal", 2000),
            "proteinGoal": protein_goal,
        },
    }
