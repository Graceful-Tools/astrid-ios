# Astrid for iOS and Mac

Native iOS, iPadOS and macOS apps for Astrid task management with AI assistance.
One repository, two shipping apps: the `Astrid App` scheme (iOS/iPadOS) and the
`Astrid Mac` scheme (macOS), sharing the service layer in `Astrid App/Core/`.

**Repository:** https://github.com/Graceful-Tools/astrid-ios
**Web App:** https://github.com/Graceful-Tools/astrid-web
**Production:** https://astrid.cc

## Download

**Mac — [latest release](https://github.com/Graceful-Tools/astrid-ios/releases/latest)**
A signed and notarized `.dmg` is attached to every `mac-v*` GitHub Release (Developer ID,
stapled, so it opens without a Gatekeeper detour). The [astrid.cc download
page](https://astrid.cc/download) resolves the newest one automatically — publishing a release
is the only step needed to ship a Mac update. Requires macOS 15 or later.

The binary lives on the Release, not in the git tree; `build/` is ignored. To produce one, see
[Mac app](#mac-app) below.

**iPhone & iPad — [TestFlight beta](https://testflight.apple.com/join/V11WpM3d)**

Sign-in note: the direct-download Mac build offers Passkey, Google and email. Sign in with Apple
is available in the TestFlight and App Store builds only — Apple does not issue that entitlement
in Developer ID provisioning profiles, so the DMG hides the button rather than showing one that
fails on click (see `MacSignInOptions`).

## Features

- Two-way sync with Google Tasks (all-lists modes, bidirectional) and Apple Reminders
- Sub-tasks with nested display and progress counts
- Per-list chat with AI agents and attachments

- **Sign in with Apple** (required for App Store)
- **Google Sign In** (OAuth 2.0 with PKCE)
- **Email/password** authentication
- Task management (create, edit, complete, delete)
- List management with colors and privacy
- Real-time sync via Server-Sent Events
- Offline storage with Core Data
- iPad optimized layouts
- **Share Extension** - Create tasks from Photos, Files, Safari
- **GitHub Integration** - Two-way GitHub Issues sync (tasks, sub-issues, comments, assignees) + repository links for AI coding agents

## Quick Start

### Prerequisites

- Xcode 26.0+
- iOS 18.6+ deployment target
- Apple Developer account (for Sign in with Apple)
- Google Cloud account (for Google Sign In)

### Setup

1. **Open the project**
   ```bash
   open "Astrid App.xcodeproj"
   ```

2. **Verify Google OAuth configuration** (Required)
   - Follow instructions in [docs/GOOGLE_OAUTH_SETUP.md](./docs/GOOGLE_OAUTH_SETUP.md)
   - Confirm the checked-in public iOS client ID and URL scheme match the app's bundle ID
   - For new bundle IDs/environments, create a new iOS OAuth client and update the public client ID + URL scheme together
   - Do not commit OAuth client secrets, API tokens, or private credentials to the iOS repo

3. **Enable Sign in with Apple**
   - In Xcode: Target > Signing & Capabilities
   - Click "+ Capability"
   - Add "Sign in with Apple"

4. **Build and Run**
   - Select iPhone simulator
   - Press Cmd+R to build and run
   - Test authentication flows

## Project Structure

```
astrid-ios/
├── Astrid App/
│   ├── Core/
│   │   ├── Authentication/    # Apple/Google OAuth
│   │   ├── Networking/        # API client
│   │   ├── Persistence/       # Core Data stack
│   │   ├── Services/          # Business logic
│   │   ├── Notifications/     # Push notifications
│   │   └── Sync/              # Data synchronization
│   ├── Models/                # Data models
│   ├── Views/                 # SwiftUI views
│   ├── ViewModels/            # View models
│   ├── Extensions/            # Swift extensions
│   ├── Utilities/             # Helpers and constants
│   └── Resources/
│       └── Localizations/     # 12 language translations
├── Astrid AppTests/           # Unit tests
├── Astrid AppUITests/         # UI tests
├── Astrid/                    # Share extension target (built from Astrid/)
├── docs/                      # Technical documentation
└── scripts/                   # Build and test scripts
```

## Development

### Build and Test Commands

```bash
# Build the app
npm run build

# Run unit tests
npm run test

# Run all tests (unit + UI)
npm run test:all

# Predeploy checks (before pushing)
npm run predeploy

# Full predeploy (includes UI tests)
npm run predeploy:full
```

### Mac app

```bash
# Build + unit-test the Mac target
xcodebuild build-for-testing -scheme "Astrid Mac" -destination "platform=macOS" \
  -derivedDataPath /tmp/astrid-mac-dd -allowProvisioningUpdates
xcodebuild test-without-building -scheme "Astrid Mac" -destination "platform=macOS" \
  -derivedDataPath /tmp/astrid-mac-dd -only-testing:"Astrid MacTests"

# Build a signed, notarized DMG (needs a Developer ID certificate)
npm run package:mac

# Run the exact Xcode Cloud binary locally, without TestFlight
node scripts/mac-ci-build.mjs --open
```

`build-for-testing` matters after any entitlements change — `build` alone leaves stale test
products and the test host fails to launch.

TestFlight on iPhone/iPad never lists Mac builds; they appear only in the **TestFlight app on
macOS**. `scripts/mac-ci-build.mjs` sidesteps that by downloading the newest successful Xcode
Cloud macOS archive and launching it.

### Configuration

**Backend API**

The app connects to `https://astrid.cc`. To change this, edit `Astrid App/Utilities/Constants.swift`:

```swift
enum API {
    // Environment-derived: DEBUG → localhost/LAN (debug_server_url override), RELEASE → https://astrid.cc — see Utilities/Constants.swift
}
```

## Localization

The app supports 12 languages:
- English (en) - Base
- Spanish (es)
- French (fr)
- German (de)
- Italian (it)
- Japanese (ja)
- Korean (ko)
- Dutch (nl)
- Portuguese (pt)
- Russian (ru)
- Simplified Chinese (zh-Hans)
- Traditional Chinese (zh-Hant)

Localization files are in `Astrid App/Resources/Localizations/`.

## API Integration

The app integrates with the Astrid backend:

- **Authentication**: `/api/v1/auth/apple`, `/api/v1/auth/google`, `/api/v1/auth/mobile-*`
- **Tasks**: `/api/v1/tasks` (CRUD operations)
- **Lists**: `/api/v1/lists` (CRUD operations)
- **Comments**: `/api/v1/tasks/{id}/comments`
- **Real-time**: `/api/v1/sse` (Server-Sent Events)
- **GitHub**: `/api/v1/github/repositories`

See [docs/API_CONTRACT.md](./docs/API_CONTRACT.md) for the full API specification.

## Security

- **PKCE** for Google OAuth (prevents code interception)
- **Nonce** for Apple Sign In (prevents replay attacks)
- **Keychain storage** for sensitive data
- **Server-side token validation**
- **HTTPOnly session cookies**

## Deployment

Day-to-day work ships from the dev branches; `main` is reserved for App Store releases:

```bash
# Run predeploy checks first
npm run predeploy

# Then push to the dev branch for the platform you changed
git push origin iosdev     # or macdev for Mac-only work
```

Xcode Cloud runs four workflows:

| Branch | Workflow | Scheme | Goes to |
|--------|----------|--------|---------|
| `iosdev` | `iOS Internal testers` | `Astrid App` | TestFlight (internal) |
| `macdev` | `Mac app internal testers` | `Astrid Mac` | TestFlight (internal) |
| `main` | `iOS Release` | `Astrid App` | App Store submission |
| `main` | `Mac Release` | `Astrid Mac` | App Store submission |

Merge into `main` only when cutting an actual App Store release. Bump
`CURRENT_PROJECT_VERSION` before pushing; Xcode Cloud stamps its own build number on CI
archives, but local archives (the DMG) use this one.

Publishing a Mac release:

```bash
npm run package:mac
gh release create mac-v$VERSION build/dist/Astrid-Mac-$VERSION.dmg --title "Astrid for Mac $VERSION"
```

The tag and filename both come from the Mac target's `MARKETING_VERSION`, so bump it before
cutting a second release or it collides with the previous tag.

## Documentation

### Setup Guides
- [docs/XCODE_SETUP.md](./docs/XCODE_SETUP.md) - Complete Xcode setup
- [docs/GOOGLE_OAUTH_SETUP.md](./docs/GOOGLE_OAUTH_SETUP.md) - Google OAuth configuration
- [docs/SHARE_EXTENSION_SETUP.md](./docs/SHARE_EXTENSION_SETUP.md) - Share extension setup

### Technical Docs
- [docs/API_CONTRACT.md](./docs/API_CONTRACT.md) - Backend API specification
- [docs/LOCAL_FIRST_PATTERN.md](./docs/LOCAL_FIRST_PATTERN.md) - Offline-first architecture

### Contributing
- [CONTRIBUTING.md](./CONTRIBUTING.md) - How to contribute
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) - Community standards
- [SECURITY.md](./SECURITY.md) - Security vulnerability reporting

## Architecture

Writes journal through the unified Outbox (`Core/Outbox/` — idempotent, retrying, dependency-ordered); reads are cache-first with a 60s SyncManager pull + SSE. External sync providers live in `Core/Sync/`. See `docs/LOCAL_FIRST_PATTERN.md`.

The app follows a local-first architecture pattern:

1. **Write Local, Sync Background** - All mutations save to Core Data immediately
2. **Read from Cache First** - UI reads Core Data, never waits for network
3. **Optimistic Updates** - Show changes instantly with temp IDs
4. **Background Sync** - 60-second timer + network restoration triggers

See [docs/LOCAL_FIRST_PATTERN.md](./docs/LOCAL_FIRST_PATTERN.md) for details.

## Code Style

- **SwiftUI** for all views
- **Async/await** for asynchronous operations
- **MVVM-like** architecture (Views + Services)
- **No external dependencies** (system frameworks only)

## Related Repositories

- **Web App & Backend**: https://github.com/Graceful-Tools/astrid-web
- **iOS App**: This repository

## Support

For issues or questions:
- iOS app bugs: Open an issue in this repository
- Backend/API issues: Check the [web app repository](https://github.com/Graceful-Tools/astrid-web)
- OAuth setup help: See [docs/GOOGLE_OAUTH_SETUP.md](./docs/GOOGLE_OAUTH_SETUP.md)

## License

MIT License - see [LICENSE](./LICENSE) for details.

---

**Built with Swift and SwiftUI**
