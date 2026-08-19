Check the Astrid iOS to-do list and autonomously work every open task to completion using the /fixstuff workflow. Designed to be safe to re-run on a schedule.

## Goal

**Drive the iOS list to empty.** Unlike `/fixstuff`, this does not ask which task to
work on — it takes them in priority order and keeps going until nothing is left.
It stops on its own when the list is clear, so a scheduled re-run that finds an
empty list is a no-op, not busywork.

## Guardrails (do not skip)

- **DO NOT PUSH unless Jon asks for a build** (Jon, 2026-08-18). Work locally: branch,
  commit, merge into `iosdev`, keep the gates green — and stop there. Push `iosdev`,
  `macdev` or `main` only when he asks to build or test.

  This reverses the earlier "ship every fix as it lands" instruction, and the reason is
  concrete rather than cautious: **it burned through the Xcode Cloud usage allotment.**
  Every ship pushed three branches and started FOUR runs — `iosdev`, `macdev`, plus iOS
  Release and Mac Release on `main` — so one fix cost four runs, and shipping several
  fixes an hour apart exhausted the month. Once the allotment is gone, every run is
  created and cancelled before it starts (`startedDate: null`, `cancelReason: null`) and
  `POST /v1/ciBuildRuns` returns 500, which looks exactly like an Apple outage and cost
  hours to diagnose. See [[xcode-cloud-runs-canceled]].

  So: a task is DONE when it is merged into `iosdev` with `npm run predeploy` green. Say
  in the completion report that it is merged and waiting to be built, rather than
  claiming it shipped. Do not bump `CURRENT_PROJECT_VERSION` per fix either — see below.

  - **When Jon DOES ask for a build**, push all three (`iosdev`, `macdev`, `main`) so
    they cannot drift — the `Core/` tree is shared — and expect one build to carry
    several tasks. That is the trade for not burning the allotment: a TestFlight build no
    longer maps to a single change, so the completion reports have to carry the detail
    instead.
  - **`main` merging is still safe.** It starts the "iOS Release" and "Mac Release"
    workflows, which archive and upload to App Store Connect, but nothing here submits
    for review — that is a manual step in App Store Connect. Submitting still needs Jon.
    It is ALSO where half the compute went, which is the other reason not to push it
    casually.
  - **`CURRENT_PROJECT_VERSION` does not name the TestFlight build.** Measured
    2026-08-18: TestFlight's build numbers are the Xcode Cloud RUN numbers (877, 878,
    882, 884…) while the repo said 254. So bumping it per fix achieves nothing visible
    and is not worth a commit. Tell Jon the run number, or the commit, not the bump.
  - **An App Store submission, deleting files, or a significant architecture change still
    needs asking**, as before.
- **One branch per task** (`fix/<short-description>`), and `npm run predeploy` green
  before the task is marked complete.
- **Never push a red gate.** If a suite fails, fix it or stop and say so. A failing test
  that looks unrelated is still a failing test — say plainly that it is unrelated and why
  rather than pushing quietly past it.
- **If a task is ambiguous or needs a product decision, hand it back** — assign it to
  Jon and move it to `Waiting` (see "Say on the board what you are doing") — leave a
  comment saying what decision is needed, and move to the next one. Do not guess at
  intent, and do not stall the whole run on one blocked task.
  - The point of `Waiting` is that a re-run stops re-reading it. A blocked task left in
    Ready is re-examined every fifteen minutes forever and reported as blocked every
    time, which is the no-op loop this file exists to avoid.
- **If the same task fails twice**, stop working it, comment with what was tried and
  why it failed, and move on.
- **If the fix needs a server change, file it on the Astrid Web board** — see below.
  Do not leave it parked on the iOS list.

## When the fix turns out to need the server

Some iOS bugs cannot be fixed on the client at all. The 30-day sign-out was one: only
the server could issue a fresh token, so no amount of Swift would have helped.

**File the server half as its own task on the Astrid Web To-do list**
(`a623f322-4c3c-49b5-8a94-d2d9f00c82ba`), and say on the iOS task that you have done so.

Why it matters: a server task parked on the iOS board is invisible to the loop that
works the web board, so it does not get picked up — it just sits, and every re-run
reports it as blocked. That is exactly what happened with the session bug, which idled
for a full cycle of runs before anyone noticed the work belonged elsewhere.

```bash
cd ../astrid-web
cat > /tmp/web-task.json <<'JSON'
[{ "title": "[web] <what the server must do>", "priority": 3,
   "description": "<contract, evidence, and what the client does once it exists>" }]
JSON
ASTRID_IOS_LIST_ID=a623f322-4c3c-49b5-8a94-d2d9f00c82ba \
  DATABASE_URL="$DATABASE_URL_PROD" npx tsx scripts/create-ios-tasks.ts /tmp/web-task.json
```

