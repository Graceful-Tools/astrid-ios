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

**Work lands on `main`. Pushing `iosdev` / `macdev` is what makes a TestFlight build —
and finished work gets pushed without being asked for** (Jon, 2026-09-06).

| Branch | Xcode Cloud workflow | Scheme | Goes to |
|--------|---------------------|--------|---------|
| `main` | *none — no automatic trigger* | — | where work lands |
| `iosdev` | iOS Internal testers | `Astrid App` | TestFlight (internal) |
| `macdev` | Mac app internal testers | `Astrid Mac` | TestFlight (internal) |
| `main` (manual) | iOS Release + Mac Release | both | **App Store submission** |

```bash
npm run predeploy                    # 1. Verify (must pass)
git add -A && git commit             # 2. Commit (message includes task id if applicable)
git push origin main                 # 3. Land the work — builds nothing
git push origin iosdev macdev        # 4. Build it → Xcode Cloud → TestFlight
```

**Step 4 is not a question.** Jon, 2026-09-06: *"I want to look at work when you are
done. I don't want to tell you to push it so I can look at it and then wait."* A build
he has to ask for is a build he waits for twice — once for the ask to be answered, once
for the run. So finishing ends with the push, and the report says a build is on the way
rather than offering one. Push both dev branches together — they share the `Core/` tree
and drift is hard to see.

**But push ONCE per session, not once per task.** This is the constraint the old
ask-first rule was really protecting: a push used to start four Xcode Cloud runs, and
shipping several fixes an hour apart exhausted the monthly allotment on 2026-08-18,
after which every run was created and cancelled before it started. Batching a session's
work into one push is what keeps that from coming back — so one build carries several
tasks, and the completion reports have to carry the per-task detail instead.

**The two Release workflows are manual-only** (changed 2026-08-27). They no longer
trigger on `main`: an App Store build is started deliberately, from App Store
Connect or via `POST /v1/ciBuildRuns`. Before that change, one push to `main`
started four runs — two TestFlight and two App Store — which is what exhausted
the monthly compute allotment on 2026-08-18 and left every run cancelled for days.

**No `CURRENT_PROJECT_VERSION` bump per push.** It does not name the TestFlight build:
measured 2026-08-18, TestFlight's numbers are the Xcode Cloud RUN numbers (877, 878,
882…) while the repo said 254. Tell Jon the run number or the commit, not the bump.
A version bump belongs to an App Store submission, which is a deliberate act anyway.
Check build status in App Store Connect.

### Local build → App Store Connect (no Xcode Cloud)

When Xcode Cloud can't run — most often its monthly compute allotment is spent and every run is
created then immediately `CANCELED` — build and upload from this machine instead:

```bash
npm run release:ios          # build + sign only, nothing sent to Apple
npm run release:ios:upload   # gate, archive, upload, wait for the build to read VALID
npm run release:mac
npm run release:mac:upload
```

Each run ends with a single `RESULT: OK` / `RESULT: FAILED` line saying what happened. Signing and
the build number are automatic (the App Store Connect key in `.env.local` stands in for the Xcode
account). **Ask before an `:upload`** — it cannot be undone. Full procedure:
`.claude/skills/appstore-release/SKILL.md`.

---

## Approvals

**Always ask the user before:** an App Store **submission** — the manual iOS Release /
Mac Release workflows, or a local `:upload` — significant architecture/API changes, or
deleting files. Those reach real users or are hard to undo.

**Autonomous (no approval needed):** code analysis, local builds/tests, implementation,
local commits, documentation updates, and **pushing `main`, `iosdev` and `macdev`**.

**A TestFlight build is how Jon looks at the work, so it is part of finishing, not a
separate request** (2026-09-06). The line is not "how much compute does this spend" but
"does anyone outside see it": an internal build is for looking at, an App Store
submission goes to real users. Spend is handled by batching — one push per session (see
Deployment) — not by waiting to be told.

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
| [`../astrid-web/docs/WEEKLY_DEEP_REVIEW.md`](../astrid-web/docs/WEEKLY_DEEP_REVIEW.md) | Weekly cross-repo deep review — driven from this board by a repeating Astrid task (`/weekly-deep-review`) |
| `docs/GOOGLE_OAUTH_SETUP.md`, `docs/SHARE_EXTENSION_SETUP.md`, `docs/XCODE_SETUP.md` | Setup guides |

---

*This file is for Codex. Claude Code reads [CLAUDE.md](./CLAUDE.md) (same content).
All architecture lives in [ASTRID.md](./ASTRID.md) — do not duplicate it here.*
