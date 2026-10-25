"""Encryption for user-supplied API keys.

* AES-256-GCM with a fresh random nonce per encryption.
* A separate sub-key per user and provider, derived from the master key with HKDF, and the user and
  provider are also bound in as authenticated data. A stolen ciphertext cannot be moved to another
  account or provider and still decrypt.
* The master key lives only in the environment (PULSE_ENCRYPTION_KEYS), never in the database, so a
  database leak alone reveals nothing. Several keys can be listed, newest first: new data uses the
  first, old data still decrypts with the others, which makes key rotation possible.
* If no key is configured the feature refuses to run. There is no weak fallback.

Generate a key:   python -m app.crypto
"""
from __future__ import annotations

import base64
import hashlib
import os
import secrets

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

VERSION = "v1"


class SecretsUnavailable(RuntimeError):
    """No usable encryption key is configured on this server."""


class SecretsCorrupt(RuntimeError):
    """The stored value could not be decrypted (wrong key, moved, or tampered with)."""


def _decode_key(text: str) -> bytes:
    raw = text.strip()
    for decoder in (base64.urlsafe_b64decode, base64.b64decode):
        try:
            key = decoder(raw + "=" * (-len(raw) % 4))
            if len(key) == 32:
                return key
        except ValueError:
            continue
    raise SecretsUnavailable("PULSE_ENCRYPTION_KEYS must contain base64 keys of exactly 32 bytes")


def key_id(key: bytes) -> str:
    return hashlib.sha256(key).hexdigest()[:8]


class SecretBox:
    def __init__(self, keys: list[bytes]):
        if not keys:
            raise SecretsUnavailable("No encryption key configured")
        self._keys = {key_id(k): k for k in keys}
        self._primary = keys[0]

    @classmethod
    def from_env(cls) -> "SecretBox":
        raw = os.environ.get("PULSE_ENCRYPTION_KEYS", "")
        parts = [p for p in raw.split(",") if p.strip()]
        if not parts:
            raise SecretsUnavailable("PULSE_ENCRYPTION_KEYS is not set")
        return cls([_decode_key(p) for p in parts])

    @staticmethod
    def _subkey(master: bytes, user_id: str, provider: str) -> bytes:
        return HKDF(algorithm=hashes.SHA256(), length=32, salt=None,
                    info=f"pulse-connector|{user_id}|{provider}".encode()).derive(master)

    @staticmethod
    def _aad(user_id: str, provider: str) -> bytes:
        return f"{user_id}|{provider}".encode()

    def encrypt(self, plaintext: str, user_id: str, provider: str) -> str:
        nonce = secrets.token_bytes(12)
        sub = self._subkey(self._primary, user_id, provider)
        ct = AESGCM(sub).encrypt(nonce, plaintext.encode(), self._aad(user_id, provider))
        b64 = lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")  # noqa: E731
        return ".".join([VERSION, key_id(self._primary), b64(nonce), b64(ct)])

    def decrypt(self, token: str, user_id: str, provider: str) -> str:
        try:
            version, kid, nonce_b64, ct_b64 = token.split(".")
            if version != VERSION or kid not in self._keys:
                raise SecretsCorrupt("Unknown key version")
            pad = lambda s: s + "=" * (-len(s) % 4)  # noqa: E731
            sub = self._subkey(self._keys[kid], user_id, provider)
            plain = AESGCM(sub).decrypt(base64.urlsafe_b64decode(pad(nonce_b64)),
                                        base64.urlsafe_b64decode(pad(ct_b64)), self._aad(user_id, provider))
            return plain.decode()
        except (ValueError, InvalidTag) as exc:
            raise SecretsCorrupt("Could not decrypt the stored key") from exc

    def needs_rotation(self, token: str) -> bool:
        return token.split(".")[1] != key_id(self._primary)


def generate_key() -> str:
    return base64.urlsafe_b64encode(secrets.token_bytes(32)).decode()


if __name__ == "__main__":
    print(generate_key())