(The script reads its list from `ASTRID_IOS_LIST_ID` despite the name, so overriding it
targets the web board. It skips titles that already exist there, so re-running is safe.)

**What the server task must contain**, because whoever picks it up will not have your
context:

- **The evidence**, with the commands to re-run it. "iOS gets signed out" is a report;
  "`mobile-session` returns 401 once `exp` passes and no route emits `Set-Cookie`" is a
  finding someone can act on.
- **The contract the client needs** — the exact field, where it appears, and when. Say
  what absence means, since that is the case that gets mishandled.
- **What the client will do once it exists**, so the two halves are designed together
  rather than negotiated after the fact.
- **Whether the halves are safe to ship independently.** Usually they are if the client
  treats the new field as optional — say so explicitly, because it decides whether
  anyone has to coordinate a release.

**Then keep the iOS half honest.** If the client work can land before the server (it
usually can), do it and ship it — but do not close the iOS task while users are still
affected. Say plainly what remains. A merged server branch is not a deployed one:
astrid-web does not auto-deploy, so `main` having the fix changes nothing until someone
deploys, and the iOS task stays open until then.

## Say on the board what you are doing

The board is where Jon looks. A task being worked and a task nobody has touched must
not look identical there.

**Starting a task → move it to `Doing`.** Do this BEFORE the strategy comment, so the
window where the board is wrong is as small as possible:

```bash
cd ../astrid-web && npx tsx scripts/set-task-status.ts <taskId> Doing
```

**Blocked on Jon → hand it back: assign to him AND move it to `Waiting`.** Both, not
one. Assigning alone leaves it sitting in Doing, which reads as in-progress; moving
alone leaves it assigned to Claude, which reads as still yours:

```bash
cd ../astrid-web && npx tsx scripts/assign-task.ts <taskId> jonparis@gmail.com
cd ../astrid-web && npx tsx scripts/set-task-status.ts <taskId> Waiting
```

Then say on the task what decision you need. A task in Waiting with no question on it
is just a task nobody is working.

Either order is safe — a half-done handoff lands the task outside the queue's scope
whichever step succeeded, so the loop will not pick it back up mid-handoff.

**Use `set-task-status.ts`, never `move-task-to-list.ts`.** Status is a SECOND
membership alongside the board, and `PUT` replaces the whole `listIds` set, so
`move-task-to-list.ts` — correct for moving between boards — would put the task on
Doing and take it off the Astrid iOS To-do, out of every queue, findable only by id.
The status script keeps the board, refuses to write if the task would be stranded, and
reads back to prove it.

**Completing a task takes it out of `Doing` on its own** — no status change needed
before marking it complete.

## Steps

1. **Ensure environment is set up** — copy `.env.local` from astrid-web if not present:
   ```bash
   cp ../astrid-web/.env.local .env.local 2>/dev/null || true
   ```

2. **Pull the queue — one call**:
   ```bash
   cd ../astrid-web && npx tsx scripts/ready-tasks.ts ios
   ```
   Prints `READY_EMPTY`, or the queue in the order to work it (priority high → low,
   then oldest first).

   **This is the same script the web loop uses**, with the board as an argument, so
   both loops get the same guarantees: `Ready` ∩ `Astrid iOS To-do`, only tasks that
   are unassigned or assigned to Claude, a loud failure if either list is missing by
   name, and a printed reason for everything it skipped. A second implementation for
   iOS would drift, and the drift would be silent — a queue that is wrong looks
   exactly like a quiet day.

   `Ready` is account-wide, shared by every board, so filtering on it alone would
   queue whatever Jon marked ready on the *web* board and put two agents in the same
   repo. Both halves are required.

   Direct-DB alternative when the OAuth path is flaky, but note it applies NEITHER
   filter — you are on your own for scope:
   `DATABASE_URL="$DATABASE_URL_PROD" npx tsx scripts/ios-tasks-direct.ts`

   **ONLY tasks assigned to Claude.** Assignment is the handshake (Jon, 2026-08-15).
   Not unassigned, not "looks like agent work" — assigned.

   Unassigned used to qualify, on the reasoning that nobody had claimed it. That made
   `Ready` mean *actionable AND unclaimed*, so anything Jon dropped into Ready to think
   about was fair game for a loop that would start on it within fifteen minutes.
   Requiring the assignment inverts the default: nothing is yours until it is handed
   over, and Ready goes back to meaning only *ready*.

   The script prints what it skipped with the assignee's name, so a queue held up by
   someone else's work never looks like an idle one. If something is genuinely yours,
   say so and let Jon assign it; do not work around the filter.

3. **If the list is empty**, say so in one line and stop. Nothing else to do.

