# Codex — Astrid iOS Operational Adapter

*Local Codex CLI workflow for the Astrid iOS app.*

**Repository:** https://github.com/Graceful-Tools/astrid-ios
**Web app (separate repo):** https://github.com/Graceful-Tools/astrid-web

> This file is intentionally kept near-identical to [CLAUDE.md](./CLAUDE.md); only the
> tool name differs. Both are thin adapters. **All architecture lives in
> [ASTRID.md](./ASTRID.md)** — never copy architecture into this file.

---

## ⚠️ Read ASTRID.md before writing code

**[ASTRID.md](./ASTRID.md) is the single source of truth for all architecture** —
the service layer / Canonical Control Points, the Unified Outbox, Repeating Tasks,
external sync, chat, and cross-platform contracts. This file (AGENTS.md) holds only
commands and workflow. **Open ASTRID.md before changing any code that touches tasks,
completion, repeating tasks, the Outbox, sync, chat, list members, or an API call.**

### Critical rules (full detail in ASTRID.md §0)

1. **Backend writes go through the service layer** — never call `AstridAPIClient`
   directly from a view, timer, notification handler, or sync worker. Add the method
   to the service first.
2. **Complete a task ONLY via `TaskService.completeTask(...)`** — never
   `updateTask(completed: true)` (that skips repeat rollover).
3. **Completing from an editable view?** Copy edited fields (`dueDateTime`, `isAllDay`,
   `repeating`, `repeatingData`, `repeatFrom`) into the `task:` argument first.
4. **Next-occurrence math lives ONLY in `RepeatingTaskCalculator`** — never inline it;
   mirror changes into `astrid-web/types/repeating.ts`.
5. **API paths are `/api/v1/...` only** — `/api/user/...` and `/api/chat/...` are dead.
6. **Preserve Outbox / offline behavior.** For breaking API changes, add a new version.
7. **Bug fixes are TDD:** RED regression test (name the task id) → green → `npm run predeploy`.
8. **Reuse before you write.** Never inline permission checks or hardcode user-facing
   copy — use the shared filtering/permission helpers in `Astrid App/Core/` and
   `Localizable.strings` keys. Permission decisions and shared strings are a
   cross-platform contract with Web: see
   [astrid-web `docs/PRODUCT_CONTRACT.md`](https://github.com/Graceful-Tools/astrid-web/blob/main/docs/PRODUCT_CONTRACT.md)
   for the permission matrix both platforms must honor and the Web-i18n ⇄
   iOS-`Localizable.strings` key registry. Diverging from it is a bug on whichever
   platform moved.

---

## Quick Start

```bash
open "Astrid App.xcodeproj"   # Open in Xcode
npm run predeploy             # Run standard checks before pushing
```

---

## Quality Gates

| Command | What it runs |
|---------|--------------|
| `npm run predeploy:quick` | Localizations + build (no tests) |
| `npm run predeploy` | Localizations + build + unit tests — **the standard gate before pushing** |
| `npm run predeploy:full` | Localizations + build + unit + UI tests |
| `npm run test` | Unit tests |
| `npm run test:ui` | UI tests only |
| `npm run test:all` | Unit + UI tests |
| `npm run check:localizations` | Validate translations (12 languages) |
| `npm run build` | Build app (quiet) |
| `npm run build:verbose` | Build app (verbose — for debugging build failures) |

### Test locations

| Type | Path |
|------|------|
| Unit tests | `Astrid AppTests/Tests/UnitTests/` |
| Integration tests | `Astrid AppTests/Tests/IntegrationTests/` |
| Test mocks | `Astrid AppTests/Tests/Mocks/` |
| UI tests | `Astrid AppUITests/` |

### Raw xcodebuild (alternative)

```bash
xcodebuild build -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -quiet
xcodebuild test  -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"Astrid AppTests"   -quiet
xcodebuild test  -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"Astrid AppUITests" -quiet
```

---

## Deployment

**Day-to-day work ships from `iosdev` / `macdev`. `main` is the App Store branch.**

| Branch | Xcode Cloud workflow | Scheme | Goes to |
|--------|---------------------|--------|---------|
| `iosdev` | iOS Internal testers | `Astrid App` | TestFlight (internal) |
| `macdev` | Mac app internal testers | `Astrid Mac` | TestFlight (internal) |
| `main` | iOS Release + Mac Release | both | **App Store submission** |

```bash
npm run predeploy               # 1. Verify (must pass)
git add -A && git commit        # 2. Commit (message includes task id if applicable)
git push origin iosdev          # 3. Push → Xcode Cloud → TestFlight
```

Use `macdev` for Mac-only work; push to both when a change spans the shared
`Core/` tree. Merge into `main` **only** when cutting an actual App Store
release — a push to `main` starts a build intended for submission.

After iOS changes, bump `CURRENT_PROJECT_VERSION` (build number) before pushing.
Check build status in App Store Connect.

---

## Approvals

**Always ask the user before:** pushing to `main` (starts an App Store release
build), significant architecture/API changes, or deleting files.

**Autonomous (no approval needed):** code analysis, local builds/tests, implementation,
local commits, documentation updates, pushing to `iosdev` / `macdev`.

---

## "Let's fix stuff"

When the user says "let's fix stuff" / "just fix stuff" / similar:

```bash
# 1. Ensure env is set up (credentials copied from astrid-web)
cp ../astrid-web/.env.local .env.local 2>/dev/null || true

# 2. Pull the iOS To-do list
cd ../astrid-web && npx tsx scripts/get-astrid-tasks.ts ios
```

Present the tasks, ask which to work on, then implement. Run `npm run predeploy`
**after** implementation, not before.

**Per-task process** (canonical, cross-repo — see `astrid-web/ASTRID_WORKFLOW.md`):
post a strategy comment → RED-GREEN-refactor TDD with a task-id-linked regression
test → run quality gates → post a completion report → then mark the task complete.

**Required env vars** (in `.env.local`, copied from astrid-web):
`ASTRID_OAUTH_CLIENT_ID`, `ASTRID_OAUTH_CLIENT_SECRET`,
`ASTRID_IOS_LIST_ID` (= `aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36`).

---

## Documentation map

| File | Purpose |
|------|---------|
| **[ASTRID.md](./ASTRID.md)** | **Architecture + all AI-agent contracts (read first)** |
| [README.md](./README.md) | Project overview and setup |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Contribution guidelines |
| `docs/API_CONTRACT.md` | Backend API specification |
| `docs/LOCAL_FIRST_PATTERN.md` | Offline-first / Outbox architecture |
| `docs/SYNC_ARCHITECTURE.md` | External sync providers |
| `docs/GOOGLE_OAUTH_SETUP.md`, `docs/SHARE_EXTENSION_SETUP.md`, `docs/XCODE_SETUP.md` | Setup guides |

---

*This file is for Codex. Claude Code reads [CLAUDE.md](./CLAUDE.md) (same content).
All architecture lives in [ASTRID.md](./ASTRID.md) — do not duplicate it here.*
