"""API-key storage and account security. The most important rule: a saved key can never be read back."""
import asyncio
import json
import logging
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

from app import connectors, main
from app.crypto import SecretBox, SecretsCorrupt, SecretsUnavailable, generate_key
from app.db import Connector, get_database
from app.main import app, provider_dependency
from app.providers import LocalProvider
from conftest import ONBOARDING, signup

ANTHROPIC_KEY = "sk-ant-api03-TESTKEYTESTKEYTESTKEY1234abcd"
OPENAI_KEY = "sk-proj-TESTKEYTESTKEYTESTKEY1234wxyz"
GEMINI_KEY = "AIzaTESTKEYTESTKEYTESTKEYTESTKEYtest12"
PASSWORD = "correct horse"


# ---------------------------------------------------------------- crypto unit tests
def box():
    return SecretBox([__import__("base64").urlsafe_b64decode(generate_key())])


def test_encrypt_roundtrip_and_ciphertext_hides_the_key():
    b = box()
    token = b.encrypt(ANTHROPIC_KEY, "user-1", "anthropic")
    assert ANTHROPIC_KEY not in token and "sk-ant" not in token
    assert b.decrypt(token, "user-1", "anthropic") == ANTHROPIC_KEY


def test_same_key_encrypts_differently_every_time():
    b = box()
    assert b.encrypt(ANTHROPIC_KEY, "u", "anthropic") != b.encrypt(ANTHROPIC_KEY, "u", "anthropic")


def test_ciphertext_cannot_be_moved_to_another_user_or_provider():
    b = box()
    token = b.encrypt(ANTHROPIC_KEY, "user-1", "anthropic")
    with pytest.raises(SecretsCorrupt):
        b.decrypt(token, "user-2", "anthropic")
    with pytest.raises(SecretsCorrupt):
        b.decrypt(token, "user-1", "openai")


def test_tampering_is_detected():
    b = box()
    token = b.encrypt(ANTHROPIC_KEY, "u", "anthropic")
    head, kid, nonce, ct = token.split(".")
    flipped = ct[:-2] + ("AA" if not ct.endswith("AA") else "BB")
    with pytest.raises(SecretsCorrupt):
        b.decrypt(".".join([head, kid, nonce, flipped]), "u", "anthropic")
    with pytest.raises(SecretsCorrupt):
        b.decrypt("garbage", "u", "anthropic")


def test_key_rotation_keeps_old_data_readable():
    import base64
    old, new = base64.urlsafe_b64decode(generate_key()), base64.urlsafe_b64decode(generate_key())
    token = SecretBox([old]).encrypt(ANTHROPIC_KEY, "u", "anthropic")
    rotated = SecretBox([new, old])
    assert rotated.decrypt(token, "u", "anthropic") == ANTHROPIC_KEY
    assert rotated.needs_rotation(token)
    assert not rotated.needs_rotation(rotated.encrypt("x" * 30, "u", "anthropic"))
    with pytest.raises(SecretsCorrupt):                 # without the old key it is unreadable
        SecretBox([new]).decrypt(token, "u", "anthropic")


def test_missing_or_bad_master_key_refuses_to_run(monkeypatch):
    monkeypatch.delenv("PULSE_ENCRYPTION_KEYS", raising=False)
    with pytest.raises(SecretsUnavailable):
        SecretBox.from_env()
    monkeypatch.setenv("PULSE_ENCRYPTION_KEYS", "tooshort")
    with pytest.raises(SecretsUnavailable):
        SecretBox.from_env()


# ---------------------------------------------------------------- API fixtures
class Provider:
    """Records what the (mock) AI providers receive."""
    def __init__(self):
        self.verify_status = 200
        self.assist_status = 200
        self.calls = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.calls.append((request.method, str(request.url), dict(request.headers)))
        if request.method == "GET":                       # key verification (list models)
            if self.verify_status == "unreachable":
                raise httpx.ConnectError("down")
            return httpx.Response(self.verify_status, json={"data": []})
        if self.assist_status != 200:                     # an assistant call
            return httpx.Response(self.assist_status, json={"error": "nope"})
        return httpx.Response(200, json={"content": [{"type": "tool_use", "name": "log_food",
                                                      "input": {"items": [{"name": "egg", "quantity": 2}]}}]})


