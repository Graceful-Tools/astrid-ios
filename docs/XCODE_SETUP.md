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
workflow (push to `iosdev` / `macdev` → Xcode Cloud → TestFlight; `main` is
reserved for App Store release builds).

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

## Pointing a Debug build at your own dev server

By default a Debug build talks to:

| where it runs | server |
|---|---|
| iOS Simulator | `http://localhost:3000` — the simulator shares the Mac's loopback |
| physical iOS device | **production** |
| Mac app | **production** |

A physical device cannot reach `localhost`, so it needs a routable address for
your machine. That address used to be hardcoded in `Constants.swift`, which
meant the repository named one developer's home LAN IP: everybody else's device
build pointed at an unreachable host, with nothing on screen saying why
(AITD-351). It is now a build setting you supply.

**Set `ASTRID_DEV_SERVER_URL`.** The recommended way is an untracked
`Debug.xcconfig` next to the project:

```
// Debug.xcconfig — DO NOT COMMIT
ASTRID_DEV_SERVER_URL = http://192.168.1.42:3000
```

then set it as the Debug configuration file for the **Astrid App** target
(Project → Info → Configurations → Debug). A User-Defined build setting on the
target works just as well if you prefer not to add a file.

`Info-Debug.plist` passes it through as `AstridDevServerURL`, and
`Constants.API.devServerURL` reads it. When it is unset — a fresh clone, CI —
it expands to an empty string, reads as "no dev server", and the device build
falls back to production. Nothing to configure if you do not need it.

Two consequences of setting it:

- On-device Debug builds use it instead of production.
- A **Dev Server (Device)** row appears in Settings → Connection. That row is
  hidden when no dev server is configured, since an option that silently meant
  "production" would be worse than no option at all.

You can still override any of this at runtime from Settings → Connection, which
writes the `debug_server_url` preference and beats everything above.

Plain HTTP to a LAN address is permitted in Debug by `NSAllowsLocalNetworking`
in `Info-Debug.plist` — no per-address ATS exception needed, and please do not
add one: the old exception named a *different* IP from the one the app actually
used, so it sat there covering nothing.

Release builds are unaffected. `Constants.API.environment` is `.production`
outside `DEBUG`, and `Info-Debug.plist` is referenced only by the iOS Debug
configuration.

`DevServerConfigurationTests` fails the build if a private-network address
(RFC 1918: `10.x`, `192.168.x`, `172.16–31.x`) reappears in tracked Swift or
plist files. For fixtures that need an address, use `192.0.2.x` — TEST-NET-1,
reserved for documentation and guaranteed to belong to nobody.
