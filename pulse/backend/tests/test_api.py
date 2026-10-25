import json
from datetime import datetime, timedelta, timezone

import pytest

from app.main import app, provider_dependency
from conftest import ONBOARDING, signup

NOW = datetime.now(timezone.utc)


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def meal(name="Roti", kcal=210, protein=6.0, when=None, id="11111111-1111-1111-1111-111111111111"):
    return {"id": id, "name": name, "calories": kcal, "protein": protein, "carbs": 30, "fat": 5,
            "date": iso(when or NOW)}


# ------------------------------------------------------------------ auth
def test_health(client):
    assert client.get("/healthz").json() == {"ok": True}


def test_signup_login_me_logout(client):
    data = signup(client)
    assert data["email"] == "a@example.com" and len(data["token"]) > 20
    me = client.get("/v1/me", headers={"Authorization": f"Bearer {data['token']}"})
    assert me.status_code == 200 and me.json()["name"] == "Aarav" and me.json()["calendarToken"]
    login = client.post("/v1/auth/login", json={"email": "A@Example.com", "password": "correct horse"})
    assert login.status_code == 200
    h = {"Authorization": f"Bearer {login.json()['token']}"}
    assert client.post("/v1/auth/logout", headers=h).status_code == 204
    assert client.get("/v1/me", headers=h).status_code == 401


def test_signup_validation_and_duplicates(client):
    assert client.post("/v1/auth/signup", json={"email": "bad", "password": "longenough"}).status_code == 422
    assert client.post("/v1/auth/signup", json={"email": "x@y.co", "password": "short"}).status_code == 422
    signup(client)
    dup = client.post("/v1/auth/signup", json={"email": "a@example.com", "password": "another one!"})
    assert dup.status_code == 409


def test_login_failures_are_generic(client):
    signup(client)
    wrong = client.post("/v1/auth/login", json={"email": "a@example.com", "password": "nope nope"})
    unknown = client.post("/v1/auth/login", json={"email": "who@example.com", "password": "nope nope"})
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json() == unknown.json()


def test_login_is_rate_limited(client):
    signup(client)
    codes = [client.post("/v1/auth/login", json={"email": "a@example.com", "password": "bad bad bad"}).status_code
             for _ in range(12)]
    assert 429 in codes


def test_passwords_are_hashed_and_tokens_not_stored(client):
    from app.db import SessionToken, User, get_database
    data = signup(client)
    with get_database().factory() as db:
        user = db.query(User).one()
        assert "correct horse" not in user.password_hash and user.password_hash.startswith("scrypt$")
        assert all(row.token_hash != data["token"] for row in db.query(SessionToken))