@pytest.fixture
def mock(client, monkeypatch):
    monkeypatch.setenv("PULSE_ENCRYPTION_KEYS", generate_key())
    monkeypatch.delenv("PULSE_PROVIDER", raising=False)
    for name in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY"):
        monkeypatch.delenv(name, raising=False)
    connectors.password_limiter.reset()
    provider = Provider()

    async def fake_client():
        async with httpx.AsyncClient(transport=httpx.MockTransport(provider.handler)) as c:
            yield c

    app.dependency_overrides[connectors.http_client] = fake_client
    app.dependency_overrides.pop(provider_dependency, None)       # use the real selection logic
    return provider


def save(client, auth, key=ANTHROPIC_KEY, provider="anthropic", password=PASSWORD):
    return client.put(f"/v1/connectors/{provider}", json={"apiKey": key, "password": password}, headers=auth)


def stored_rows():
    with get_database().factory() as db:
        return db.query(Connector).all()


# ---------------------------------------------------------------- saving a key
def test_save_key_success_returns_only_the_last_four(client, auth, mock):
    r = save(client, auth)
    assert r.status_code == 200
    body = r.json()
    assert body["last4"] == ANTHROPIC_KEY[-4:] and body["provider"] == "anthropic"
    assert ANTHROPIC_KEY not in r.text
    # the provider check was a free read-only call carrying the key
    method, url, headers = mock.calls[0]
    assert method == "GET" and url.endswith("/v1/models") and headers["x-api-key"] == ANTHROPIC_KEY


def test_stored_value_is_encrypted_not_plaintext(client, auth, mock):
    save(client, auth)
    row = stored_rows()[0]
    assert ANTHROPIC_KEY not in row.ciphertext and "sk-ant" not in row.ciphertext
    assert row.ciphertext.startswith("v1.")


def test_the_key_never_appears_in_any_response(client, auth, mock):
    client.post("/v1/onboarding", json=ONBOARDING, headers=auth)
    save(client, auth)
    save(client, auth, key=OPENAI_KEY, provider="openai")
    for path in ("/v1/connectors", "/v1/state", "/v1/export", "/v1/me", "/v1/providers", "/v1/sessions",
                 "/v1/profile/stats", "/v1/insights", "/v1/meal-plan", "/v1/weights"):
        text = client.get(path, headers=auth).text
        assert ANTHROPIC_KEY not in text and OPENAI_KEY not in text, path
        assert "TESTKEYTESTKEY" not in text, path
    export = json.loads(client.get("/v1/export", headers=auth).text)
    assert {c["provider"] for c in export["aiConnectors"]} == {"anthropic", "openai"}
    assert all(set(c) == {"provider", "last4", "addedAt"} for c in export["aiConnectors"])


def test_saving_needs_the_right_password(client, auth, mock):
    r = save(client, auth, password="not my password")
    assert r.status_code == 403 and stored_rows() == [] and mock.calls == []     # nothing sent to the provider either
    assert save(client, auth, password="").status_code == 422


def test_password_guessing_is_rate_limited(client, auth, mock):
    codes = [save(client, auth, password=f"guess {i}").status_code for i in range(8)]
    assert codes[:5] == [403] * 5 and 429 in codes[5:]
    assert save(client, auth).status_code == 429                                  # even the right one is paused


@pytest.mark.parametrize("provider,key", [
    ("anthropic", "not-a-key"), ("anthropic", "sk-short"), ("openai", ANTHROPIC_KEY[:5] + "x"),
    ("gemini", "sk-ant-api03-wrongprovider-wrongprovider"), ("anthropic", "sk-ant-api03-has space inside-xxxxxxxx"),
    ("anthropic", "sk-ant-api03-newline\ninjection-xxxxxxxx"), ("anthropic", "x" * 401),
])
def test_malformed_keys_are_rejected_without_echoing_them(client, auth, mock, provider, key):
    r = save(client, auth, key=key, provider=provider)
    assert r.status_code == 422 and key.strip()[:12] not in r.text
    assert stored_rows() == [] and mock.calls == []


def test_unknown_provider_is_404(client, auth, mock):
    assert save(client, auth, provider="skynet").status_code == 404


def test_key_the_provider_rejects_is_not_stored(client, auth, mock):
    mock.verify_status = 401
    r = save(client, auth)
    assert r.status_code == 422 and "rejected" in r.json()["detail"] and ANTHROPIC_KEY not in r.text
    assert stored_rows() == []


