"""Recipe suggestions, weekly meal plan and shopping list."""
from __future__ import annotations

import json
import math
import os
import zlib
from collections import defaultdict
from datetime import date, timedelta
from functools import lru_cache
from pathlib import Path

DEFAULT_PATH = Path(__file__).resolve().parents[2] / "shared" / "recipes.json"
DIET_LEVEL = {"vegan": 0, "vegetarian": 1, "eggetarian": 2, "non-vegetarian": 3}
MEAL_SHARE = {"breakfast": 0.25, "lunch": 0.33, "dinner": 0.30, "snack": 0.12}
MEALS = list(MEAL_SHARE)


@lru_cache(maxsize=1)
def load_recipes() -> tuple[dict, ...]:
    path = Path(os.environ.get("PULSE_RECIPES_PATH", DEFAULT_PATH))
    return tuple(json.loads(path.read_text(encoding="utf-8"))["recipes"])


def get_recipe(recipe_id: str) -> dict | None:
    return next((r for r in load_recipes() if r["id"] == recipe_id), None)


def allowed(recipe: dict, diet: str, allergies: list[str]) -> bool:
    """A recipe is only suggested if it fits the diet AND has none of the user's allergens."""
    level = DIET_LEVEL.get(diet.lower(), 1)
    if DIET_LEVEL[recipe["diet"]] > level:
        return False
    avoid = {a.strip().lower() for a in allergies}
    return not (avoid & {a.lower() for a in recipe["allergens"]})


def suggest(diet: str, allergies: list[str], meal: str | None = None,
            max_minutes: int | None = None, max_kcal: int | None = None) -> list[dict]:
    results = []
    for recipe in load_recipes():
        if not allowed(recipe, diet, allergies):
            continue
        if meal and meal not in recipe["meals"]:
            continue
        if max_minutes and recipe["minutes"] > max_minutes:
            continue
        if max_kcal and recipe["kcal"] > max_kcal:
            continue
        results.append(recipe)
    return results


def scaled(recipe: dict, factor: float) -> dict:
    """A copy of the recipe with a different portion size. Never mutates the shared recipe."""
    if factor == 1:
        return {**recipe, "portion": 1}
    out = dict(recipe)
    for key in ("kcal", "protein", "carbs", "fat"):
        out[key] = round(recipe[key] * factor, 1) if key != "kcal" else round(recipe[key] * factor)
    out["ingredients"] = [{**i, "qty": round(i["qty"] * factor, 2)} for i in recipe["ingredients"]]
    out["portion"] = factor
    return out


def week_plan(start: date, diet: str, allergies: list[str], calorie_goal: int,
              overrides: dict[str, str] | None = None) -> dict:
    """Deterministic 7-day plan: per meal, pick the recipe closest to its calorie share,
    avoiding repeats from the last two days. `overrides` maps 'YYYY-MM-DD|meal' to a recipe id."""
    overrides = overrides or {}
    days: list[dict] = []
    recent: dict[str, list[str]] = defaultdict(list)
    for offset in range(7):
        day = start + timedelta(days=offset)
        entry: dict = {"date": day.isoformat(), "meals": {}}
        for meal in MEALS:
            pick = None
            override = get_recipe(overrides.get(f"{day.isoformat()}|{meal}", ""))
            if override and allowed(override, diet, allergies):
                pick = override
            else:
                pool = suggest(diet, allergies, meal)
                fresh = [r for r in pool if r["id"] not in recent[meal][-2:]] or pool
                target = calorie_goal * MEAL_SHARE[meal]
                # Tie-break by rotating through equally good options so the week varies.
                fresh.sort(key=lambda r: (round(abs(r["kcal"] - target) / 40), (zlib.crc32(r["id"].encode()) + offset) % 7))
                pick = fresh[0] if fresh else None
            if pick:
                recent[meal].append(pick["id"])
                entry["meals"][meal] = pick
        # Scale portions so the day lands near the calorie goal (quarter-portion steps, 0.8x to 1.5x).
        raw_total = sum(r["kcal"] for r in entry["meals"].values())
        factor = 1.0
        if raw_total:
            factor = round(min(max(calorie_goal / raw_total, 0.8), 1.5) * 4) / 4
        entry["meals"] = {m: scaled(r, factor) for m, r in entry["meals"].items()}
        entry["scale"] = factor
        entry["kcal"] = sum(r["kcal"] for r in entry["meals"].values())
        entry["protein"] = round(sum(r["protein"] for r in entry["meals"].values()), 1)
        days.append(entry)
    return {"start": start.isoformat(), "days": days}


def shopping_list(plan: dict) -> list[dict]:
    totals: dict[tuple[str, str], float] = defaultdict(float)
    for day in plan["days"]:
        for recipe in day["meals"].values():
            for item in recipe["ingredients"]:
                totals[(item["name"], item["unit"])] += item["qty"]
    countable = {"piece", "slice", "scoop"}   # you can't buy 7.5 onions
    weights = {"g", "ml"}                     # round up to the next 5 so the list reads like a shop list

    def tidy(qty: float, unit: str) -> float:
        if unit in countable:
            return math.ceil(qty - 1e-9)
        if unit in weights:
            return math.ceil(qty / 5 - 1e-9) * 5
        return round(qty, 1)

    return [{"name": name, "qty": tidy(qty, unit), "unit": unit} for (name, unit), qty in sorted(totals.items())]
