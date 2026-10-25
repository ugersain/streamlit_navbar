"""Cloud sync: load and merge a user's snapshot.

Same rules as the apps' AppStore.merge: the newer snapshot wins for profile, plan and
reminders; meals are merged by id so offline logs from any device survive; deleted meals
stay deleted (tombstones).
"""
from __future__ import annotations

from datetime import datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select
from sqlalchemy.orm import Session

from .api_models import SnapshotModel, norm_dt, norm_id
from .db import ActivityLog, ProfileRow, Record, utcnow

EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


def parse_dt(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def as_utc(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def local_day(iso: str, tz_name: str) -> str:
    try:
        zone = ZoneInfo(tz_name)
    except (ZoneInfoNotFoundError, ValueError):
        zone = timezone.utc
    return parse_dt(iso).astimezone(zone).strftime("%Y-%m-%d")


def _profile_row(db: Session, user_id: str) -> ProfileRow:
    row = db.get(ProfileRow, user_id)
    if row is None:
        row = ProfileRow(user_id=user_id, data={}, updated_at=EPOCH)
        db.add(row)
        db.flush()
    return row


def load_snapshot(db: Session, user_id: str) -> dict:
    profile_row = _profile_row(db, user_id)
    records = db.scalars(select(Record).where(Record.user_id == user_id, Record.deleted.is_(False))).all()
    by_kind: dict[str, list[dict]] = {"meal": [], "plan": [], "reminder": []}
    for record in records:
        if record.kind in by_kind:
            by_kind[record.kind].append(record.data)
    profile = SnapshotModel.model_validate({"profile": profile_row.data}).profile
    meals = sorted(by_kind["meal"], key=lambda m: m["date"])
    return {
        "profile": profile.model_dump(by_alias=True),
        "meals": meals,
        "plan": sorted(by_kind["plan"], key=lambda d: d["weekday"]),
        "reminders": sorted(by_kind["reminder"], key=lambda r: r["minutes"]),
        "updatedAt": as_utc(profile_row.updated_at).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def _upsert(db: Session, user_id: str, kind: str, rid: str, data: dict, day: str | None = None) -> None:
    row = db.get(Record, (user_id, kind, rid))
    if row is None:
        db.add(Record(user_id=user_id, kind=kind, rid=rid, day=day, data=data, deleted=False))
    elif not row.deleted:
        row.data, row.day, row.updated_at = data, day, utcnow()


def merge_snapshot(db: Session, user_id: str, incoming: SnapshotModel) -> dict:
    profile_row = _profile_row(db, user_id)
    incoming_time = parse_dt(norm_dt(incoming.updated_at) or "1970-01-01T00:00:00Z")
    # >= so two edits in the same second both apply. A stale device is older, never equal.
    incoming_newer = incoming_time >= as_utc(profile_row.updated_at)
    stored_tz = {**profile_row.data}.get("timezone", "UTC")
    tz_name = incoming.profile.timezone if "timezone" in incoming.profile.model_fields_set else stored_tz

    # Deleted ids first, so a stale device re-sending a meal cannot bring it back.
    for raw in incoming.deleted_ids:
        rid = norm_id(raw)
        for kind in ("meal",):
            row = db.get(Record, (user_id, kind, rid))
            if row is None:
                db.add(Record(user_id=user_id, kind=kind, rid=rid, data={}, deleted=True))
            else:
                row.deleted, row.data = True, {}

    for meal in incoming.meals:
        data = meal.model_dump(by_alias=True)
        data["id"], data["date"] = norm_id(meal.id), norm_dt(meal.date)
        _upsert(db, user_id, "meal", data["id"], data, day=local_day(data["date"], tz_name))

    if incoming_newer:
        merged_profile = {**profile_row.data, **incoming.profile.model_dump(
            by_alias=True, exclude_unset=True)}
        profile_row.data = merged_profile
        profile_row.updated_at = incoming_time
        _replace(db, user_id, "plan", {norm_id(d.id): _plan_data(d) for d in incoming.plan})
        _replace(db, user_id, "reminder", {norm_id(r.id): _reminder_data(r) for r in incoming.reminders})

    _log_activity(db, user_id, incoming, tz_name)
    db.commit()
    return load_snapshot(db, user_id)


def _plan_data(day) -> dict:
    data = day.model_dump(by_alias=True)
    data["id"] = norm_id(day.id)
    for exercise in data["exercises"]:
        exercise["id"] = norm_id(exercise["id"])
        for item in exercise["sets"]:
            item["id"] = norm_id(item["id"])
            item["doneOn"] = norm_dt(item.get("doneOn"))
            if item["doneOn"] is None:
                item.pop("doneOn")
    return data


def _reminder_data(reminder) -> dict:
    data = reminder.model_dump(by_alias=True)
    data["id"] = norm_id(reminder.id)
    for key in ("lastCompleted", "snoozedUntil"):
        data[key] = norm_dt(data.get(key))
        if data[key] is None:
            data.pop(key)
    return data


def _replace(db: Session, user_id: str, kind: str, items: dict[str, dict]) -> None:
    existing = db.scalars(select(Record).where(Record.user_id == user_id, Record.kind == kind)).all()
    seen = set()
    for row in existing:
        seen.add(row.rid)
        if row.rid in items:
            row.data, row.deleted, row.updated_at = items[row.rid], False, utcnow()
        else:
            row.deleted = True
    for rid, data in items.items():
        if rid not in seen:
            db.add(Record(user_id=user_id, kind=kind, rid=rid, data=data, deleted=False))


def _log_activity(db: Session, user_id: str, incoming: SnapshotModel, tz_name: str) -> None:
    """Remember completed sets and habits so insights have history."""
    def upsert(kind: str, ref: str, day: str, label: str, value: float) -> None:
        row = db.get(ActivityLog, (user_id, kind, ref, day))
        if row is None:
            db.add(ActivityLog(user_id=user_id, kind=kind, ref=ref, day=day, label=label, value=value))
        else:
            row.label, row.value = label, value

    for plan_day in incoming.plan:
        for exercise in plan_day.exercises:
            for item in exercise.sets:
                if item.done_on:
                    day = local_day(norm_dt(item.done_on), tz_name)
                    upsert("set", norm_id(item.id), day, plan_day.title, item.weight_kg * item.reps)
    for reminder in incoming.reminders:
        if reminder.last_completed and not reminder.one_off:
            day = local_day(norm_dt(reminder.last_completed), tz_name)
            upsert("habit", norm_id(reminder.id), day, reminder.title, 1)