@pytest.mark.parametrize("status,expected", [(429, 429), (500, 502), ("unreachable", 502)])
def test_provider_trouble_means_not_saved(client, auth, mock, status, expected):
    mock.verify_status = status
    assert save(client, auth).status_code == expected and stored_rows() == []


def test_feature_is_off_without_a_server_encryption_key(client, auth, mock, monkeypatch):
    monkeypatch.delenv("PULSE_ENCRYPTION_KEYS")
    assert save(client, auth).status_code == 503
    assert client.get("/v1/connectors", headers=auth).json()["encryptionAvailable"] is False
    assert stored_rows() == []


def test_replacing_a_key_updates_last4(client, auth, mock):
    save(client, auth)
    new = "sk-ant-api03-NEWKEYNEWKEYNEWKEYNEWKEY9999"
    assert save(client, auth, key=new).json()["last4"] == "9999"
    assert len(stored_rows()) == 1


def test_connectors_endpoints_require_login(client, mock):
    assert client.get("/v1/connectors").status_code == 401
    assert client.put("/v1/connectors/anthropic", json={"apiKey": ANTHROPIC_KEY, "password": "x"}).status_code == 401
    assert client.post("/v1/connectors/anthropic/remove", json={"password": "x"}).status_code == 401


def test_users_are_isolated(client, auth, mock):
    save(client, auth)
    other = {"Authorization": f"Bearer {signup(client, 'b@example.com')['token']}"}
    assert client.get("/v1/connectors", headers=other).json()["connectors"] == []
    # B cannot remove A's key: removal only ever touches B's own rows
    client.post("/v1/connectors/anthropic/remove", json={"password": PASSWORD}, headers=other)
    assert len(stored_rows()) == 1


# ---------------------------------------------------------------- using + removing a key
def test_assistant_uses_the_users_own_key(client, auth, mock):
    save(client, auth)
    mock.calls.clear()
    r = client.post("/v1/assist", json={"text": "log two eggs"}, headers=auth)
    body = r.json()
    assert r.status_code == 200 and body["provider"] == "anthropic (your key)" and body["notice"] is None
    assert body["actions"][0]["items"][0]["calories"] == 156            # numbers still come from the database
    assert mock.calls[0][2]["x-api-key"] == ANTHROPIC_KEY               # the provider got their key
    assert client.get("/v1/connectors", headers=auth).json()["connectors"][0]["lastUsedAt"]


def test_provider_that_later_rejects_the_key_flags_it_and_falls_back(client, auth, mock):
    save(client, auth)
    mock.assist_status = 401
    r = client.post("/v1/assist", json={"text": "log two eggs"}, headers=auth).json()
    assert "rejected" in r["notice"] and r["provider"] == "local (fallback)"
    assert r["actions"][0]["type"] == "log_meal"                         # logging still works
    assert client.get("/v1/connectors", headers=auth).json()["connectors"][0]["status"] == "rejected"
    mock.calls.clear()
    client.post("/v1/assist", json={"text": "log an egg"}, headers=auth)
    assert mock.calls == []                                              # a rejected key is not used again
    mock.verify_status = 200                                             # re-adding it makes it active again
    assert save(client, auth).status_code == 200
    assert client.get("/v1/connectors", headers=auth).json()["connectors"][0]["status"] == "ok"


def test_provider_rate_limit_gets_a_friendly_notice(client, auth, mock):
    save(client, auth)
    mock.assist_status = 429
    r = client.post("/v1/assist", json={"text": "log an egg"}, headers=auth).json()
    assert "rate limiting" in r["notice"] and r["actions"][0]["type"] == "log_meal"


def test_removing_a_key_needs_the_password_and_deletes_it(client, auth, mock):
    save(client, auth)
    assert client.post("/v1/connectors/anthropic/remove", json={"password": "wrong"}, headers=auth).status_code == 403
    assert len(stored_rows()) == 1
    assert client.post("/v1/connectors/anthropic/remove", json={"password": PASSWORD}, headers=auth).status_code == 204
    assert stored_rows() == []
    r = client.post("/v1/assist", json={"text": "log an egg"}, headers=auth).json()
    assert r["provider"] == "local" and "your key" not in r["provider"]


