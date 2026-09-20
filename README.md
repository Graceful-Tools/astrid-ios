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
is the only step needed to ship a Mac update. Requires macOS 14 or later.

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
- **Passkeys** (WebAuthn; email/password sign-in was removed in 2026-04)
- Task management (create, edit, complete, delete)
- List management with colors and privacy
- Real-time sync via Server-Sent Events
- Offline storage with Core Data
- iPad optimized layouts
- **Share Extension** - Create tasks from Photos, Files, Safari
- **GitHub Integration** - Two-way GitHub Issues sync (tasks, sub-issues, comments, assignees) + repository links for AI coding agents
- **AI Agents & Connections** - the Agent Hub (who runs each agent: Astrid, your own harness, a webhook server, Custom Agents) and Connections (everything that can act as your account, revocable), on iOS and the Mac; see `docs/API_ENDPOINTS.md`

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
├── Astrid Mac/                # macOS app shell (shares Astrid App/Core)
├── Shared/                    # Files compiled into the app and the share extension
├── Astrid/                    # Share extension target
├── Astrid AppTests/, Astrid AppUITests/, Astrid MacTests/, Astrid MacUITests/
├── docs/                      # Technical documentation
└── scripts/                   # Build and test scripts
```

## Development

### Build and Test Commands

`npm run predeploy` is the standard gate before pushing. The full table of `npm run`
commands, what each runs, and where the tests live is in [CLAUDE.md](./CLAUDE.md)
§Quality Gates. `npm run simulator:prepare` boots the exact iPhone simulator once so later
runs reuse it.

### Mac app

```bash
# Build + unit-test the Mac target
npm run test:mac

# Build a signed, notarized DMG (needs a Developer ID certificate)
npm run package:mac

# Run the exact Xcode Cloud binary locally, without TestFlight
node scripts/mac-ci-build.mjs --open
```

`build-for-testing` matters after any entitlements change — `build` alone leaves stale test
products and the test host fails to launch.

The first simulator boot after installing a new runtime can spend several minutes migrating
system data. `npm run simulator:prepare` leaves that exact device booted, so local and Actions
test runs reuse it instead of selecting a similarly named Pro model or paying another cold boot.

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

Every path the app calls (all under `/api/v1/`) is listed in
[docs/API_ENDPOINTS.md](./docs/API_ENDPOINTS.md), which a unit test keeps in step with the
source. Wire shapes, SSE events and error codes are in
[docs/API_CONTRACT.md](./docs/API_CONTRACT.md).

## Security

- **PKCE** for Google OAuth (prevents code interception)
- **Nonce** for Apple Sign In (prevents replay attacks)
- **Keychain storage** for sensitive data
- **Server-side token validation**
- **HTTPOnly session cookies**

## Deployment

Work lands on `main`; pushing `iosdev` / `macdev` starts the Xcode Cloud TestFlight builds;
App Store submissions are manual. The branch table, the batching rule and the local
build-and-upload path are in [CLAUDE.md](./CLAUDE.md) §Deployment.

Publishing a direct-download Mac release:

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
- [ASTRID.md](./ASTRID.md) - Architecture rules and cross-platform contracts (read first)
- [docs/API_ENDPOINTS.md](./docs/API_ENDPOINTS.md) - Every API path the app calls
- [docs/API_CONTRACT.md](./docs/API_CONTRACT.md) - Wire shapes, SSE events, errors
- [docs/LOCAL_FIRST_PATTERN.md](./docs/LOCAL_FIRST_PATTERN.md) - Outbox and caching
- [docs/SYNC_ARCHITECTURE.md](./docs/SYNC_ARCHITECTURE.md) - External sync providers
- [docs/MAC_SIGNING.md](./docs/MAC_SIGNING.md), [docs/MAC_DISTRIBUTION.md](./docs/MAC_DISTRIBUTION.md) - Mac signing and release channels

### Contributing
- [CONTRIBUTING.md](./CONTRIBUTING.md) - How to contribute
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) - Community standards
- [SECURITY.md](./SECURITY.md) - Security vulnerability reporting

## Architecture

Local-first: every write applies optimistically, then journals through the unified Outbox;
reads are cache-first. [ASTRID.md](./ASTRID.md) holds the rules and control points,
[docs/LOCAL_FIRST_PATTERN.md](./docs/LOCAL_FIRST_PATTERN.md) the mechanism.

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