4. **Otherwise, report the queue** — task ids and titles in the order you will work
   them (priority high → low, then oldest first) — then start on the first one
   without waiting for a reply.

5. **For each task**, follow the coding workflow in [ASTRID.md](../../ASTRID.md):
   - **Move it to `Doing` first**, before anything else, so the board stops showing it
     as untouched while you work:
     ```bash
     cd ../astrid-web && npx tsx scripts/set-task-status.ts <taskId> Doing
     ```
   - **Post the session link** so the user can follow along on mobile:
     ```bash
     cd ../astrid-web && npx tsx scripts/post-session-link.ts <taskId>
     ```
   - Analyze the issue — read the description AND its comments/attachments. A
     screenshot attached to the task is usually the fastest route to the real cause.
   - **Check where the fix actually lives before writing any.** If the cause is
     server-side, file the server half on the Astrid Web board now (see "When the fix
     turns out to need the server") rather than discovering it three steps later.
   - Post a short strategy comment to the task before writing code.
   - Create a feature branch (`fix/<short-description>`).
   - **RED-GREEN TDD (mandatory for bug fixes):**
     1. Write a failing test that reproduces the bug, citing the task id in the test
        name. Confirm it fails for the right reason.
     2. Implement the minimum change to make it pass.
     3. Refactor while tests stay green.
   - Run `npm run predeploy` (plus the Mac suites for Mac tasks) and fix regressions.
   - **Land it** — see step 6. Merge into `iosdev` locally and STOP; do not push.
   - Post a completion report on the task saying it is merged and waiting to be built,
     and mark it complete. A task is done when it is merged with the gates green — the
     build is a separate event now, and holding tasks open for it would leave the whole
     board waiting on Jon asking for a build.

6. **Land the task on `iosdev` — locally. Do not push.**
   ```bash
   git checkout iosdev && git merge --no-ff fix/<branch> -m "Merge: <what> (Task: <id>)"
   ```
   - **Re-run the gates on the MERGED tree**, not just on the branch. A merge can break
     what neither side broke alone:
     ```bash
     npm run predeploy
     xcodebuild test -scheme "Astrid Mac" -destination "platform=macOS" \
       -only-testing:"Astrid MacTests" -quiet
     ```
   - **No `CURRENT_PROJECT_VERSION` bump.** It does not name the TestFlight build —
     measured 2026-08-18, TestFlight numbers are the Xcode Cloud RUN numbers while the
     repo said 254 — so a bump per fix is a commit that changes nothing anyone sees.
   - **Stop here.** Unpushed work is not lost work; it is work waiting for a build Jon
     has asked for.

6b. **When Jon asks for a build**, push all three so they cannot drift, then watch:
   ```bash
   git push origin iosdev
   git checkout macdev && git merge --ff-only iosdev && git push origin macdev
   git checkout main   && git merge --no-ff iosdev -m "Merge iosdev: <what>"
   git push origin main && git checkout iosdev
   ```
   - That push starts FOUR runs (iosdev, macdev, iOS Release, Mac Release). Budget for it.
   - Xcode Cloud picks the push up by webhook, which has been seen to lag anywhere from
     0 to ~36 minutes. That lag is normal — do not retrigger on a hunch. If you do need a
     manual `POST /v1/ciBuildRuns`, it **must** carry
     `relationships.sourceBranchOrTag` (an `scmGitReferences` id) or it defaults to
     `main` and 409s.
   - **If runs are created and cancelled with `startedDate: null`, the allotment is gone.**
     Say so and stop; pushing again only creates more cancelled runs. See
     [[xcode-cloud-runs-canceled]].

7. **RE-CHECK THE LIST AFTER EVERY TASK — never work from the opening snapshot.**
   New tasks arrive while work is in progress, and a REOPENED task looks exactly
   like one that was never done:
   ```bash
   cd ../astrid-web && npx tsx scripts/ready-tasks.ts ios
   ```
   Re-check with the SAME filtered script you opened with. The direct-DB script
   applies neither the board nor the assignee filter, so re-checking with it hands
   back work that was deliberately scoped out — including tasks someone has claimed
   since the run began, which is exactly when a claim is most likely to be fresh.

   Work anything new or reopened before declaring the list clear. A reopened task
   means the previous fix missed — re-read it and find a different cause rather than
   re-closing it on the same reasoning.

8. **When the list is empty**, summarize in a few lines: what shipped and in which
   build, and anything skipped and why. Nothing should be "waiting to ship" — if
   something is, say why it could not go out. Describe the work in plain language by
   what it does, not by commit hash or task id.

See [ASTRID.md](../../ASTRID.md) for architecture and the full coding workflow, and
`/fixstuff` for the interactive, pick-one-task-at-a-time version of this.