def test_a_ciphertext_copied_to_another_account_is_useless(client, auth, mock):
    save(client, auth)
    other = signup(client, "thief@example.com")
    thief = {"Authorization": f"Bearer {other['token']}"}
    with get_database().factory() as db:
        victim = db.query(Connector).one()
        db.add(Connector(user_id=other["userId"], provider="anthropic", ciphertext=victim.ciphertext, last4="xxxx"))
        db.commit()
    mock.calls.clear()
    r = client.post("/v1/assist", json={"text": "log an egg"}, headers=thief).json()
    assert r["provider"] == "local" and mock.calls == []                 # decryption fails, nothing is sent anywhere


def test_deleting_the_account_wipes_stored_keys(client, auth, mock):
    save(client, auth)
    assert client.delete("/v1/account", headers=auth).status_code == 204
    assert stored_rows() == []


def test_providers_endpoint_prefers_the_connected_key(client, auth, mock):
    save(client, auth, key=OPENAI_KEY, provider="openai")
    state = client.get("/v1/state", headers=auth).json()
    assert state["profile"]["aiProvider"] == "openai"                    # auto-selected after the first key


# ---------------------------------------------------------------- nothing leaks into logs
def test_key_never_reaches_the_logs(client, auth, mock, caplog):
    caplog.set_level(logging.DEBUG)
    save(client, auth)
    mock.assist_status = 500
    client.post("/v1/assist", json={"text": "log an egg"}, headers=auth)
    mock.verify_status = 401
    save(client, auth, key="sk-ant-api03-ANOTHERKEYANOTHERKEYANOTHER77")
    assert "TESTKEYTESTKEY" not in caplog.text and "ANOTHERKEY" not in caplog.text


def test_provider_objects_hide_their_key_in_repr():
    from app.providers import AnthropicProvider
    provider = AnthropicProvider(ANTHROPIC_KEY)
    assert ANTHROPIC_KEY not in repr(provider) and ANTHROPIC_KEY not in str(provider)


# ---------------------------------------------------------------- abuse + headers
def test_assistant_rate_limit(client, auth, mock):
    from app.main import assist_limiter
    assist_limiter.reset()
    codes = [client.post("/v1/assist", json={"text": "log an egg"}, headers=auth).status_code for _ in range(32)]
    assert 429 in codes and codes[:30] == [200] * 30
    assist_limiter.reset()


def test_daily_cap_protects_the_shared_server_key(client, auth, mock, monkeypatch):
    class Shared:
        name = "anthropic"

        async def interpret(self, *a):
            from app.providers import Interpretation, ToolCall
            return Interpretation(calls=[ToolCall("log_food", {"items": [{"name": "egg", "quantity": 1}]})])

    monkeypatch.setattr(main, "SERVER_KEY_DAILY_LIMIT", 2)
    main._daily_use.clear()
    app.dependency_overrides[provider_dependency] = lambda: Shared()
    from app.main import assist_limiter
    assist_limiter.reset()
    results = [client.post("/v1/assist", json={"text": "log an egg"}, headers=auth).json() for _ in range(3)]
    assert results[0]["notice"] is None and results[1]["notice"] is None
    assert "limit" in results[2]["notice"] and results[2]["provider"] == "local"
    app.dependency_overrides.pop(provider_dependency, None)


def test_a_users_own_key_is_not_subject_to_the_shared_daily_cap(client, auth, mock, monkeypatch):
    save(client, auth)
    monkeypatch.setattr(main, "SERVER_KEY_DAILY_LIMIT", 1)
    main._daily_use.clear()
    from app.main import assist_limiter
    assist_limiter.reset()
    for _ in range(3):
        assert client.post("/v1/assist", json={"text": "log an egg"}, headers=auth).json()["notice"] is None


def test_security_headers_everywhere(client, auth):
    for path, headers in (("/", {}), ("/healthz", {}), ("/v1/me", auth)):
        r = client.get(path, headers=headers)
        assert r.headers["x-content-type-options"] == "nosniff" and r.headers["x-frame-options"] == "DENY"
        csp = r.headers["content-security-policy"]
        assert "script-src 'self'" in csp and "frame-ancestors 'none'" in csp and "object-src 'none'" in csp
        assert "unsafe-eval" not in csp and "script-src 'self' 'unsafe" not in csp
    assert client.get("/v1/me", headers=auth).headers["cache-control"] == "no-store"
    assert "strict-transport-security" not in client.get("/healthz").headers
    assert "max-age" in client.get("/healthz", headers={"x-forwarded-proto": "https"}).headers["strict-transport-security"]


