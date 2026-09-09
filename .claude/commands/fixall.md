Check the Astrid iOS to-do list and autonomously work every open task to completion. Designed to be safe to re-run on a schedule.

## Goal

**Drive the iOS queue to empty.** Unlike `/fixstuff`, this does not ask which task to work on —
it takes them in the order the queue returns them and keeps going until nothing is left. It
stops on its own when the queue is clear, so a scheduled re-run that finds an empty queue is a
no-op, not busywork.

## One session per working tree — take the lock first

**Before anything else, including reading the queue:**

```bash
# FROM THE astrid-ios ROOT. Do NOT `cd ../astrid-web` first — see below.
../astrid-web/node_modules/.bin/tsx ../astrid-web/scripts/fixall-session.ts \
  acquire --pid $PPID --harness claude-code
```

Exit `0` means this checkout is yours. **Exit `2` means another live session is already running
`/fixall` here — stop, and do not read the queue.** Start again in your own worktree
(`npm run work:start <task-slug>` in astrid-web), which is what this steers toward rather than
away from: parallel runs are good, sharing one checkout is not.

Release when the run ends — the same command with `release --pid $PPID` — and `status` says who
holds the tree and whether they are still alive.

**Why not `cd ../astrid-web` like every other script here.** The lock is keyed to
`git rev-parse --absolute-git-dir` **of the current directory**, so running it from astrid-web
would lock the *web* checkout and leave this one unguarded — the exact failure the lock exists
to prevent, with a `0` exit that looks like success. Verified 2026-09-09: from astrid-ios the
git dir resolves to `astrid-ios/.git`; after `cd ../astrid-web` it resolves to
`astrid-web/.git`. astrid-ios has no `tsx` of its own, hence invoking astrid-web's binary by
path while staying put.

The OAuth scripts are the opposite case and **do** need `cd ../astrid-web`: `loadScriptEnv()`
looks for `.env.local` in `process.cwd()`, and that file lives in astrid-web. So the lock runs
from here and the claim runs from there — not a style difference, and swapping them breaks
both.

Three details that are easy to get wrong:

- **Pass `$PPID`, not the script's own pid.** In an agent's shell `$PPID` is the harness
  session itself, so the lock lives exactly as long as the run and clears itself if the
  session is killed. `process.pid` would be the `tsx` process, which exits in milliseconds, so
  every lock would read as stale to the next caller.
- **Staleness is process liveness, never an age limit.** A run can legitimately sit on one hard
  task for a long time, and a lock that expires under a working session is worse than no lock.

- **The lock is per working TREE, not per repository.** Two iOS sessions in two worktrees never
  see each other; two in one tree collide immediately. That is the arrangement to aim for.

**Why the board lanes do not already cover this.** `Ready` → `Doing` claims a **task**. It says
nothing about which **checkout** is being edited, and two sessions working two *different* tasks
in one tree corrupt each other just as thoroughly — on 2026-09-09 one moved `HEAD` while the
other had six files uncommitted. The lanes and the lock answer different questions; neither
substitutes for the other.

## Talk to Astrid through the MCP server — never the database

The `astrid` MCP server (`https://www.astrid.cc/mcp`, configured for this project) is the
**only** way this loop reads or writes tasks. Its tools:

| Need | Tool |
|------|------|
| The queue | `get_agent_queue` `{ agent: "claude", listId: "aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36" }` |
| Read a task | `get_task` `{ taskId }` and `get_task_comments` `{ taskId }` |
| Comment (strategy, progress, report) | `add_comment` `{ taskId, content, type: "MARKDOWN" }` |
| Complete | `update_task` `{ taskId, completed: true }` |
| File the other repo's half | `create_task` `{ listId: <other board>, title, description, priority }` |

