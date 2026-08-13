Check the Astrid iOS to-do list and autonomously work every open task to completion using the /fixstuff workflow. Designed to be safe to re-run on a schedule.

## Goal

**Drive the iOS list to empty.** Unlike `/fixstuff`, this does not ask which task to
work on — it takes them in priority order and keeps going until nothing is left.
It stops on its own when the list is clear, so a scheduled re-run that finds an
empty list is a no-op, not busywork.

## Guardrails (do not skip)

- **Never push, merge, or deploy without an explicit go-ahead.** Committing locally is
  autonomous; pushing always waits for the user. Report what is ready to ship instead
  of shipping it.
  - **`iosdev` and `macdev` are the release branches** — pushing either builds to
    TestFlight. Those are the pushes with real consequences.
  - **`main` no longer triggers a release build** (confirmed with Jon 2026-08-09). It is
    the integration branch. An earlier version of this file said `main` was the App Store
    branch; that was wrong, and it made every merge to `main` look more dangerous than it
    is. Do not restore that wording without re-checking with Jon.
- **One branch per task** (`fix/<short-description>`), and `npm run predeploy` green
  before the task is marked complete.
- **If a task is ambiguous or needs a product decision, skip it**, leave a comment on
  the task saying what decision is needed, and move to the next one. Do not guess at
  intent, and do not stall the whole run on one blocked task.
- **If the same task fails twice**, stop working it, comment with what was tried and
  why it failed, and move on.

## Steps

1. **Ensure environment is set up** — copy `.env.local` from astrid-web if not present:
   ```bash
   cp ../astrid-web/.env.local .env.local 2>/dev/null || true
   ```

2. **Pull iOS tasks**:
   ```bash
   cd ../astrid-web && npx tsx scripts/get-astrid-tasks.ts ios
   ```
   Direct-DB alternative when the OAuth script is flaky:
   `DATABASE_URL="$DATABASE_URL_PROD" npx tsx scripts/ios-tasks-direct.ts`

3. **If the list is empty**, say so in one line and stop. Nothing else to do.

4. **Otherwise, report the queue** — task ids and titles in the order you will work
   them (priority high → low, then oldest first) — then start on the first one
   without waiting for a reply.

5. **For each task**, follow the coding workflow in [ASTRID.md](../../ASTRID.md):
   - **Post the session link** so the user can follow along on mobile:
     ```bash
     cd ../astrid-web && npx tsx scripts/post-session-link.ts <taskId>
     ```
   - Analyze the issue — read the description AND its comments/attachments. A
     screenshot attached to the task is usually the fastest route to the real cause.
   - Post a short strategy comment to the task before writing code.
   - Create a feature branch (`fix/<short-description>`).
   - **RED-GREEN TDD (mandatory for bug fixes):**
     1. Write a failing test that reproduces the bug, citing the task id in the test
        name. Confirm it fails for the right reason.
     2. Implement the minimum change to make it pass.
     3. Refactor while tests stay green.
   - Run `npm run predeploy` (plus the Mac suites for Mac tasks) and fix regressions.
   - Post a completion report on the task and mark it complete.

6. **RE-CHECK THE LIST AFTER EVERY TASK — never work from the opening snapshot.**
   New tasks arrive while work is in progress, and a REOPENED task looks exactly
   like one that was never done:
   ```bash
   cd ../astrid-web && DATABASE_URL="$DATABASE_URL_PROD" npx tsx scripts/ios-tasks-direct.ts
   ```
   Work anything new or reopened before declaring the list clear. A reopened task
   means the previous fix missed — re-read it and find a different cause rather than
   re-closing it on the same reasoning.

7. **When the list is empty**, summarize in a few lines: tasks completed, tasks
   skipped and why, and which branches are waiting to ship. Then ask whether to ship.

See [ASTRID.md](../../ASTRID.md) for architecture and the full coding workflow, and
`/fixstuff` for the interactive, pick-one-task-at-a-time version of this.
