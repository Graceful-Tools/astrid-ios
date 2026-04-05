# Claude Code CLI - Operational Context

*Local Claude Code CLI workflow for the Astrid iOS app*

**Repository:** https://github.com/Graceful-Tools/astrid-ios
**Web App:** https://github.com/Graceful-Tools/astrid-web (separate repo)

---

## Quick Start

```bash
# Open in Xcode
open "Astrid App.xcodeproj"

# Run predeploy checks before pushing
npm run predeploy
```

---

## Quality Gates

```bash
# Quick check (localizations + build only)
npm run predeploy:quick

# Standard check (localizations + build + unit tests)
npm run predeploy

# Full check with UI tests (slower)
npm run predeploy:full

# Run specific test suites
npm run test          # Unit tests only
npm run test:ui       # UI tests only
npm run test:all      # Both unit and UI tests

# Localization validation
npm run check:localizations
```

---

## Deployment Workflow

**IMPORTANT: Push to main triggers Xcode Cloud build automatically.**

### Before Pushing

Always run predeploy checks:

```bash
npm run predeploy
```

This validates:
1. All localizations are complete (12 languages)
2. Project builds successfully
3. Unit tests pass

### Deployment Steps

```bash
# 1. Run predeploy checks
npm run predeploy

# 2. Commit changes
git add -A
git commit -m "feat: your changes"

# 3. Push to main (triggers Xcode Cloud)
git push origin main
```

### Xcode Cloud

- Push to main triggers automatic build
- TestFlight builds are distributed automatically
- Check build status in App Store Connect

---

## User Approval Points

### Always Ask Before:

1. **Pushing to main** - Triggers production build
2. **Significant changes** - Architecture, API changes
3. **Deleting files** - Confirm with user first

### Autonomous Actions (No Approval Needed)

- Code analysis and exploration
- Local builds and tests
- Implementation and testing
- Local commits
- Documentation updates

---

## Workflow Trigger: "Let's Fix Stuff"

When user says "let's fix stuff", "just fix stuff", or similar (or use `/fixstuff`):

```bash
# 1. Ensure environment is set up
# Copy .env.local from astrid-web if not present
cp ../astrid-web/.env.local .env.local 2>/dev/null || true

# 2. Pull tasks from Astrid iOS To-do list
cd ../astrid-web && npx tsx scripts/get-astrid-tasks.ts ios
```

Present tasks to the user and ask which to work on. Run `npm run predeploy` **after** implementation, not before.

### Environment Setup

Required variables (in `.env.local`, copied from astrid-web):
- `ASTRID_OAUTH_CLIENT_ID` - OAuth client ID
- `ASTRID_OAUTH_CLIENT_SECRET` - OAuth client secret
- `ASTRID_IOS_LIST_ID` - iOS task list ID (`aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36`)

---

## Testing

### Test Commands

| Command | Description |
|---------|-------------|
| `npm run test` | Run unit tests |
| `npm run test:ui` | Run UI tests only |
| `npm run test:all` | Run both unit and UI tests |

### Test File Locations

| Test Type | Location |
|-----------|----------|
| Unit tests | `Astrid AppTests/Tests/UnitTests/` |
| Integration tests | `Astrid AppTests/Tests/IntegrationTests/` |
| Test mocks | `Astrid AppTests/Tests/Mocks/` |
| UI tests | `Astrid AppUITests/` |

### Xcode Commands (Alternative)

```bash
# Build
xcodebuild build -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -quiet

# Run unit tests
xcodebuild test -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"Astrid AppTests" -quiet

# Run UI tests
xcodebuild test -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"Astrid AppUITests" -quiet
```

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `npm run predeploy:quick` | Quick check (build only) |
| `npm run predeploy` | Standard check (build + unit tests) |
| `npm run predeploy:full` | Full check (includes UI tests) |
| `npm run test` | Run unit tests |
| `npm run test:all` | Run all tests |
| `npm run check:localizations` | Validate translations |
| `npm run build` | Build app (quiet mode) |

### Common Workflows

