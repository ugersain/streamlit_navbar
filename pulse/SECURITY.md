# Security

How Pulse protects accounts and the AI API keys people connect. Written to be checked, not to reassure:
every claim below has an automated test (`backend/tests/test_security.py`, `web/e2e/e2e.cjs`).

## Bring-your-own AI key

| Protection | How | Test |
| --- | --- | --- |
| Encrypted at rest | AES-256-GCM, fresh random nonce each time. A separate sub-key per user and provider (HKDF), with the user and provider also authenticated. | `test_encrypt_roundtrip…`, `test_same_key_encrypts_differently…` |
| Stolen ciphertext is useless | The master key is only in the server environment (`PULSE_ENCRYPTION_KEYS`), never in the database. A ciphertext copied to another account or provider fails to decrypt. | `test_ciphertext_cannot_be_moved…`, `test_a_ciphertext_copied_to_another_account_is_useless` |
| Tampering is detected | GCM authentication. | `test_tampering_is_detected` |
| No weak fallback | With no encryption key configured the feature refuses to run (HTTP 503). It never stores plaintext. | `test_feature_is_off_without_a_server_encryption_key` |
| Key rotation | List several keys, newest first. New data uses the first, old data still decrypts. | `test_key_rotation_keeps_old_data_readable` |
| Never read back | No endpoint returns a key: only the last 4 characters, the provider and dates. Not in sync, export, logs or error messages. | `test_the_key_never_appears_in_any_response`, browser test scans the page, storage and API responses |
| Password to change | Adding, replacing or removing a key needs the account password. Only wrong guesses count against a 5 a minute limit, so honest use is never locked out. | `test_saving_needs_the_right_password`, `test_password_guessing_is_rate_limited` |
| Checked before saving | A free read-only call to the provider (list models). A rejected key is never stored. | `test_key_the_provider_rejects_is_not_stored` |
| Input is strict | Per-provider format, length cap, no whitespace or newlines. The key is never echoed, including in validation errors. | `test_malformed_keys_are_rejected_without_echoing_them` |
| No SSRF | Provider URLs are fixed in code. Users cannot supply a URL. The only test hook is ignored unless `PULSE_ENV=test` and only points at localhost. | `test_provider_redirect_only_exists_in_test_mode` |
| Kept out of logs | Provider objects hide the key in `repr`; error handling never includes request headers. | `test_key_never_reaches_the_logs`, `test_provider_objects_hide_their_key_in_repr` |
| Bad keys are handled | A provider that later rejects the key marks it, tells the user, and stops using it. Logging still works through the built-in parser. | `test_provider_that_later_rejects_the_key…` |
| Gone when asked | Removing a key, or deleting the account, deletes the row. | `test_removing_a_key…`, `test_deleting_the_account_wipes_stored_keys` |
| Abuse limits | 30 assistant requests a minute per user. A daily cap on the shared server key. A user's own key is not capped by Pulse. | `test_assistant_rate_limit`, `test_daily_cap_protects…` |
| The apps never keep it | The iPhone app sends the key once over HTTPS and clears the field. It is never written to disk, Keychain or the Watch. | `ConnectorClientTests` (Swift) |

## Accounts and the web app

* Passwords hashed with scrypt. Sessions are random 256-bit tokens, stored only as a SHA-256 hash, valid 90 days, revocable.
* Changing the password signs out every other device. Changing the email needs the password.
* Login and signup are rate limited, and login errors are identical for unknown email and wrong password.
* Strict headers on every response: a Content-Security-Policy with `script-src 'self'` (no inline or eval scripts),
  `frame-ancestors 'none'`, `nosniff`, `no-referrer`, HSTS over HTTPS, and `Cache-Control: no-store` on API responses.
* All user text is HTML-escaped before it reaches the page.
* Request bodies over 1 MB are refused.
* Validation errors never repeat what you typed (so they cannot echo a password or key).
* Calendar links are secret URLs that you can reset at any time.

## What this does NOT protect against

Being honest about the limits matters more than a bold claim:

1. **A fully compromised server.** To use a key, the server has to decrypt it, so someone who controls both the
   running server and its environment variables can read keys. Encryption at rest protects against database
   leaks, backups, other users and bugs, not against root on the live machine. Keep the server patched, restrict who can
   deploy, and never put `PULSE_ENCRYPTION_KEYS` in the repository.
2. **A stolen unlocked session plus the password.** Someone with both can replace or remove a key.
3. **The AI provider itself.** Pulse sends meal text to the provider you chose. Use a key with a spending limit,
   and revoke it from the provider's dashboard if you ever suspect a leak.
4. **Single-instance limits.** The rate limiters are in memory. Behind several servers, move them to a shared store.
5. **No email verification or password reset yet**, and no two-factor sign-in.

## Running it safely

* Serve over HTTPS only (the host usually does this). Set a Postgres `DATABASE_URL`.
* Generate the encryption key once with `python -m app.crypto`, store it in your host's secret manager, and back it up
  somewhere separate. **If it is lost, saved keys cannot be recovered** and users must add them again.
* To rotate: set `PULSE_ENCRYPTION_KEYS=<new>,<old>`, deploy, and later drop `<old>`.
* Never set `PULSE_ENV=test` in production.
* Prefer asking users for a restricted key with a spending limit.

## Reporting a problem

Open a private security advisory on the GitHub repository. Please don't post exploit details publicly.
