# Pulse

Personal fitness companion for Apple Watch, iPhone and (planned) web: calorie tracking, gym plan,
reminders and a voice assistant. Design lives in the "Personal Fitness Companion" canvas.

```
pulse/
  shared/foods.json      Food database. Used by the backend AND bundled in both apps.
  backend/               FastAPI service: holds AI keys, talks to Claude / OpenAI / Gemini.
  apple/Shared/          Swift code shared by iPhone and Watch (models, store, sync, assistant).
  apple/PulseWatch/      Apple Watch app (SwiftUI, watchOS 10).
  apple/PulseiOS/        iPhone app (SwiftUI, iOS 17).
  apple/Tests/           Unit tests.
  project.yml            XcodeGen spec. The .xcodeproj is generated, not committed.
```

## What works today

| Area | State |
| --- | --- |
| Backend `/v1/assist` (Claude, OpenAI, Gemini, local fallback) | Built, 12 tests pass |
| Voice food logging: AI reads *what* you said, the database supplies the numbers | Built |
| Watch: Home, Workout (crown, rest timer, HealthKit session), Assistant, Routine | Written, **not yet compiled** |
| iPhone: Onboarding, Today, Food, Train, Routine, Profile, Siri-style assistant | Written, **not yet compiled** |
| iPhone to Watch sync (WatchConnectivity, latest snapshot + meal merge) | Written, not yet run on devices |

The Swift code was written without access to Xcode, so expect a few compile fixes on first build.
The GitHub Actions workflow `.github/workflows/pulse.yml` builds both apps on a macOS runner, so every
push tells you exactly what to fix.

## Apple Watch sizes

Supports every size from 40 mm (162 pt wide) to 49 mm (Ultra). `WatchMetrics` scales graphics from a 198 pt
baseline, text uses Dynamic Type styles, every screen scrolls, and the rings/stats switch to a stacked layout
when space is tight. Open `WatchPreviews.swift` in Xcode to see Home, Assistant and Workout on 40, 41, 45 and 49 mm.

## Run the backend

```bash
cd pulse/backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
python -m pytest -q

export PULSE_API_TOKEN=choose-a-long-random-string
export PULSE_PROVIDER=anthropic          # or openai, gemini; omit for the offline rule-based mode
export ANTHROPIC_API_KEY=...             # OPENAI_API_KEY / GEMINI_API_KEY for the others
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Without a provider key the server answers using the built-in parser, so the apps still work.

## Build the apps (on a Mac)

```bash
brew install xcodegen
cd pulse
cp apple/Secrets.example.xcconfig apple/Secrets.xcconfig   # fill in your server URL and token
xcodegen generate
open Pulse.xcodeproj
```

In `project.yml` change `bundleIdPrefix`/bundle ids and set `DEVELOPMENT_TEAM`. Run the **Pulse** scheme on an
iPhone; the Watch app installs with it. Enable the HealthKit and Sign in with Apple capabilities for your team.

## Known gaps (next milestones)

- **Accounts:** "Sign in with Apple" is wired in the UI but not verified by a server yet. The app token is a shared
  development secret; production needs per-user sessions.
- **Watch voice:** watchOS has no speech recognizer, so the Watch uses the system dictation sheet. The custom
  listening screen from the design is iPhone-only until audio is sent to the server for transcription.
- **Sync deletes:** deleting a meal while the other device is offline can bring it back (needs tombstones).
- **Watch standalone reminders:** daily reminders are scheduled by the iPhone and mirrored to the Watch.
- **Not started:** web app, recipes, calendar events, shopping list, complications, data export/delete.

Nutrition numbers are estimates. This app gives general guidance, not medical advice.