| Scenario | Action |
|----------|--------|
| Before pushing | `npm run predeploy` |
| After localization changes | `npm run check:localizations` |
| Full validation | `npm run predeploy:full` |
| Debug build issues | `npm run build:verbose` |

---

## Chat & Agent Features

### Per-List Chat
Every list (including My Tasks) has a chat channel accessible via the chat toggle button in the header. Chat supports:
- **@mentions** for users and AI agents (format: `@[Name](id)`)
- **#list** and **!task** references (format: `#[Name](id)`, `![Name](id)`)
- **File attachments** — photos and documents via paperclip button, with offline queue support
- **AI agent responses** — @mention Astrid or configured agents; server-side processing via `processAstridMessage`
- **Real-time updates** — SSE for live messages + 3-second polling fallback

### Key Chat Files

| File | Purpose |
|------|---------|
| `Views/Chat/ChatPanelView.swift` | Main chat container with channel resolution |
| `Views/Chat/ChatInputView.swift` | Rich input with @/#/! autocomplete + attachments |
| `Views/Chat/ChatMessageBubble.swift` | Message rendering with agent indicators |
| `Views/Chat/ChatMessageListView.swift` | Scrollable message list with pagination |
| `Views/Chat/ChatToggleView.swift` | Header toggle button (tasks ↔ chat) |
| `Core/Services/ChatService.swift` | Local-first service with offline sync |
| `Core/Persistence/CDChatMessage+CoreDataClass.swift` | CoreData persistence |
| `Models/ChatMessage.swift` | ChatChannel + ChatMessage domain models |
| `Models/DTOs/ChatDTOs.swift` | API request/response types |

### Chat API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/chat/channels` | POST | Get or create channel for list/virtual key |
| `/api/chat/channels/{id}/messages` | GET | Paginated messages (cursor-based) |
| `/api/chat/channels/{id}/messages` | POST | Send message (with optional fileId + attachment fields) |
| `/api/user/available-agents` | GET | List AI agents for @mention |
| `/api/user/ai-assistant-settings` | GET/PATCH | Default agent preferences |

### Attachment Upload Flow
1. User picks photo/document → `AttachmentService.saveLocallyAndUploadAsync(context:)` saves locally + starts background upload
2. Context is `{"listId": "..."}` for list channels or `{"channelId": "..."}` for virtual channels
3. Upload goes to `/api/secure-upload/request-upload` (<4MB) or `/api/secure-upload/get-upload-url` + direct blob (≥4MB)
4. On send, `ChatService.syncPendingCreate` resolves temp fileId → real fileId and sends with attachment metadata
5. Server associates `SecureFile` with `ChatMessage` via `chatMessageId`
6. Response includes `secureFiles` array for rendering

### Offline Support
- Messages saved to CoreData with `syncStatus: "pending"` and `clientRequestId` for deduplication
- Attachments cached locally with temp IDs, uploaded when online
- `ChatService.syncPendingMessages()` triggered on network restoration

---

## Documentation

### Root Files

- `CLAUDE.md` - Claude Code CLI context (this file)
- `README.md` - Project overview
- `CONTRIBUTING.md` - Contribution guidelines
- `SECURITY.md` - Security policy
- `CODE_OF_CONDUCT.md` - Community standards

### Technical Docs (in `/docs/`)

- `API_CONTRACT.md` - Backend API specification
- `LOCAL_FIRST_PATTERN.md` - Offline-first architecture
- `GOOGLE_OAUTH_SETUP.md` - Google OAuth configuration
- `SHARE_EXTENSION_SETUP.md` - Share extension setup
- `XCODE_SETUP.md` - Complete Xcode setup

---

## See Also

- **[README.md](./README.md)** - Project overview and setup
- **[docs/API_CONTRACT.md](./docs/API_CONTRACT.md)** - API specification
- **[docs/LOCAL_FIRST_PATTERN.md](./docs/LOCAL_FIRST_PATTERN.md)** - Offline architecture
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** - How to contribute

---

*This file is for Claude Code CLI.*
