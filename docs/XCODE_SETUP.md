# Xcode Setup

The Xcode project is checked in — there is **no manual project creation**. Just
clone and open.

## Prerequisites

- macOS with **Xcode 26.0+**
- Deployment target: **iOS 18.6+**

## Open the project

```bash
git clone https://github.com/Graceful-Tools/astrid-ios.git
cd astrid-ios
open "Astrid App.xcodeproj"
```

Xcode resolves Swift Package dependencies automatically on first open.

## Configuration

- API base URL and other endpoints live in `Astrid App/Utilities/Constants.swift`
  (`Constants.API.baseURL`). No hardcoded URLs elsewhere.
- Local tooling reads `.env.local` (copied from `astrid-web` — see the root
  `CLAUDE.md` "Environment Setup").

## Build & test

```bash
npm run predeploy        # localizations + build + unit tests
xcodebuild build -scheme "Astrid App" \
  -destination "platform=iOS Simulator,name=iPhone 17" -quiet
```

See the root `CLAUDE.md` for the full quality-gate commands and the deploy
workflow (push to `main` triggers an Xcode Cloud build → TestFlight).

## Targets

- **Astrid App** — the main app.
- **Astrid** — the Share Extension (built from `Astrid/`).
- **Astrid AppTests / Astrid AppUITests** — unit and UI tests.

## Architecture

The app is offline-first: every backend write flows through the unified
**Outbox** (`Astrid App/Core/Outbox/`), and reads are cache-first (CoreData)
with a background pull + SSE. External sync (Apple Reminders / Google Tasks /
GitHub Issues) lives in `Astrid App/Core/Sync/`. See
[`LOCAL_FIRST_PATTERN.md`](./LOCAL_FIRST_PATTERN.md) and the root `CLAUDE.md`.
