"""Bring-your-own-key connectors.

The key is checked with the provider, encrypted (see crypto.py) and stored. It is never returned by
any endpoint, never included in exports or sync, never logged, and wiped on removal or account deletion.
Changing it requires the account password.
"""
from __future__ import annotations

import re
from collections.abc import AsyncIterator
from datetime import datetime

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from .crypto import SecretBox, SecretsCorrupt, SecretsUnavailable
from .endpoints import endpoint
from .db import Connector, ProfileRow, User, get_session, utcnow
from .providers import Provider, build_provider
from .security import RateLimiter, current_user, verify_password
from .state import _profile_row

router = APIRouter(prefix="/v1/connectors", tags=["connectors"])

PROVIDERS = {
    "anthropic": {"name": "Claude (Anthropic)", "hint": "Starts with sk-ant-",
                  "pattern": re.compile(r"^sk-ant-[A-Za-z0-9_\-]{20,300}$"),
                  "check": ("GET", "https://api.anthropic.com/v1/models"),
                  "headers": lambda k: {"x-api-key": k, "anthropic-version": "2023-06-01"}},
    "openai": {"name": "OpenAI", "hint": "Starts with sk-",
               "pattern": re.compile(r"^sk-[A-Za-z0-9_\-]{20,300}$"),
               "check": ("GET", "https://api.openai.com/v1/models"),
               "headers": lambda k: {"Authorization": f"Bearer {k}"}},
    "gemini": {"name": "Google Gemini", "hint": "Starts with AIza",
               "pattern": re.compile(r"^AIza[0-9A-Za-z_\-]{30,60}$"),
               "check": ("GET", "https://generativelanguage.googleapis.com/v1beta/models"),
               "headers": lambda k: {"x-goog-api-key": k}},
}

# 5 password checks a minute per user, so a stolen session can't guess the password here.
password_limiter = RateLimiter(attempts=5, window_seconds=60)


async def http_client() -> AsyncIterator[httpx.AsyncClient]:
    async with httpx.AsyncClient(timeout=10, follow_redirects=False) as client:
        yield client


def secret_box() -> SecretBox:
    try:
        return SecretBox.from_env()
    except SecretsUnavailable:
        raise HTTPException(503, "Saving API keys is switched off on this server (no encryption key is configured).")


class KeyBody(BaseModel):
    api_key: str = Field(alias="apiKey", min_length=1, max_length=400)
    password: str = Field(min_length=1, max_length=200)
    model_config = {"populate_by_name": True}


class PasswordBody(BaseModel):
    password: str = Field(min_length=1, max_length=200)


def require_password(user: User, password: str) -> None:
    """Only wrong guesses count against the limit, so normal use is never locked out."""
    if password_limiter.is_blocked(user.id):
        raise HTTPException(429, "Too many wrong passwords. Please wait a minute and try again.")
    if not verify_password(password, user.password_hash):
        password_limiter.record(user.id)
        raise HTTPException(403, "That password is incorrect.")
    password_limiter.clear(user.id)


def check_provider(provider: str) -> dict:
    if provider not in PROVIDERS:
        raise HTTPException(404, "Unknown provider")
    return PROVIDERS[provider]


async def verify_key_with_provider(provider: str, key: str, client: httpx.AsyncClient) -> None:
    """A free, read-only call (list models). Uses no tokens and costs the user nothing."""
    spec = PROVIDERS[provider]
    method, url = spec["check"]
    url = endpoint(provider, url)
    try:
        response = await client.request(method, url, headers=spec["headers"](key))
    except httpx.HTTPError:
        raise HTTPException(502, f"Couldn't reach {spec['name']} to check your key. Try again in a moment.")
    if response.status_code in (401, 403):
        raise HTTPException(422, f"{spec['name']} rejected this key. Check that you copied all of it.")
    if response.status_code == 429:
        raise HTTPException(429, f"{spec['name']} is rate limiting this key right now. Try again shortly.")
    if response.status_code >= 400:
        raise HTTPException(502, f"{spec['name']} couldn't confirm this key ({response.status_code}).")


