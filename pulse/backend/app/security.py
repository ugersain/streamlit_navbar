from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import time
from datetime import timedelta

from fastapi import Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import SessionToken, User, get_session, utcnow

SESSION_DAYS = 90


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return "scrypt$" + base64.b64encode(salt).decode() + "$" + base64.b64encode(digest).decode()


def verify_password(password: str, stored: str) -> bool:
    try:
        scheme, salt_b64, digest_b64 = stored.split("$")
        if scheme != "scrypt":
            return False
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(digest_b64)
    except ValueError:
        return False
    actual = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return hmac.compare_digest(actual, expected)


def _digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def device_label(user_agent: str | None) -> str:
    """'Chrome on Mac', 'Safari on iPhone', ... from a User-Agent. Only for the devices list."""
    ua = user_agent or ""
    if "Pulse" in ua:
        return "Pulse app"
    browser = next((n for k, n in (("Edg/", "Edge"), ("Firefox/", "Firefox"), ("Chrome/", "Chrome"), ("Safari/", "Safari")) if k in ua), "Browser")
    system = next((n for k, n in (("iPhone", "iPhone"), ("iPad", "iPad"), ("Android", "Android"), ("Mac OS", "Mac"),
                                  ("Windows", "Windows"), ("Linux", "Linux")) if k in ua), "")
    return f"{browser} on {system}" if system else browser


def create_session(db: Session, user_id: str, user_agent: str | None = None) -> str:
    """Returns the raw token once; only its hash is stored."""
    token = secrets.token_urlsafe(32)
    db.add(SessionToken(token_hash=_digest(token), user_id=user_id, device=device_label(user_agent),
                        expires_at=utcnow() + timedelta(days=SESSION_DAYS)))
    db.commit()
    return token


def token_digest(token: str) -> str:
    return _digest(token)


def revoke_session(db: Session, token: str) -> None:
    row = db.get(SessionToken, _digest(token))
    if row:
        db.delete(row)
        db.commit()


def bearer(authorization: str | None = Header(default=None)) -> str:
    token = (authorization or "").removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(401, "Not signed in")
    return token


def current_user(token: str = Depends(bearer), db: Session = Depends(get_session)) -> User:
    row = db.get(SessionToken, _digest(token))
    if row is None or row.expires_at.replace(tzinfo=row.expires_at.tzinfo or utcnow().tzinfo) < utcnow():
        raise HTTPException(401, "Session expired, please sign in again")
    user = db.get(User, row.user_id)
    if user is None:
        raise HTTPException(401, "Account not found")
    last = row.last_used_at
    if last is None or (utcnow() - (last if last.tzinfo else last.replace(tzinfo=utcnow().tzinfo))).total_seconds() > 60:
        row.last_used_at = utcnow()
        db.commit()
    return user


class RateLimiter:
    """Tiny in-memory limiter for login and signup. Use a shared store if you run many instances."""

    def __init__(self, attempts: int, window_seconds: int):
        self.attempts = attempts
        self.window = window_seconds
        self.hits: dict[str, list[float]] = {}

    def check(self, key: str) -> None:
        now = time.monotonic()
        recent = [t for t in self.hits.get(key, []) if now - t < self.window]
        if len(recent) >= self.attempts:
            raise HTTPException(429, "Too many attempts. Please wait a minute and try again.")
        recent.append(now)
        self.hits[key] = recent

    def is_blocked(self, key: str) -> bool:
        now = time.monotonic()
        return len([t for t in self.hits.get(key, []) if now - t < self.window]) >= self.attempts

    def record(self, key: str) -> None:
        now = time.monotonic()
        self.hits[key] = [t for t in self.hits.get(key, []) if now - t < self.window] + [now]

    def clear(self, key: str) -> None:
        self.hits.pop(key, None)

    def reset(self) -> None:
        self.hits.clear()


login_limiter = RateLimiter(attempts=8, window_seconds=60)
