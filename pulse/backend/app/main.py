from __future__ import annotations

import hmac
import os

from fastapi import Depends, FastAPI, Header, HTTPException

from .providers import Provider, get_provider
from .schemas import AssistRequest, AssistResponse
from .service import assist

app = FastAPI(title="Pulse API", version="0.1.0")


def require_token(authorization: str | None = Header(default=None)) -> None:
    """Shared bearer token for now. Replace with per-user auth (see README)."""
    expected = os.environ.get("PULSE_API_TOKEN")
    if not expected:
        raise HTTPException(503, "Server is missing PULSE_API_TOKEN")
    supplied = (authorization or "").removeprefix("Bearer ").strip()
    if not hmac.compare_digest(supplied, expected):
        raise HTTPException(401, "Invalid token")


def provider_dependency() -> Provider:
    return get_provider()


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}


@app.post("/v1/assist", response_model=AssistResponse, dependencies=[Depends(require_token)])
async def assist_endpoint(req: AssistRequest, provider: Provider = Depends(provider_dependency)) -> AssistResponse:
    try:
        return await assist(req, provider)
    except Exception as exc:  # provider outage: degrade to the rule-based parser
        from .providers import LocalProvider
        fallback = await assist(req, LocalProvider())
        fallback.provider = f"local (fallback after {type(exc).__name__})"
        return fallback
