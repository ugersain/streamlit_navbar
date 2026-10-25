from __future__ import annotations

from .foods import ground
from .providers import Provider
from .schemas import Action, AssistRequest, AssistResponse, FoodItem


async def assist(req: AssistRequest, provider: Provider) -> AssistResponse:
    result = await provider.interpret(req.text, req.context, req.history)
    actions: list[Action] = []
    reply = result.reply.strip()

    for call in result.calls:
        if call.name == "log_food":
            items = [
                ground(str(i.get("name", "")), float(i.get("quantity") or 1))
                for i in call.args.get("items", [])
            ]
            if not items:
                continue
            uncertain = any(not i.confident for i in items)
            actions.append(Action(
                type="log_meal",
                items=[FoodItem(**i.to_dict()) for i in items],
                needs_confirmation=uncertain,
            ))
            kcal = sum(i.calories for i in items)
            protein = sum(i.protein for i in items)
            left = req.context.calorie_goal - req.context.calories_eaten - kcal
            reply = (
                f"That's about {kcal} kcal and {protein:.0f} g protein. "
                + (f"{left} kcal left today." if left >= 0 else f"{-left} kcal over your goal.")
            )
            if uncertain:
                reply += " Please check the items I wasn't sure about."
        elif call.name == "add_reminder":
            minutes = int(call.args.get("minutes_from_now") or 30)
            title = str(call.args.get("title") or "Reminder")
            actions.append(Action(type="add_reminder", title=title, minutes_from_now=minutes))
            reply = f"Okay, I'll remind you in {minutes} min: {title}."

    if not actions:
        actions.append(Action(type="none"))
        reply = reply or "Sorry, I didn't catch that."
    return AssistResponse(reply=reply, actions=actions, provider=provider.name)
