"""Provider adapters.

Every adapter implements `interpret()` and returns the same `Interpretation`,
so the app never depends on one model vendor. Adapters only decide *what the
user meant* (a reply, or tool calls). They never produce nutrition numbers.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Protocol

import httpx

from .foods import parse_meal_text
from .schemas import Turn, UserContext

SYSTEM_PROMPT = (
    "You are Pulse, a concise fitness and nutrition assistant inside a watch and phone app. "
    "Keep replies under 40 words. When the user says what they ate, call log_food with the "
    "foods and quantities exactly as said; never invent calories, the app looks them up. "
    "When the user asks for a reminder, call add_reminder. Give general guidance only and "
    "suggest a qualified professional for medical concerns."
)

TOOLS = [
    {
        "name": "log_food",
        "description": "Log foods the user ate. Do not include nutrition numbers.",
        "parameters": {
            "type": "object",
            "properties": {
                "items": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string", "description": "Food name, e.g. 'roti'"},
                            "quantity": {"type": "number", "description": "How many units"},
                        },
                        "required": ["name", "quantity"],
                    },
                }
            },
            "required": ["items"],
        },
    },
    {
        "name": "add_reminder",
        "description": "Create a reminder for the user.",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "minutes_from_now": {"type": "integer"},
            },
            "required": ["title", "minutes_from_now"],
        },
    },
]


@dataclass
class ToolCall:
    name: str
    args: dict


@dataclass
class Interpretation:
    reply: str = ""
    calls: list[ToolCall] = field(default_factory=list)


class Provider(Protocol):
    name: str

    async def interpret(self, text: str, context: UserContext, history: list[Turn]) -> Interpretation: ...


def _context_line(context: UserContext) -> str:
    return (
        f"User today: {context.calories_eaten}/{context.calorie_goal} kcal, "
        f"{context.protein_eaten:.0f}/{context.protein_goal} g protein"
        + (f", diet: {context.diet}" if context.diet else "")
        + (f", workout today: {context.workout_today}" if context.workout_today else "")
        + "."
    )


class LocalProvider:
    """No network, no key. Rule-based, so the app works offline and in tests."""
    name = "local"

    async def interpret(self, text, context, history):
        lowered = text.lower()
        if "remind" in lowered:
            minutes = 30
            for token in lowered.split():
                if token.isdigit():
                    minutes = int(token)
                    break
            title = lowered.split("to", 1)[1].strip() if " to " in lowered else "Reminder"
            return Interpretation(calls=[ToolCall("add_reminder", {"title": title.capitalize(), "minutes_from_now": minutes})])
        items = parse_meal_text(text)
        if items and any(i.confident for i in items):
            return Interpretation(calls=[ToolCall("log_food", {
                "items": [{"name": i.name, "quantity": i.quantity} for i in items]})])
        return Interpretation(reply="I can log meals and set reminders. Try: log two rotis and a cup of dal.")


class AnthropicProvider:
    name = "anthropic"

    def __init__(self, api_key: str, model: str | None = None, client: httpx.AsyncClient | None = None):
        self.api_key = api_key
        self.model = model or os.environ.get("ANTHROPIC_MODEL", "claude-haiku-5-5")
        self.client = client or httpx.AsyncClient(timeout=20)

    async def interpret(self, text, context, history):
        messages = [{"role": t.role, "content": t.text} for t in history]
        messages.append({"role": "user", "content": text})
        body = {
            "model": self.model,
            "max_tokens": 400,
            "system": f"{SYSTEM_PROMPT}\n{_context_line(context)}",
            "tools": [{"name": t["name"], "description": t["description"], "input_schema": t["parameters"]} for t in TOOLS],
            "messages": messages,
        }
        r = await self.client.post(
            "https://api.anthropic.com/v1/messages",
            headers={"x-api-key": self.api_key, "anthropic-version": "2023-06-01"},
            json=body,
        )
        r.raise_for_status()
        out = Interpretation()
        for block in r.json().get("content", []):
            if block.get("type") == "text":
                out.reply += block["text"]
            elif block.get("type") == "tool_use":
                out.calls.append(ToolCall(block["name"], block.get("input", {})))
        return out


class OpenAIProvider:
    name = "openai"

    def __init__(self, api_key: str, model: str | None = None, client: httpx.AsyncClient | None = None):
        self.api_key = api_key
        self.model = model or os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
        self.client = client or httpx.AsyncClient(timeout=20)

    async def interpret(self, text, context, history):
        messages = [{"role": "system", "content": f"{SYSTEM_PROMPT}\n{_context_line(context)}"}]
        messages += [{"role": t.role, "content": t.text} for t in history]
        messages.append({"role": "user", "content": text})
        r = await self.client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {self.api_key}"},
            json={
                "model": self.model,
                "messages": messages,
                "tools": [{"type": "function", "function": t} for t in TOOLS],
            },
        )
        r.raise_for_status()
        message = r.json()["choices"][0]["message"]
        out = Interpretation(reply=message.get("content") or "")
        for call in message.get("tool_calls") or []:
            out.calls.append(ToolCall(call["function"]["name"], json.loads(call["function"]["arguments"] or "{}")))
        return out


class GeminiProvider:
    name = "gemini"

    def __init__(self, api_key: str, model: str | None = None, client: httpx.AsyncClient | None = None):
        self.api_key = api_key
        self.model = model or os.environ.get("GEMINI_MODEL", "gemini-2.0-flash")
        self.client = client or httpx.AsyncClient(timeout=20)

    async def interpret(self, text, context, history):
        contents = [
            {"role": "user" if t.role == "user" else "model", "parts": [{"text": t.text}]}
            for t in history
        ]
        contents.append({"role": "user", "parts": [{"text": text}]})
        r = await self.client.post(
            f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent",
            headers={"x-goog-api-key": self.api_key},
            json={
                "systemInstruction": {"parts": [{"text": f"{SYSTEM_PROMPT}\n{_context_line(context)}"}]},
                "contents": contents,
                "tools": [{"functionDeclarations": TOOLS}],
            },
        )
        r.raise_for_status()
        out = Interpretation()
        candidates = r.json().get("candidates") or [{}]
        for part in candidates[0].get("content", {}).get("parts", []):
            if "text" in part:
                out.reply += part["text"]
            elif "functionCall" in part:
                call = part["functionCall"]
                out.calls.append(ToolCall(call["name"], call.get("args", {})))
        return out


def configured_providers() -> list[str]:
    """Providers the server has an API key for. 'local' is always available."""
    names = [n for n, var in (("anthropic", "ANTHROPIC_API_KEY"), ("openai", "OPENAI_API_KEY"),
                              ("gemini", "GEMINI_API_KEY")) if os.environ.get(var)]
    return names + ["local"]


def get_provider(name: str | None = None) -> Provider:
    """Pick the provider from PULSE_PROVIDER; fall back to local without a key."""
    name = (name or os.environ.get("PULSE_PROVIDER", "")).lower()
    keys = {
        "anthropic": os.environ.get("ANTHROPIC_API_KEY"),
        "openai": os.environ.get("OPENAI_API_KEY"),
        "gemini": os.environ.get("GEMINI_API_KEY"),
    }
    classes = {"anthropic": AnthropicProvider, "openai": OpenAIProvider, "gemini": GeminiProvider}
    if name in classes and keys[name]:
        return classes[name](keys[name])
    return LocalProvider()
