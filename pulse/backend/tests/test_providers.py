import asyncio

import httpx
import pytest

from app.providers import (AnthropicProvider, GeminiProvider, LocalProvider, OpenAIProvider,
                           get_provider)
from app.schemas import AssistRequest, Turn, UserContext
from app.service import assist


def run(coro):
    return asyncio.run(coro)


def client_for(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def test_anthropic_parses_text_and_tool_use_and_sends_key():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["key"] = request.headers["x-api-key"]
        seen["body"] = request.read().decode()
        return httpx.Response(200, json={"content": [
            {"type": "text", "text": "Sure."},
            {"type": "tool_use", "name": "log_food", "input": {"items": [{"name": "egg", "quantity": 2}]}},
        ]})

    provider = AnthropicProvider("k", client=client_for(handler))
    result = run(provider.interpret("2 eggs", UserContext(), [Turn(role="user", text="hi")]))
    assert result.reply == "Sure." and result.calls[0].args["items"][0]["name"] == "egg"
    assert seen["key"] == "k" and "tools" in seen["body"] and "claude-" in seen["body"]


def test_openai_parses_tool_calls():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["authorization"] == "Bearer k"
        return httpx.Response(200, json={"choices": [{"message": {"content": None, "tool_calls": [
            {"function": {"name": "add_reminder", "arguments": '{"title":"Stretch","minutes_from_now":20}'}}]}}]})

    result = run(OpenAIProvider("k", client=client_for(handler)).interpret("remind me", UserContext(), []))
    assert result.calls[0].name == "add_reminder" and result.calls[0].args["minutes_from_now"] == 20


def test_gemini_parses_function_call():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["x-goog-api-key"] == "k"
        return httpx.Response(200, json={"candidates": [{"content": {"parts": [
            {"text": "ok"}, {"functionCall": {"name": "log_food", "args": {"items": [{"name": "banana", "quantity": 1}]}}}]}}]})

    result = run(GeminiProvider("k", client=client_for(handler)).interpret("banana", UserContext(), []))
    assert result.reply == "ok" and result.calls[0].name == "log_food"


def test_provider_http_error_raises():
    provider = AnthropicProvider("k", client=client_for(lambda r: httpx.Response(500)))
    with pytest.raises(httpx.HTTPStatusError):
        run(provider.interpret("x", UserContext(), []))


def test_get_provider_selection(monkeypatch):
    for name in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "PULSE_PROVIDER"):
        monkeypatch.delenv(name, raising=False)
    assert isinstance(get_provider(), LocalProvider)
    monkeypatch.setenv("PULSE_PROVIDER", "anthropic")
    assert isinstance(get_provider(), LocalProvider)          # no key -> local
    monkeypatch.setenv("ANTHROPIC_API_KEY", "x")
    assert isinstance(get_provider(), AnthropicProvider)
    monkeypatch.setenv("PULSE_PROVIDER", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "x")
    assert isinstance(get_provider(), OpenAIProvider)
    monkeypatch.setenv("PULSE_PROVIDER", "gemini")
    monkeypatch.setenv("GEMINI_API_KEY", "x")
    assert isinstance(get_provider(), GeminiProvider)


class Fake:
    name = "fake"

    def __init__(self, calls):
        from app.providers import Interpretation, ToolCall
        self.result = Interpretation(calls=[ToolCall(n, a) for n, a in calls])

    async def interpret(self, *args):
        return self.result


def test_model_supplied_numbers_are_ignored():
    fake = Fake([("log_food", {"items": [{"name": "banana", "quantity": 2, "calories": 99999}]})])
    res = run(assist(AssistRequest(text="x"), fake))
    assert res.actions[0].items[0].calories == 210


def test_unknown_food_needs_confirmation():
    fake = Fake([("log_food", {"items": [{"name": "mystery stew", "quantity": 1}]})])
    res = run(assist(AssistRequest(text="x"), fake))
    assert res.actions[0].needs_confirmation and "check" in res.reply


def test_calories_remaining_and_over_goal_messages():
    ctx = UserContext(calorie_goal=2000, calories_eaten=1000)
    res = run(assist(AssistRequest(text="log two rotis", context=ctx), LocalProvider()))
    assert "790 kcal left" in res.reply
    over = UserContext(calorie_goal=1000, calories_eaten=990)
    res = run(assist(AssistRequest(text="log two rotis", context=over), LocalProvider()))
    assert "over your goal" in res.reply


def test_reminder_and_gibberish():
    res = run(assist(AssistRequest(text="remind me in 20 minutes to stretch"), LocalProvider()))
    a = res.actions[0]
    assert a.type == "add_reminder" and a.minutes_from_now == 20 and a.title == "Stretch"
    res = run(assist(AssistRequest(text="blorp"), LocalProvider()))
    assert res.actions[0].type == "none" and res.reply


def test_tool_with_no_items_is_ignored():
    res = run(assist(AssistRequest(text="x"), Fake([("log_food", {"items": []})])))
    assert res.actions[0].type == "none"


def test_request_validation():
    with pytest.raises(Exception):
        AssistRequest(text="")
    with pytest.raises(Exception):
        AssistRequest(text="x" * 2001)
