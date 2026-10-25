import asyncio

import httpx
import pytest
from fastapi.testclient import TestClient

from app.foods import ground, parse_meal_text
from app.main import app, provider_dependency
from app.providers import AnthropicProvider, Interpretation, LocalProvider, ToolCall
from app.schemas import AssistRequest, UserContext
from app.service import assist


def test_parses_the_spec_example():
    items = parse_meal_text("Log two rotis, one bowl of dal, and a cup of curd")
    assert [(i.name, i.quantity, i.calories) for i in items] == [
        ("roti", 2, 210), ("dal", 1, 180), ("curd", 1, 98),
    ]
    assert all(i.confident for i in items)


def test_number_words_digits_and_leading_phrase():
    items = parse_meal_text("I had 3 eggs and a banana")
    assert [(i.name, i.quantity) for i in items] == [("egg", 3), ("banana", 1)]


def test_unknown_food_is_flagged_not_invented():
    item = ground("dragon fruit smoothie", 1)
    assert not item.confident and item.calories == 0


def test_longest_alias_wins():
    assert ground("greek yogurt").name == "greek yogurt"
    assert ground("curd").name == "curd"


def test_assist_logs_and_reports_remaining_calories():
    req = AssistRequest(text="log two rotis", context=UserContext(calorie_goal=2000, calories_eaten=1000))
    res = asyncio.run(assist(req, LocalProvider()))
    assert res.actions[0].type == "log_meal"
    assert res.actions[0].items[0].calories == 210
    assert "790 kcal left" in res.reply


def test_assist_asks_for_confirmation_when_unsure():
    req = AssistRequest(text="log a mystery stew")
    res = asyncio.run(assist(req, LocalProvider()))
    # nothing recognised: local provider replies instead of guessing numbers
    assert res.actions[0].type == "none"


def test_reminder_action():
    req = AssistRequest(text="remind me in 20 minutes to stretch")
    res = asyncio.run(assist(req, LocalProvider()))
    action = res.actions[0]
    assert action.type == "add_reminder" and action.minutes_from_now == 20
    assert action.title == "Stretch"


class FakeProvider:
    name = "fake"

    async def interpret(self, text, context, history):
        return Interpretation(calls=[ToolCall("log_food", {"items": [{"name": "banana", "quantity": 2}]})])


def test_model_numbers_are_never_trusted():
    # even if a model sent calories, only name+quantity are read; numbers come from the database
    res = asyncio.run(assist(AssistRequest(text="two bananas"), FakeProvider()))
    assert res.actions[0].items[0].calories == 210


def test_anthropic_adapter_parses_tool_use():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["x-api-key"] == "k"
        return httpx.Response(200, json={"content": [
            {"type": "text", "text": "Sure."},
            {"type": "tool_use", "name": "log_food", "input": {"items": [{"name": "egg", "quantity": 2}]}},
        ]})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    result = asyncio.run(AnthropicProvider("k", client=client).interpret("2 eggs", UserContext(), []))
    assert result.calls[0].name == "log_food"


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("PULSE_API_TOKEN", "secret")
    app.dependency_overrides[provider_dependency] = lambda: LocalProvider()
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_endpoint_requires_token(client):
    assert client.post("/v1/assist", json={"text": "log an egg"}).status_code == 401


def test_endpoint_happy_path(client):
    r = client.post("/v1/assist", json={"text": "log an egg"}, headers={"Authorization": "Bearer secret"})
    assert r.status_code == 200
    body = r.json()
    assert body["actions"][0]["items"][0]["name"] == "egg"
    assert body["provider"] == "local"


def test_provider_failure_falls_back_to_local(client):
    class Broken:
        name = "broken"

        async def interpret(self, *a):
            raise RuntimeError("down")

    app.dependency_overrides[provider_dependency] = lambda: Broken()
    r = client.post("/v1/assist", json={"text": "log an egg"}, headers={"Authorization": "Bearer secret"})
    assert r.status_code == 200
    assert r.json()["provider"].startswith("local (fallback")
