Check the Astrid iOS to-do list and autonomously work every open task to completion using the /fixstuff workflow. Designed to be safe to re-run on a schedule.

## Goal

**Drive the iOS list to empty.** Unlike `/fixstuff`, this does not ask which task to
work on — it takes them in priority order and keeps going until nothing is left.
It stops on its own when the list is clear, so a scheduled re-run that finds an
empty list is a no-op, not busywork.

## Guardrails (do not skip)

- **Ship every fix to TestFlight as it lands** (standing authorization from Jon,
  2026-08-13). A task is not finished when it is committed; it is finished when Jon can
  test it on his device. Do not stop to ask — the asking was the bottleneck, and that is
  exactly what this instruction removes. Ship one task at a time rather than batching, so
  a TestFlight build maps to a single change and a regression is obvious.
  - **`iosdev` and `macdev` both build to TestFlight.** Push both, even for a Mac-only
    fix — the `Core/` tree is shared, and letting them drift means the next iOS build
    silently lacks code the Mac build has.
  - **`main` is the integration branch, and merging to it is safe** — but be precise
    about why (verified against the Xcode Cloud API 2026-08-13). It *does* start the
    "iOS Release" and "Mac Release" workflows, which archive and upload to App Store
    Connect. What it does not do is submit anything for review: submission is a manual
    step in App Store Connect and nothing here performs it. An earlier version of this
    file said `main` was "the App Store branch", which overstated the risk, and a later
    one said it "does not trigger a release build", which understated what runs. Merging
    is autonomous; submitting for review still needs Jon.
  - **The standing authorization covers shipping fixes from this list.** It is not a
    blanket approval: an App Store submission, deleting files, or a significant
    architecture change still needs asking.
- **One branch per task** (`fix/<short-description>`), and `npm run predeploy` green
  before the task is marked complete.
- **Never push a red gate.** If a suite fails, fix it or stop and say so. A failing test
  that looks unrelated is still a failing test — say plainly that it is unrelated and why
  rather than pushing quietly past it.
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
   - **Ship it** — see step 6. Do this BEFORE marking the task complete, so a task is
     never closed on something Jon cannot yet test.
   - Post a completion report on the task, including the build number it shipped in,
     and mark it complete.

6. **Ship the task to TestFlight.** Merge, bump, verify, push:
   ```bash
   git checkout iosdev && git merge --no-ff fix/<branch> -m "Merge: <what> (Task: <id>)"
   ```
   - **Bump `CURRENT_PROJECT_VERSION`** in `Astrid App.xcodeproj/project.pbxproj` (all
     occurrences) — a duplicate build number is the most common way a Xcode Cloud build
     fails after everything else passed.
   - **Re-run the gates on the MERGED tree**, not just on the branch. A merge can break
     what neither side broke alone:
     ```bash
     npm run predeploy
     xcodebuild test -scheme "Astrid Mac" -destination "platform=macOS" \
       -only-testing:"Astrid MacTests" -quiet
     ```
   - Push both release branches, then integrate:
     ```bash
     git push origin iosdev
     git checkout macdev && git merge --ff-only iosdev && git push origin macdev
     git checkout main   && git merge --no-ff iosdev -m "Merge iosdev: <what> (build N)"
     git push origin main && git checkout iosdev
     ```
   - Xcode Cloud picks the push up by webhook, which has been seen to lag anywhere from
     0 to ~36 minutes. That lag is normal — do not retrigger on a hunch. If you do need a
     manual `POST /v1/ciBuildRuns`, it **must** carry
     `relationships.sourceBranchOrTag` (an `scmGitReferences` id) or it defaults to
     `main` and 409s.

7. **RE-CHECK THE LIST AFTER EVERY TASK — never work from the opening snapshot.**
   New tasks arrive while work is in progress, and a REOPENED task looks exactly
   like one that was never done:
   ```bash
   cd ../astrid-web && DATABASE_URL="$DATABASE_URL_PROD" npx tsx scripts/ios-tasks-direct.ts
   ```
   Work anything new or reopened before declaring the list clear. A reopened task
   means the previous fix missed — re-read it and find a different cause rather than
   re-closing it on the same reasoning.

8. **When the list is empty**, summarize in a few lines: what shipped and in which
   build, and anything skipped and why. Nothing should be "waiting to ship" — if
   something is, say why it could not go out. Describe the work in plain language by
   what it does, not by commit hash or task id.

See [ASTRID.md](../../ASTRID.md) for architecture and the full coding workflow, and
`/fixstuff` for the interactive, pick-one-task-at-a-time version of this.