@pytest.mark.parametrize("path", ["/v1/me", "/v1/state", "/v1/recipes", "/v1/meal-plan", "/v1/insights", "/v1/export"])
def test_endpoints_require_auth(client, path):
    assert client.get(path).status_code == 401
    assert client.get(path, headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_users_cannot_see_each_others_data(client):
    a = {"Authorization": f"Bearer {signup(client, 'a@x.com')['token']}"}
    b = {"Authorization": f"Bearer {signup(client, 'b@x.com')['token']}"}
    client.put("/v1/state", json={"meals": [meal()], "updatedAt": iso(NOW)}, headers=a)
    assert len(client.get("/v1/state", headers=a).json()["meals"]) == 1
    assert client.get("/v1/state", headers=b).json()["meals"] == []


# ------------------------------------------------------------------ onboarding + sync
def test_onboarding_builds_everything(client, auth):
    r = client.post("/v1/onboarding", json=ONBOARDING, headers=auth)
    assert r.status_code == 200
    s = r.json()
    assert s["profile"]["onboarded"] and s["profile"]["name"] == "Aarav"
    assert 1500 < s["profile"]["calorieGoal"] < 2600 and s["profile"]["proteinGoal"] > 100
    assert len(s["plan"]) == 4 and len(s["reminders"]) == 7
    assert s["summary"]["weeklyChangeKg"] < 0
    assert s["profile"]["allergies"] == ["Peanuts"] and s["profile"]["timezone"] == "Asia/Kolkata"
    # idempotent: running again replaces rather than duplicates
    again = client.post("/v1/onboarding", json={**ONBOARDING, "daysPerWeek": 3}, headers=auth).json()
    assert len(again["plan"]) == 3 and len(again["reminders"]) == 7


@pytest.mark.parametrize("bad", [{"age": 5}, {"weightKg": 1}, {"daysPerWeek": 9}, {"name": ""}, {"wakeMinutes": 5000}])
def test_onboarding_validation(client, auth, bad):
    assert client.post("/v1/onboarding", json={**ONBOARDING, **bad}, headers=auth).status_code == 422


def test_bad_timezone_falls_back_to_utc(client, auth):
    s = client.post("/v1/onboarding", json={**ONBOARDING, "timezone": "Mars/Base"}, headers=auth).json()
    assert s["profile"]["timezone"] == "UTC"


def test_sync_roundtrip_and_merge_rules(client, auth):
    client.post("/v1/onboarding", json=ONBOARDING, headers=auth)
    state = client.get("/v1/state", headers=auth).json()

    # device A logs a meal with a newer snapshot
    state["meals"] = [meal(id="aaaaaaaa-0000-0000-0000-000000000001", name="Dal")]
    state["updatedAt"] = iso(NOW + timedelta(minutes=1))
    state["profile"]["calorieGoal"] = 1800
    merged = client.put("/v1/state", json=state, headers=auth).json()
    assert merged["profile"]["calorieGoal"] == 1800
    assert merged["meals"][0]["id"] == "AAAAAAAA-0000-0000-0000-000000000001"   # ids normalised

    # device B is stale (older) but has an offline meal: meal merged, settings NOT overwritten
    stale = {"profile": {"calorieGoal": 999}, "meals": [meal(id="bbbbbbbb-0000-0000-0000-000000000002", name="Egg")],
             "plan": [], "reminders": [], "updatedAt": iso(NOW - timedelta(days=1))}
    merged = client.put("/v1/state", json=stale, headers=auth).json()
    assert {m["name"] for m in merged["meals"]} == {"Dal", "Egg"}
    assert merged["profile"]["calorieGoal"] == 1800
    assert len(merged["plan"]) == 4


def test_deleted_meals_stay_deleted(client, auth):
    mid = "cccccccc-0000-0000-0000-000000000003"
    client.put("/v1/state", json={"meals": [meal(id=mid)], "updatedAt": iso(NOW)}, headers=auth)
    out = client.put("/v1/state", json={"deletedIds": [mid], "updatedAt": iso(NOW)}, headers=auth).json()
    assert out["meals"] == []
    # a stale device re-sends the same meal: it must not come back
    out = client.put("/v1/state", json={"meals": [meal(id=mid)], "updatedAt": iso(NOW)}, headers=auth).json()
    assert out["meals"] == []


def test_profile_extras_survive_a_swift_style_push(client, auth):
    client.post("/v1/onboarding", json=ONBOARDING, headers=auth)
    swift_profile = {"name": "Aarav", "calorieGoal": 2100, "onboarded": True}   # no web-only fields
    out = client.put("/v1/state", json={"profile": swift_profile, "updatedAt": iso(NOW + timedelta(minutes=5))},
                     headers=auth).json()
    assert out["profile"]["calorieGoal"] == 2100 and out["profile"]["allergies"] == ["Peanuts"]


def test_completing_sets_and_reminders(client, auth):
    s = client.post("/v1/onboarding", json=ONBOARDING, headers=auth).json()
    s["plan"][0]["exercises"][0]["sets"][0]["doneOn"] = iso(NOW)
    s["reminders"][0]["lastCompleted"] = iso(NOW)
    s["updatedAt"] = iso(NOW + timedelta(seconds=30))
    out = client.put("/v1/state", json=s, headers=auth).json()
    assert out["plan"][0]["exercises"][0]["sets"][0]["doneOn"] == iso(NOW)
    assert out["reminders"][0]["lastCompleted"] == iso(NOW)


def test_invalid_payloads_rejected(client, auth):
    assert client.put("/v1/state", json={"meals": [{"id": "x"}]}, headers=auth).status_code == 422
    bad = meal()
    bad["calories"] = -5
    assert client.put("/v1/state", json={"meals": [bad]}, headers=auth).status_code == 422
    assert client.put("/v1/state", json={"plan": [{"id": "1", "weekday": 9, "title": "x", "startMinutes": 5,
                                                   "exercises": []}]}, headers=auth).status_code == 422


# ------------------------------------------------------------------ recipes / meal plan
def test_recipes_respect_diet_and_allergies(client, auth):
    client.post("/v1/onboarding", json={**ONBOARDING, "allergies": ["Peanuts", "Dairy"], "diet": "Vegan"}, headers=auth)
    found = client.get("/v1/recipes", headers=auth).json()["recipes"]
    assert found
    for r in found:
        assert r["diet"] == "vegan" and "dairy" not in r["allergens"] and "peanuts" not in r["allergens"]


def test_non_veg_user_gets_more_options_than_vegan(client, auth):
    client.post("/v1/onboarding", json={**ONBOARDING, "allergies": [], "diet": "Vegan"}, headers=auth)
    vegan = len(client.get("/v1/recipes", headers=auth).json()["recipes"])
    client.post("/v1/onboarding", json={**ONBOARDING, "allergies": [], "diet": "Non-vegetarian"}, headers=auth)
    non_veg = len(client.get("/v1/recipes", headers=auth).json()["recipes"])
    assert non_veg > vegan


def test_recipe_filters(client, auth):
    client.post("/v1/onboarding", json={**ONBOARDING, "allergies": [], "diet": "Non-vegetarian"}, headers=auth)
    quick = client.get("/v1/recipes?max_minutes=10", headers=auth).json()["recipes"]
    assert quick and all(r["minutes"] <= 10 for r in quick)
    lunch = client.get("/v1/recipes?meal=lunch&max_kcal=450", headers=auth).json()["recipes"]
    assert all("lunch" in r["meals"] and r["kcal"] <= 450 for r in lunch)
    assert client.get("/v1/recipes?max_minutes=0", headers=auth).status_code == 422


def test_meal_plan_and_shopping_list(client, auth):
    client.post("/v1/onboarding", json={**ONBOARDING, "allergies": ["Peanuts", "Gluten"]}, headers=auth)
    plan = client.get("/v1/meal-plan", headers=auth).json()
    assert len(plan["days"]) == 7
    for day in plan["days"]:
        assert set(day["meals"]) == {"breakfast", "lunch", "dinner", "snack"}
        for r in day["meals"].values():
            assert "peanuts" not in r["allergens"] and "gluten" not in r["allergens"]
    assert plan["shopping"] and all({"name", "qty", "unit"} <= set(i) for i in plan["shopping"])
    # deterministic
    assert client.get("/v1/meal-plan", headers=auth).json()["days"][0]["meals"]["lunch"]["id"] == \
        plan["days"][0]["meals"]["lunch"]["id"]
    # variety: not the same lunch all week
    assert len({d["meals"]["lunch"]["id"] for d in plan["days"]}) > 1


def test_meal_plan_override_and_safety(client, auth):
    client.post("/v1/onboarding", json={**ONBOARDING, "allergies": ["Dairy"]}, headers=auth)
    day = client.get("/v1/meal-plan", headers=auth).json()["days"][0]["date"]
    ok = client.put("/v1/meal-plan/override", json={"date": day, "meal": "lunch", "recipe_id": "khichdi"}, headers=auth)
    assert ok.status_code == 204
    assert client.get("/v1/meal-plan", headers=auth).json()["days"][0]["meals"]["lunch"]["id"] == "khichdi"
    unsafe = client.put("/v1/meal-plan/override", json={"date": day, "meal": "lunch", "recipe_id": "paneer-chickpea-bowl"},
                        headers=auth)
    assert unsafe.status_code == 422
    assert client.put("/v1/meal-plan/override", json={"date": day, "meal": "lunch", "recipe_id": "nope"},
                      headers=auth).status_code == 404


# ------------------------------------------------------------------ insights
def test_insights_aggregate_history(client, auth):
    s = client.post("/v1/onboarding", json={**ONBOARDING, "timezone": "UTC"}, headers=auth).json()
    meals = [meal(id=f"00000000-0000-0000-0000-00000000000{i}", kcal=500 + i, protein=40,
                  when=NOW - timedelta(days=i)) for i in range(1, 4)]
    s["meals"], s["updatedAt"] = meals, iso(NOW + timedelta(seconds=10))
    s["plan"][0]["exercises"][0]["sets"][0]["doneOn"] = iso(NOW - timedelta(days=1))
    s["reminders"][0]["lastCompleted"] = iso(NOW - timedelta(days=1))
    client.put("/v1/state", json=s, headers=auth)
    data = client.get("/v1/insights?days=14", headers=auth).json()
    assert len(data["days"]) == 14 and data["weeks"]
    summary = data["summary"]
    assert summary["daysLogged"] == 3 and summary["avgCalories"] == 502 and summary["avgProtein"] == 40
    assert summary["workoutsDone"] == 1 and summary["workoutsPlanned"] == 8
    assert summary["habitRate"] > 0
    assert client.get("/v1/insights?days=3", headers=auth).status_code == 422


def test_insights_empty_account(client, auth):
    data = client.get("/v1/insights", headers=auth).json()
    assert data["summary"]["daysLogged"] == 0 and data["summary"]["avgCalories"] == 0


# ------------------------------------------------------------------ calendar
def test_calendar_feed(client, auth):
    client.post("/v1/onboarding", json=ONBOARDING, headers=auth)
    token = client.get("/v1/me", headers=auth).json()["calendarToken"]
    r = client.get(f"/v1/calendar/{token}.ics")
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/calendar")
    text = r.text
    assert text.startswith("BEGIN:VCALENDAR") and text.count("BEGIN:VEVENT") == 4
    assert "TZID=Asia/Kolkata" in text and "RRULE:FREQ=WEEKLY;BYDAY=" in text and "Gym: Upper body" in text
    assert all(len(line.encode()) <= 75 for line in text.split("\r\n"))
    assert client.get("/v1/calendar/wrong-token.ics").status_code == 404


# ------------------------------------------------------------------ assistant
def test_assist_uses_server_side_context(client, auth):
    client.post("/v1/onboarding", json={**ONBOARDING, "timezone": "UTC"}, headers=auth)
    client.put("/v1/state", json={"meals": [meal(kcal=1000)], "updatedAt": iso(NOW)}, headers=auth)
    goal = client.get("/v1/state", headers=auth).json()["profile"]["calorieGoal"]
    r = client.post("/v1/assist", json={"text": "log two rotis",
                                        "context": {"calorieGoal": 1, "caloriesEaten": 99999}}, headers=auth)
    assert r.status_code == 200
    body = r.json()
    assert body["actions"][0]["type"] == "log_meal" and body["provider"] == "local"
    assert f"{goal - 1000 - 210} kcal left" in body["reply"]      # client-sent numbers ignored


def test_assist_requires_auth_and_validates(client, auth):
    assert client.post("/v1/assist", json={"text": "hi"}).status_code == 401
    assert client.post("/v1/assist", json={"text": ""}, headers=auth).status_code == 422


def test_assist_provider_outage_falls_back(client, auth):
    class Broken:
        name = "broken"

        async def interpret(self, *a):
            raise RuntimeError("down")

    app.dependency_overrides[provider_dependency] = lambda: Broken()
    r = client.post("/v1/assist", json={"text": "log an egg"}, headers=auth)
    assert r.status_code == 200 and r.json()["provider"].startswith("local (fallback")


# ------------------------------------------------------------------ export + delete
def test_export_contains_everything(client, auth):
    s = client.post("/v1/onboarding", json=ONBOARDING, headers=auth).json()
    s["meals"], s["updatedAt"] = [meal()], iso(NOW + timedelta(seconds=5))
    client.put("/v1/state", json=s, headers=auth)
    r = client.get("/v1/export", headers=auth)
    assert r.headers["content-disposition"].startswith("attachment")
    data = json.loads(r.text)
    assert data["account"]["email"] == "a@example.com"
    assert len(data["data"]["meals"]) == 1 and len(data["data"]["plan"]) == 4


def test_delete_account_removes_everything(client, auth):
    from app.db import ActivityLog, ProfileRow, Record, SessionToken, User, get_database
    s = client.post("/v1/onboarding", json=ONBOARDING, headers=auth).json()
    s["meals"], s["updatedAt"] = [meal()], iso(NOW + timedelta(seconds=5))
    s["plan"][0]["exercises"][0]["sets"][0]["doneOn"] = iso(NOW)
    client.put("/v1/state", json=s, headers=auth)
    token = client.get("/v1/me", headers=auth).json()["calendarToken"]
    assert client.delete("/v1/account", headers=auth).status_code == 204
    with get_database().factory() as db:
        for table in (User, Record, ProfileRow, SessionToken, ActivityLog):
            assert db.query(table).count() == 0, table
    assert client.get("/v1/me", headers=auth).status_code == 401
    assert client.get(f"/v1/calendar/{token}.ics").status_code == 404
    assert client.post("/v1/auth/login", json={"email": "a@example.com", "password": "correct horse"}).status_code == 401


def test_provider_choice(client, auth, monkeypatch):
    for name in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "PULSE_PROVIDER"):
        monkeypatch.delenv(name, raising=False)
    info = client.get("/v1/providers", headers=auth).json()
    assert info["available"] == ["local"] and info["active"] == "local"
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    monkeypatch.setenv("GEMINI_API_KEY", "k")
    info = client.get("/v1/providers", headers=auth).json()
    assert info["available"] == ["openai", "gemini", "local"]
    client.put("/v1/state", json={"profile": {"aiProvider": "gemini"}, "updatedAt": iso(NOW)}, headers=auth)
    assert client.get("/v1/providers", headers=auth).json()["active"] == "gemini"
    # a choice the server can't honour falls back instead of breaking
    client.put("/v1/state", json={"profile": {"aiProvider": "anthropic"}, "updatedAt": iso(NOW + timedelta(seconds=5))},
               headers=auth)
    assert client.get("/v1/providers", headers=auth).json()["active"] in ("local", "openai", "gemini")