If the MCP tools are not loaded, they are deferred — load them with
`ToolSearch "select:mcp__astrid__get_agent_queue,mcp__astrid__get_task,mcp__astrid__get_task_comments,mcp__astrid__add_comment,mcp__astrid__update_task,mcp__astrid__create_task"`.
If only `mcp__astrid__authenticate` exists, the server needs OAuth: call it, give Jon the URL,
and stop until he has authorised — do not fall back to scripts.

**Direct database access (`DATABASE_URL_PROD`, `ios-tasks-direct.ts`, `create-ios-tasks.ts`,
Prisma) is for deep repair only** — Jon, 2026-08-29 — and never part of this loop. It bypasses
visibility, the assignee handshake and the due-date gate, and a queue read that way hands back
work that was deliberately scoped out.

**What the MCP cannot do yet:** claim a task, move one to `Waiting`, or reassign it. For those
board-etiquette steps only, use the OAuth scripts in astrid-web (not the DB):

```bash
# CLAIMING — atomic. Requires Ready and writes Doing in one conditional update.
cd ../astrid-web && npx tsx scripts/claim-fixall-task.ts <taskId> ready --agent claude

# Everything else — still set-task-status.ts, which is correct for these.
cd ../astrid-web && npx tsx scripts/set-task-status.ts <taskId> Waiting
cd ../astrid-web && npx tsx scripts/assign-task.ts <taskId> jonparis@gmail.com
```

**Exit `2` from the claim (`CLAIM_CONFLICT`) is not a failure — move to the next task
silently.** It means a peer session claimed it first, which is the ordinary outcome of two
loops sharing a board. Exit `0` is yours.

**Pass `--agent claude`.** Omitted, the claim assigns to **Copilot** — the GitHub Actions
worker calls the script positionally and that default has to keep meaning what it always did.
A Claude Code loop that omits it hands its own work to another harness.

Reading the queue and then writing `Doing` as two steps is what this replaces: the window
between them is how two sessions came to work AWTD-865 at the same time on 2026-09-09.
`set-task-status.ts` is still exactly right for `Waiting` and for handing a task back — only
the *claim* has to be atomic.

If those fail (OAuth flakiness), say so on the task with `add_comment` and carry on — a
missing status change is a cosmetic gap; a task worked through the DB is not.

### Until the web branch lands, degrade knowingly

The claim's `--agent` support and `scripts/fixall-session.ts` arrived on astrid-web's
`fix/fixall-collision-safety`, **which is not merged to astrid-web `main` as of 2026-09-09**.
Check before concluding either is broken:

- **`fixall-session.ts` missing** → the branch is not merged. Skip the lock, say so in the run
  summary, and make certain by hand that no second session is in this checkout.
- **The claim assigns to Copilot despite `--agent claude`** → the branch is merged but astrid-web
  is not **deployed** (its deploys are manual). Fall back to `set-task-status.ts <taskId> Doing`
  for that task. Do not work a task the board now says belongs to Copilot.

Both halves ship independently and in either order, so neither of these blocks a run.

## The workflow itself is shared

**Read [`../astrid-web/docs/FIXALL_WORKFLOW.md`](../../../astrid-web/docs/FIXALL_WORKFLOW.md)
— it is the canonical description** of the queue, the board etiquette (`Doing` / `Waiting` /
handing back), the per-task loop (strategy comment → branch → RED-GREEN TDD → gates → report),
filing the other repo's half, and re-checking after every task. It is one workflow, not two;
this file holds only what is different about the iOS repo.

### What `get_agent_queue` returns

A task is in the queue only when **all** hold: Ready status, **assigned to `claude`**, on the
given list, and due now (a task with a future `dueDateTime` is listed under `held.scheduled`
with when it comes due). It answers `empty: true` when there is nothing to do.

- **Assignment is required.** Unlike the old `ready-tasks.ts` script, an unassigned Ready task
  is NOT in the queue — it is someone's untriaged note. If something unassigned is genuinely
  yours, say so and let Jon assign it; do not work around the filter.
