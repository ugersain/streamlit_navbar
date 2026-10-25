import pytest
from fastapi.testclient import TestClient

from app.db import Database, set_database
from app.main import app, provider_dependency
from app.providers import LocalProvider
from app.security import login_limiter


@pytest.fixture
def client():
    set_database(Database("sqlite:///:memory:"))
    login_limiter.reset()
    app.dependency_overrides[provider_dependency] = lambda: LocalProvider()
    yield TestClient(app)
    app.dependency_overrides.clear()
    set_database(None)


def signup(client, email="a@example.com", password="correct horse", name="Aarav"):
    r = client.post("/v1/auth/signup", json={"email": email, "password": password, "name": name})
    assert r.status_code == 200, r.text
    return r.json()


@pytest.fixture
def auth(client):
    data = signup(client)
    return {"Authorization": f"Bearer {data['token']}"}


ONBOARDING = {
    "name": "Aarav", "sex": "male", "age": 28, "heightCm": 175, "weightKg": 78.5, "targetKg": 72,
    "goal": "lose", "activity": "light", "daysPerWeek": 4, "diet": "Vegetarian",
    "allergies": ["Peanuts"], "wakeMinutes": 390, "bedMinutes": 1350, "workoutMinutes": 1110,
    "timezone": "Asia/Kolkata",
}
