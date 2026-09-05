Check the Astrid iOS to-do list and autonomously work every open task to completion. Designed to be safe to re-run on a schedule.

## Goal

**Drive the iOS queue to empty.** Unlike `/fixstuff`, this does not ask which task to work on —
it takes them in the order the queue returns them and keeps going until nothing is left. It
stops on its own when the queue is clear, so a scheduled re-run that finds an empty queue is a
no-op, not busywork.

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

**What the MCP cannot do yet:** move a task to `Doing` / `Waiting`, or reassign it. For those
two board-etiquette steps only, use the OAuth scripts (not the DB):
```bash
cd ../astrid-web && npx tsx scripts/set-task-status.ts <taskId> Doing      # or Waiting
cd ../astrid-web && npx tsx scripts/assign-task.ts <taskId> jonparis@gmail.com
```
If those fail (OAuth flakiness), say so on the task with `add_comment` and carry on — a
missing status change is a cosmetic gap; a task worked through the DB is not.

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

- **DO NOT PUSH unless Jon asks for a build** (Jon, 2026-08-18). Work locally: branch, commit,
  merge into `iosdev`, keep the gates green — and stop there. Push `iosdev`, `macdev` or `main`
  only when he asks to build or test.

  The reason is concrete rather than cautious: **it burned through the Xcode Cloud usage
  allotment.** Every ship pushed three branches and started FOUR runs — `iosdev`, `macdev`,
  plus iOS Release and Mac Release on `main` — so one fix cost four runs, and shipping several
  fixes an hour apart exhausted the month. Once it is gone, every run is created and cancelled
  before it starts (`startedDate: null`, `cancelReason: null`) and `POST /v1/ciBuildRuns`
  returns 500, which looks exactly like an Apple outage and cost hours to diagnose. See
  [[xcode-cloud-runs-canceled]].

- **A task is DONE when it is merged into `iosdev` with the gates green.** Say in the
  completion report that it is merged and waiting to be built, rather than claiming it shipped.

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

## When Jon asks for a build

Push all three so they cannot drift — the `Core/` tree is shared — and expect one build to
carry several tasks. That is the trade for not burning the allotment: a build no longer maps to
a single change, so the completion reports have to carry the detail instead.

```bash
git push origin iosdev
git checkout macdev && git merge --ff-only iosdev && git push origin macdev
git checkout main   && git merge --no-ff iosdev -m "Merge iosdev: <what>"
git push origin main && git checkout iosdev
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