def test_oversized_requests_are_refused(client, auth):
    r = client.put("/v1/state", content=b"x" * 1_100_000, headers={**auth, "content-type": "application/json"})
    assert r.status_code == 413


# ---------------------------------------------------------------- account security
def test_change_name_and_email(client, auth):
    assert client.patch("/v1/account", json={"name": "Aarav K"}, headers=auth).json()["name"] == "Aarav K"
    assert client.get("/v1/me", headers=auth).json()["name"] == "Aarav K"
    no_pw = client.patch("/v1/account", json={"email": "new@example.com"}, headers=auth)
    assert no_pw.status_code == 403
    wrong = client.patch("/v1/account", json={"email": "new@example.com", "currentPassword": "bad bad bad"}, headers=auth)
    assert wrong.status_code == 403
    ok = client.patch("/v1/account", json={"email": "New@Example.com", "currentPassword": PASSWORD}, headers=auth)
    assert ok.json()["email"] == "new@example.com"
    assert client.post("/v1/auth/login", json={"email": "new@example.com", "password": PASSWORD}).status_code == 200
    assert client.post("/v1/auth/login", json={"email": "a@example.com", "password": PASSWORD}).status_code == 401


def test_email_must_be_unique_and_valid(client, auth):
    signup(client, "taken@example.com")
    r = client.patch("/v1/account", json={"email": "taken@example.com", "currentPassword": PASSWORD}, headers=auth)
    assert r.status_code == 409
    assert client.patch("/v1/account", json={"email": "nonsense"}, headers=auth).status_code == 422


def test_password_change_signs_out_other_devices(client, auth):
    second = {"Authorization": f"Bearer {client.post('/v1/auth/login', json={'email': 'a@example.com', 'password': PASSWORD}).json()['token']}"}
    assert client.get("/v1/me", headers=second).status_code == 200
    r = client.post("/v1/account/password", json={"currentPassword": PASSWORD, "newPassword": "a brand new pass"}, headers=auth)
    assert r.status_code == 204
    assert client.get("/v1/me", headers=auth).status_code == 200            # this device stays signed in
    assert client.get("/v1/me", headers=second).status_code == 401          # the other one is out
    assert client.post("/v1/auth/login", json={"email": "a@example.com", "password": PASSWORD}).status_code == 401
    assert client.post("/v1/auth/login", json={"email": "a@example.com", "password": "a brand new pass"}).status_code == 200


def test_password_change_validation(client, auth):
    assert client.post("/v1/account/password", json={"currentPassword": "wrong one!", "newPassword": "long enough pw"}, headers=auth).status_code == 403
    assert client.post("/v1/account/password", json={"currentPassword": PASSWORD, "newPassword": "short"}, headers=auth).status_code == 422


def test_sessions_list_and_sign_out_others(client, auth):
    chrome = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0 Safari/537.36"
    client.post("/v1/auth/login", json={"email": "a@example.com", "password": PASSWORD}, headers={"user-agent": chrome})
    sessions = client.get("/v1/sessions", headers=auth).json()["sessions"]
    assert len(sessions) == 2 and sum(s["current"] for s in sessions) == 1
    assert "Chrome on Mac" in {s["device"] for s in sessions}
    assert client.post("/v1/sessions/revoke-others", headers=auth).status_code == 204
    assert len(client.get("/v1/sessions", headers=auth).json()["sessions"]) == 1
    assert client.get("/v1/me", headers=auth).status_code == 200


def test_calendar_link_can_be_reset(client, auth):
    client.post("/v1/onboarding", json=ONBOARDING, headers=auth)
    old = client.get("/v1/me", headers=auth).json()["calendarToken"]
    assert client.get(f"/v1/calendar/{old}.ics").status_code == 200
    new = client.post("/v1/calendar/rotate", headers=auth).json()["calendarToken"]
    assert new != old
    assert client.get(f"/v1/calendar/{old}.ics").status_code == 404
    assert client.get(f"/v1/calendar/{new}.ics").status_code == 200