def test_two_edits_in_the_same_second_both_apply(client, auth):
    """Regression: the second change used to be dropped when its timestamp equalled the first."""
    s = client.post("/v1/onboarding", json=ONBOARDING, headers=auth).json()
    stamp = iso(NOW + timedelta(minutes=2))
    s["reminders"][0]["lastCompleted"], s["updatedAt"] = iso(NOW), stamp
    client.put("/v1/state", json=s, headers=auth)
    s = client.get("/v1/state", headers=auth).json()
    s["plan"][0]["exercises"].append({"id": "EEEEEEEE-0000-0000-0000-000000000001", "name": "Lateral raise",
                                      "restSeconds": 60, "sets": []})
    s["updatedAt"] = stamp                                    # same second as the previous push
    out = client.put("/v1/state", json=s, headers=auth).json()
    assert out["plan"][0]["exercises"][-1]["name"] == "Lateral raise"
    assert out["reminders"][0]["lastCompleted"] == iso(NOW)


def test_older_snapshot_never_overwrites_newer_settings(client, auth):
    s = client.post("/v1/onboarding", json=ONBOARDING, headers=auth).json()
    s["profile"]["calorieGoal"], s["updatedAt"] = 1700, iso(NOW + timedelta(minutes=3))
    client.put("/v1/state", json=s, headers=auth)
    s["profile"]["calorieGoal"], s["updatedAt"] = 3000, iso(NOW + timedelta(minutes=2))
    out = client.put("/v1/state", json=s, headers=auth).json()
    assert out["profile"]["calorieGoal"] == 1700


def test_meal_plan_days_land_near_the_calorie_goal(client, auth):
    client.post("/v1/onboarding", json={**ONBOARDING, "allergies": []}, headers=auth)
    goal = client.get("/v1/state", headers=auth).json()["profile"]["calorieGoal"]
    plan = client.get("/v1/meal-plan", headers=auth).json()
    for day in plan["days"]:
        assert abs(day["kcal"] - goal) / goal < 0.22, (day["date"], day["kcal"], goal)
        assert 0.8 <= day["scale"] <= 1.5


def test_shopping_list_has_whole_countable_items(client, auth):
    client.post("/v1/onboarding", json=ONBOARDING, headers=auth)
    for item in client.get("/v1/meal-plan", headers=auth).json()["shopping"]:
        if item["unit"] in ("piece", "slice", "scoop"):
            assert float(item["qty"]).is_integer(), item


def test_shopping_weights_are_rounded_up_to_five(client, auth):
    client.post("/v1/onboarding", json=ONBOARDING, headers=auth)
    for item in client.get("/v1/meal-plan", headers=auth).json()["shopping"]:
        if item["unit"] in ("g", "ml"):
            assert item["qty"] % 5 == 0, item
