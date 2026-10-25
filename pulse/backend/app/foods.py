"""Food database and the rule-based parser.

The database is the source of truth for nutrition numbers. AI models only
interpret what the user said (names and quantities); the numbers always come
from here, so they stay consistent and explainable.
"""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

DEFAULT_FOODS_PATH = Path(__file__).resolve().parents[2] / "shared" / "foods.json"

NUMBER_WORDS = {
    "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "half": 0.5, "couple": 2,
}
UNITS = {
    "piece", "slice", "bowl", "cup", "glass", "teaspoon", "tsp", "handful", "serving",
}
UNIT_ALIASES = {"tsp": "teaspoon"}
LEADING_PHRASES = re.compile(
    r"^(please\s+)?(log|add|i had|i ate|i've had|ive had|i have had|had|ate)\s+", re.I
)
SPLITTER = re.compile(r"\s*(?:,|\band\b|\bplus\b|\bwith\b)\s*", re.I)


@dataclass(frozen=True)
class Food:
    id: str
    names: tuple[str, ...]
    unit: str
    kcal: float
    protein: float
    carbs: float
    fat: float


@dataclass
class ParsedItem:
    name: str
    quantity: float
    unit: str
    calories: int
    protein: float
    carbs: float
    fat: float
    confident: bool

    def to_dict(self) -> dict:
        return {
            "name": self.name, "quantity": self.quantity, "unit": self.unit,
            "calories": self.calories, "protein": self.protein,
            "carbs": self.carbs, "fat": self.fat, "confident": self.confident,
        }


@lru_cache(maxsize=1)
def load_foods() -> tuple[Food, ...]:
    path = Path(os.environ.get("PULSE_FOODS_PATH", DEFAULT_FOODS_PATH))
    data = json.loads(path.read_text(encoding="utf-8"))
    return tuple(
        Food(f["id"], tuple(n.lower() for n in f["names"]), f["unit"],
             f["kcal"], f["protein"], f["carbs"], f["fat"])
        for f in data["foods"]
    )


def singular(word: str) -> str:
    w = word.lower()
    if len(w) > 3 and w.endswith("ies"):
        return w[:-3] + "y"
    if len(w) > 3 and w.endswith("es") and w[:-2].endswith(("ch", "sh", "x", "s", "o")):
        return w[:-2]
    if len(w) > 2 and w.endswith("s") and not w.endswith("ss"):
        return w[:-1]
    return w


def normalise(text: str) -> str:
    return " ".join(singular(w) for w in re.findall(r"[a-z]+", text.lower()))


def find_food(name: str) -> Food | None:
    """Longest alias contained in the (singularised) phrase wins."""
    phrase = normalise(name)
    best: tuple[int, Food] | None = None
    for food in load_foods():
        for alias in food.names:
            a = normalise(alias)
            if re.search(rf"\b{re.escape(a)}\b", phrase):
                if best is None or len(a) > best[0]:
                    best = (len(a), food)
    return best[1] if best else None


def ground(name: str, quantity: float = 1, unit: str | None = None) -> ParsedItem:
    """Turn (name, quantity) from any interpreter into a nutrition estimate."""
    food = find_food(name)
    if food is None:
        return ParsedItem(name.strip() or "Unknown food", quantity, unit or "serving",
                          0, 0, 0, 0, confident=False)
    q = quantity if quantity and quantity > 0 else 1
    return ParsedItem(
        name=food.id, quantity=q, unit=food.unit,
        calories=round(food.kcal * q), protein=round(food.protein * q, 1),
        carbs=round(food.carbs * q, 1), fat=round(food.fat * q, 1), confident=True,
    )


def parse_meal_text(text: str) -> list[ParsedItem]:
    """Rule-based parser used offline and as the 'local' provider."""
    cleaned = LEADING_PHRASES.sub("", text.strip().rstrip(".!?"))
    items: list[ParsedItem] = []
    for chunk in SPLITTER.split(cleaned):
        chunk = chunk.strip()
        if not chunk:
            continue
        tokens = chunk.split()
        quantity: float = 1
        if tokens and re.fullmatch(r"\d+(\.\d+)?", tokens[0]):
            quantity = float(tokens.pop(0))
        elif tokens and tokens[0].lower() in NUMBER_WORDS:
            quantity = NUMBER_WORDS[tokens.pop(0).lower()]
        unit = None
        if tokens and singular(tokens[0]) in UNITS:
            unit = UNIT_ALIASES.get(singular(tokens[0]), singular(tokens[0]))
            tokens.pop(0)
        if tokens and tokens[0].lower() == "of":
            tokens.pop(0)
        if not tokens:
            continue
        items.append(ground(" ".join(tokens), quantity, unit))
    return items