def describe(row: Connector) -> dict:
    return {"provider": row.provider, "last4": row.last4, "status": row.status,
            "createdAt": row.created_at.isoformat(), "lastUsedAt": row.last_used_at.isoformat() if row.last_used_at else None}


@router.get("")
def list_connectors(user: User = Depends(current_user), db: Session = Depends(get_session)) -> dict:
    try:
        SecretBox.from_env()
        available = True
    except SecretsUnavailable:
        available = False
    rows = db.query(Connector).filter(Connector.user_id == user.id).all()
    return {
        "encryptionAvailable": available,
        "providers": [{"id": k, "name": v["name"], "hint": v["hint"]} for k, v in PROVIDERS.items()],
        "connectors": [describe(r) for r in rows],
    }


@router.put("/{provider}")
async def save_key(provider: str, body: KeyBody, user: User = Depends(current_user),
                   db: Session = Depends(get_session), box: SecretBox = Depends(secret_box),
                   client: httpx.AsyncClient = Depends(http_client)) -> dict:
    spec = check_provider(provider)
    require_password(user, body.password)
    key = body.api_key.strip()
    if not spec["pattern"].fullmatch(key):
        # Never echo the key back, not even in an error.
        raise HTTPException(422, f"That doesn't look like a {spec['name']} key. {spec['hint']}.")
    await verify_key_with_provider(provider, key, client)

    ciphertext = box.encrypt(key, user.id, provider)
    row = db.get(Connector, (user.id, provider))
    if row is None:
        row = Connector(user_id=user.id, provider=provider, ciphertext=ciphertext, last4=key[-4:])
        db.add(row)
    else:
        row.ciphertext, row.last4, row.status, row.created_at = ciphertext, key[-4:], "ok", utcnow()
    # Use this provider unless the user already picked another one that has a key.
    profile = _profile_row(db, user.id)
    if profile is not None:
        data = dict(profile.data)
        existing = {r.provider for r in db.query(Connector).filter(Connector.user_id == user.id)}
        if data.get("aiProvider", "") not in existing or data.get("aiProvider") == provider:
            data["aiProvider"] = provider
            profile.data, profile.updated_at = data, utcnow()
    db.commit()
    del key, body   # drop the plaintext as soon as it has been stored
    return describe(row)


@router.post("/{provider}/remove", status_code=204)
def remove_key(provider: str, body: PasswordBody, user: User = Depends(current_user),
               db: Session = Depends(get_session)) -> Response:
    check_provider(provider)
    require_password(user, body.password)
    row = db.get(Connector, (user.id, provider))
    if row is not None:
        db.delete(row)
        profile = db.get(ProfileRow, user.id)
        if profile is not None and profile.data.get("aiProvider") == provider:
            profile.data = {**profile.data, "aiProvider": ""}
            profile.updated_at = utcnow()
        db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- used by the assistant

class OwnKey:
    """The user's decrypted key for one request. Not stored anywhere beyond this object's lifetime."""

    def __init__(self, provider: Provider, row: Connector):
        self.provider, self.row = provider, row


def resolve_own_provider(db: Session, user: User, chosen: str, client: httpx.AsyncClient | None = None) -> OwnKey | None:
    """Return the provider built from the user's own key, if they have one and chose (or only have) it."""
    rows = {r.provider: r for r in db.query(Connector).filter(Connector.user_id == user.id)}
    if not rows:
        return None
    if chosen in rows:
        row = rows[chosen]
    elif not chosen and len(rows) == 1:
        row = next(iter(rows.values()))
    else:
        return None
    if row.status != "ok":
        return None
    try:
        key = SecretBox.from_env().decrypt(row.ciphertext, user.id, row.provider)
    except (SecretsUnavailable, SecretsCorrupt):
        return None
    return OwnKey(build_provider(row.provider, key, client), row)


def mark_rejected(db: Session, row: Connector) -> None:
    row.status = "rejected"
    db.commit()


def mark_used(db: Session, row: Connector) -> None:
    row.last_used_at = utcnow()
    db.commit()