def test_weight_log(client, auth):
    client.post("/v1/onboarding", json={**ONBOARDING, "timezone": "UTC"}, headers=auth)
    assert client.post("/v1/weights", json={"kg": 82, "date": "2026-10-01"}, headers=auth).status_code == 200
    client.post("/v1/weights", json={"kg": 80.5, "date": "2026-10-15"}, headers=auth)
    client.post("/v1/weights", json={"kg": 79.2, "date": "2026-10-20"}, headers=auth)
    client.post("/v1/weights", json={"kg": 79.0, "date": "2026-10-20"}, headers=auth)       # same day updates
    weights = client.get("/v1/weights", headers=auth).json()["weights"]
    assert [(w["date"], w["kg"]) for w in weights] == [("2026-10-01", 82), ("2026-10-15", 80.5), ("2026-10-20", 79.0)]
    assert client.get("/v1/state", headers=auth).json()["profile"]["weightKg"] == 79.0
    assert client.get("/v1/profile/stats", headers=auth).json()["weightChangeKg"] == -3.0
    assert client.delete("/v1/weights/2026-10-15", headers=auth).status_code == 204
    assert len(client.get("/v1/weights", headers=auth).json()["weights"]) == 2
    for bad in ({"kg": 5}, {"kg": 900}, {"kg": "heavy"}, {"kg": 70, "date": "tomorrow"}):
        assert client.post("/v1/weights", json=bad, headers=auth).status_code == 422


def test_recalculate_targets_after_body_changes(client, auth):
    client.post("/v1/onboarding", json=ONBOARDING, headers=auth)
    before = client.get("/v1/state", headers=auth).json()["profile"]["calorieGoal"]
    state = client.get("/v1/state", headers=auth).json()
    state["profile"].update(goal="build", weightKg=90)
    state["updatedAt"] = (datetime.now(timezone.utc) + timedelta(seconds=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
    client.put("/v1/state", json=state, headers=auth)
    out = client.post("/v1/plan/recalculate", headers=auth).json()
    assert out["profile"]["calorieGoal"] > before and out["summary"]["weeklyChangeKg"] > 0
    assert len(out["plan"]) == 4 and len(out["reminders"]) == 7              # workouts and routine untouched


def test_recalculate_needs_finished_setup(client, auth):
    assert client.post("/v1/plan/recalculate", headers=auth).status_code == 409


def test_profile_stats_streak(client, auth):
    client.post("/v1/onboarding", json={**ONBOARDING, "timezone": "UTC"}, headers=auth)
    now = datetime.now(timezone.utc)
    meals = [{"id": f"00000000-0000-0000-0000-00000000000{i}", "name": "Egg", "calories": 78,
              "date": (now - timedelta(days=i)).strftime("%Y-%m-%dT%H:%M:%SZ")} for i in (0, 1, 2, 4)]
    client.put("/v1/state", json={"meals": meals, "updatedAt": now.strftime("%Y-%m-%dT%H:%M:%SZ")}, headers=auth)
    stats = client.get("/v1/profile/stats", headers=auth).json()
    assert stats["streak"] == 3 and stats["workouts"] == 0 and stats["memberSince"]


def test_provider_redirect_only_exists_in_test_mode(monkeypatch):
    from app.endpoints import endpoint
    url = "https://api.anthropic.com/v1/models"
    monkeypatch.setenv("PULSE_FAKE_PROVIDER_URL", "http://127.0.0.1:9911")
    monkeypatch.delenv("PULSE_ENV", raising=False)
    assert endpoint("anthropic", url) == url                      # never redirected without PULSE_ENV=test
    monkeypatch.setenv("PULSE_ENV", "production")
    assert endpoint("anthropic", url) == url
    monkeypatch.setenv("PULSE_ENV", "test")
    assert endpoint("anthropic", url) == "http://127.0.0.1:9911/anthropic/v1/models"
    monkeypatch.setenv("PULSE_FAKE_PROVIDER_URL", "https://evil.example.com")
    assert endpoint("anthropic", url) == url                      # and only ever to localhost


def test_correct_passwords_never_trigger_the_lockout(client, auth, mock):
    for _ in range(12):                                   # far more than the 5 wrong-guess limit
        assert save(client, auth).status_code == 200
    assert client.post("/v1/connectors/anthropic/remove", json={"password": PASSWORD}, headers=auth).status_code == 204


def test_a_correct_password_resets_the_wrong_guess_count(client, auth, mock):
    for _ in range(4):
        assert save(client, auth, password="wrong wrong").status_code == 403
    assert save(client, auth).status_code == 200          # right one clears the counter
    for _ in range(4):
        assert save(client, auth, password="wrong wrong").status_code == 403
