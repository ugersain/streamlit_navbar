"""iCalendar feed of the weekly gym sessions, so Apple Calendar / Google Calendar can subscribe."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

BYDAY = {1: "SU", 2: "MO", 3: "TU", 4: "WE", 5: "TH", 6: "FR", 7: "SA"}


def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def _fold(line: str) -> str:
    out, data = [], line.encode()
    while len(data) > 74:
        cut = 74
        while cut > 0 and (data[cut] & 0xC0) == 0x80:  # do not split a UTF-8 character
            cut -= 1
        out.append(data[:cut].decode())
        data = b" " + data[cut:]
    out.append(data.decode())
    return "\r\n".join(out)


def build_calendar(user_id: str, plan: list[dict], tz_name: str, now: datetime | None = None,
                   minutes: int = 60) -> str:
    try:
        zone = ZoneInfo(tz_name)
    except (ZoneInfoNotFoundError, ValueError):
        zone, tz_name = timezone.utc, "UTC"
    now = (now or datetime.now(timezone.utc)).astimezone(zone)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Pulse//Fitness//EN", "CALSCALE:GREGORIAN",
             "X-WR-CALNAME:Pulse workouts"]
    for day in plan:
        # Next date (today or later) that falls on this plan weekday. Plan weekday: 1 = Sunday.
        python_weekday = (day["weekday"] - 2) % 7  # Monday = 0
        delta = (python_weekday - now.weekday()) % 7
        start = (now + timedelta(days=delta)).replace(
            hour=day["startMinutes"] // 60, minute=day["startMinutes"] % 60, second=0, microsecond=0)
        end = start + timedelta(minutes=minutes)
        local = "%Y%m%dT%H%M%S"
        lines += [
            "BEGIN:VEVENT",
            f"UID:{day['id']}@pulse",
            f"DTSTAMP:{stamp}",
            f"DTSTART;TZID={tz_name}:{start.strftime(local)}",
            f"DTEND;TZID={tz_name}:{end.strftime(local)}",
            f"RRULE:FREQ=WEEKLY;BYDAY={BYDAY[day['weekday']]}",
            f"SUMMARY:{_escape('Gym: ' + day['title'])}",
            "DESCRIPTION:" + _escape(", ".join(e["name"] for e in day["exercises"])),
            "BEGIN:VALARM", "TRIGGER:-PT30M", "ACTION:DISPLAY", "DESCRIPTION:Workout in 30 minutes", "END:VALARM",
            "END:VEVENT",
        ]
    lines.append("END:VCALENDAR")
    return "\r\n".join(_fold(line) for line in lines) + "\r\n"
