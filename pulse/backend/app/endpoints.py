"""Where the AI providers live.

Always the real provider URL, with one exception for automated tests: when PULSE_ENV=test and
PULSE_FAKE_PROVIDER_URL is set, calls go to a local stand-in so key saving can be tested end to end
without a real account. In production PULSE_ENV is never "test", so this can never redirect a key.
"""
from __future__ import annotations

import os
from urllib.parse import urlparse


def endpoint(provider: str, default: str) -> str:
    if os.environ.get("PULSE_ENV") == "test":
        base = os.environ.get("PULSE_FAKE_PROVIDER_URL", "")
        if base.startswith("http://127.0.0.1") or base.startswith("http://localhost"):
            return f"{base.rstrip('/')}/{provider}{urlparse(default).path}"
    return default
