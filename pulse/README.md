# Pulse

Personal fitness companion for Apple Watch, iPhone and web: calorie tracking, gym plan, reminders,
recipes, weekly meal plan, insights and a voice assistant. One account syncs everything.

```
pulse/
  backend/        FastAPI service: accounts, sync, plans, recipes, insights, calendar feed, AI assistant
  web/            The web app (plain JavaScript, no build step). Served by the backend at "/".
  shared/         foods.json and recipes.json, used by the backend AND bundled in the apps
  apple/Shared/   Swift code shared by iPhone and Watch (models, store, sync, assistant)
  apple/PulseWatch/  Apple Watch app (SwiftUI, watchOS 10)
  apple/PulseiOS/    iPhone app (SwiftUI, iOS 17)
  project.yml     XcodeGen spec. The .xcodeproj is generated, not committed.
  Dockerfile, render.yaml   Deployment
```

## What is built and how it is tested

| Area | State | How it is tested |
| --- | --- | --- |
| Accounts: sign up, log in, log out, delete account, data export | Done | 77 API tests + browser tests |
| Cloud sync (newer settings win, meals merge, deletes stick) | Done | API tests, including same-second edits and stale devices |
| Plan builder, workout split, routine from onboarding answers | Done | Unit + API tests |
| Voice/text food logging (AI reads what you said, a database supplies the numbers) | Done | Parser and provider tests; Claude, OpenAI and Gemini adapters tested against mock servers |
| Recipes, weekly meal plan, shopping list (never suggests your allergens) | Done | API tests |
| Insights (calories, protein, training, habits), calendar feed (.ics) | Done | API tests |
| Web app: every screen in the design | Done | 45-step browser test (`web/e2e/e2e.cjs`) |
| Apple Watch app (40 mm to 49 mm), iPhone app | Written, **not yet compiled** | CI builds and tests them on a Mac (`.github/workflows/pulse.yml`) |

The Swift code was written without Xcode available, so expect a few compile fixes on the first build.
Real speech recognition, HealthKit, notifications and WatchConnectivity can only be checked on devices.

## Run it locally

```bash
cd pulse/backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
python -m pytest -q                           # backend tests

# optional: a real AI provider. Without a key the built-in parser answers.
export PULSE_PROVIDER=anthropic ANTHROPIC_API_KEY=...     # or openai / gemini
uvicorn app.main:app --port 8000
```

Open http://localhost:8000, create an account and go through onboarding.

Browser tests (needs the server running and `npm i playwright`):

```bash
cd pulse/web && node e2e/e2e.cjs
```

## Deploy

`render.yaml` is a Render blueprint (web service from the Dockerfile plus a free Postgres). Or:

```bash
cd pulse && docker build -t pulse .
docker run -p 8000:8000 -e DATABASE_URL=postgresql://... -e PULSE_PROVIDER=anthropic -e ANTHROPIC_API_KEY=... pulse
```

Set `DATABASE_URL` to Postgres for anything real: SQLite on a host with a temporary disk loses data on restart.
API keys live only on the server, never in the apps or the web page.

## Build the apps (on a Mac)

```bash
brew install xcodegen
cd pulse
cp apple/Secrets.example.xcconfig apple/Secrets.xcconfig   # your server address
xcodegen generate && open Pulse.xcodeproj
```

Change the bundle ids in `project.yml` and set your Apple Developer team. A free Apple ID works for running on
your own devices (the app expires after 7 days). The Watch app installs with the iPhone app.

## Apple Watch sizes

Works on every size from 40 mm (162 pt wide) to 49 mm. `WatchMetrics` scales graphics from a 198 pt baseline,
text uses Dynamic Type, every screen scrolls and the rings switch to a stacked layout when space is tight.
Open `WatchPreviews.swift` in Xcode to see Home, Assistant and Workout on 40, 41, 45 and 49 mm.

## Known limits

- **Sign in with Apple and Google** are not included yet; accounts use email and password.
- **Watch voice:** watchOS has no speech recognizer, so the Watch uses the system dictation sheet.
- **Active energy** comes from Apple Health on the iPhone and Watch; the web app cannot show it.
- **Web voice** uses the browser's speech recognition where available (Chrome, Edge, Safari); other browsers can type.
- **No password reset email yet.** Needs an email provider.
- **Single server instance:** the login rate limiter is in memory.

Nutrition numbers are estimates. This app gives general guidance, not medical advice.
