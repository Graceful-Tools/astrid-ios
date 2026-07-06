# Astrid iOS App

Native iOS app for Astrid task management with AI assistance.

**Repository:** https://github.com/Graceful-Tools/astrid-ios
**Web App:** https://github.com/Graceful-Tools/astrid-web
**Production:** https://astrid.cc

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
- **GitHub Integration** - Two-way GitHub Issues sync (tasks, sub-issues, comments, assignees) + repository links for AI coding agents for AI coding agents

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

2. **Configure Google OAuth** (Required)
   - Follow instructions in [docs/GOOGLE_OAUTH_SETUP.md](./docs/GOOGLE_OAUTH_SETUP.md)
   - Create iOS OAuth Client ID in Google Cloud Console
   - Update `GoogleSignInManager.swift` with your credentials
   - Add URL scheme to Xcode project

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

Push to main triggers Xcode Cloud build automatically:

```bash
# Run predeploy checks first
npm run predeploy

# Then push
git push origin main
```

TestFlight builds are distributed via Xcode Cloud.

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
