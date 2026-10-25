import pytest

from app.foods import find_food, ground, parse_meal_text, singular
from app.plan import build_plan, build_reminders, build_workout_days, workout_weekdays


def test_spec_example():
    items = parse_meal_text("Log two rotis, one bowl of dal, and a cup of curd")
    assert [(i.name, i.quantity, i.calories) for i in items] == [("roti", 2, 210), ("dal", 1, 180), ("curd", 1, 98)]
    assert all(i.confident for i in items)


@pytest.mark.parametrize("text,expected", [
    ("I had 3 eggs and a banana", [("egg", 3), ("banana", 1)]),
    ("ate two idlis with sambar", [("idli", 2)]),
    ("add half a cup of rice", [("rice", 0.5)]),
    ("1.5 cups of milk", [("milk", 1.5)]),
    ("a couple of samosas", [("samosa", 2)]),
    ("Log an apple.", [("apple", 1)]),
    ("two teaspoons of ghee", [("ghee", 2)]),
])
def test_parse_variants(text, expected):
    got = [(i.name, i.quantity) for i in parse_meal_text(text) if i.confident]
    assert got[: len(expected)] == expected


def test_unknown_food_flagged_not_invented():
    item = ground("dragon fruit smoothie", 1)
    assert not item.confident and item.calories == 0


def test_longest_alias_wins_and_plurals():
    assert ground("greek yogurt").name == "greek yogurt"
    assert ground("curd").name == "curd"
    assert find_food("chapatis").id == "roti"
    assert singular("dishes") == "dish" and singular("berries") == "berry" and singular("glass") == "glass"


def test_zero_or_negative_quantity_defaults_to_one():
    assert ground("egg", 0).quantity == 1
    assert ground("egg", -3).quantity == 1


def test_empty_text_parses_to_nothing():
    assert parse_meal_text("   ") == []


def test_plan_lose_vs_maintain_vs_build():
    base = dict(sex="male", age=28, height_cm=175, weight_kg=78.5, activity="light")
    lose, keep, build = (build_plan(goal=g, **base) for g in ("lose", "maintain", "build"))
    assert lose.calories < keep.calories < build.calories
    assert lose.weekly_change_kg < 0 < build.weekly_change_kg
    assert keep.weekly_change_kg == 0


def test_plan_floor_protects_small_users():
    plan = build_plan("female", 28, 150, 40, "sitting", "lose")
    assert plan.calories >= 1200


def test_macros_add_up():
    plan = build_plan("male", 30, 180, 85, "active", "build")
    kcal = plan.protein_g * 4 + plan.carbs_g * 4 + plan.fat_g * 9
    assert abs(kcal - plan.calories) <= 40


@pytest.mark.parametrize("days", range(1, 7))
def test_workout_days_count_and_validity(days):
    weekdays = workout_weekdays(days)
    assert len(weekdays) == days and len(set(weekdays)) == days and all(1 <= w <= 7 for w in weekdays)
    built = build_workout_days(days, 1110)
    assert len(built) == days and all(d["exercises"] for d in built)


def test_workout_days_clamped():
    assert len(workout_weekdays(0)) == 1 and len(workout_weekdays(99)) == 6


def test_reminders_follow_wake_and_bed_time():
    reminders = build_reminders(wake=360, bed=1380)
    titles = {r["title"]: r["minutes"] for r in reminders}
    assert titles["Breakfast"] == 405 and titles["Wind down"] == 1350
    assert all(0 <= r["minutes"] < 1440 for r in reminders)