- **A queue held up by the clock is not an idle one.** If `empty` but `held.scheduled` is
  non-empty, say when the next task comes due rather than just "empty".
- **Re-check after every task with the same call** — never work from the opening snapshot. New
  tasks arrive mid-run and a REOPENED task looks exactly like one never done; a reopened task
  means the previous fix missed, so find a different cause.

## What is different here

- **PUSH WHEN THE RUN IS DONE — do not ask** (Jon, 2026-09-06, superseding the 2026-08-18
  ask-first rule). Emptying the queue ends with `main`, `iosdev` and `macdev` pushed, so a
  TestFlight build is already on its way by the time Jon looks. His reason: *"I want to look at
  work when you are done. I don't want to tell you to push it so I can look at it and then
  wait."* Asking made him wait twice — once for the ask, once for the run.

- **ONE push per run, at the end — never per task.** This is what the old ask-first rule was
  actually protecting, and it still holds: **a push per fix burned through the Xcode Cloud
  allotment.** Every ship pushed three branches and started FOUR runs — `iosdev`, `macdev`,
  plus iOS Release and Mac Release on `main` — so one fix cost four runs, and shipping several
  fixes an hour apart exhausted the month. Once it is gone, every run is created and cancelled
  before it starts (`startedDate: null`, `cancelReason: null`) and `POST /v1/ciBuildRuns`
  returns 500, which looks exactly like an Apple outage and cost hours to diagnose. See
  [[xcode-cloud-runs-canceled]]. (The two Release workflows became manual-only on 2026-08-27,
  so a push now starts two runs rather than four — batching still matters.)

- **A task is DONE when it is merged into `main` with the gates green.** Say in the completion
  report that it is merged, and — once the run's push has happened — that a build is on the
  way. Never say it shipped: an App Store submission is a separate, deliberate act.

- **Gates:** `npm run predeploy`, plus the Mac suite for anything touching `Core/` or Mac:
  ```bash
  xcodebuild test -scheme "Astrid Mac" -destination "platform=macOS" \
    -only-testing:"Astrid MacTests" -quiet
  ```
  Re-run them on the MERGED tree, not just the branch — a merge can break what neither side
  broke alone.

- **No `CURRENT_PROJECT_VERSION` bump per fix.** It does not name the TestFlight build:
  measured 2026-08-18, TestFlight's numbers are the Xcode Cloud RUN numbers (877, 878, 882…)
  while the repo said 254. Tell Jon the build number or the commit, not the bump.

- **An App Store submission, deleting files, or a significant architecture change still needs
  asking.**

## Pushing, at the end of the run

Work lands on `main` (that is where the per-task branches merge), then both dev branches
fast-forward to it. Push all three so they cannot drift — the `Core/` tree is shared — and
expect one build to carry several tasks. That is the trade for not burning the allotment: a
build no longer maps to a single change, so the completion reports have to carry the detail.

```bash
git push origin main                                    # lands the work — builds nothing
git checkout iosdev && git merge --ff-only main && git push origin iosdev
git checkout macdev && git merge --ff-only main && git push origin macdev
git checkout main
```

- Xcode Cloud picks the push up by webhook, which has lagged 0 to ~36 minutes. That is normal —
  do not retrigger on a hunch. A manual `POST /v1/ciBuildRuns` **must** carry
  `relationships.sourceBranchOrTag` (an `scmGitReferences` id) or it defaults to `main` and 409s.
- **If runs are created and cancelled with `startedDate: null`, the allotment is gone.** Say so
  and stop; pushing again only makes more cancelled runs.

**Xcode Cloud is not the only way out.** `npm run release:ios:upload` archives locally and
uploads straight to App Store Connect / TestFlight with the ASC key in `.env.local` — see
`.claude/skills/appstore-release/SKILL.md`. Ask before an `:upload`.

See [ASTRID.md](../../ASTRID.md) for architecture and the full coding workflow, and `/fixstuff`
for the interactive, pick-one-task-at-a-time version.
