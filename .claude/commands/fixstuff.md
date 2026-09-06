Pull tasks from the Astrid iOS to-do list and work through them until the list is empty.

Everything here goes through the `astrid` MCP server — **never the database**. The DB is for
deep repair only (Jon, 2026-08-29). The tool table, the auth fallback, and the two steps the
MCP cannot do (status / assign) are in `/fixall`; the rules below are the interactive version.

## Steps

1. **Pull the queue** with the MCP tool:
   `get_agent_queue { agent: "claude", listId: "aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36" }`
   (Astrid iOS To-do). Load the tools first if they are deferred; if only
   `mcp__astrid__authenticate` is available, run it, hand Jon the URL, and wait.

   The queue is Ready ∩ assigned-to-`claude` ∩ due-now. **An assignee is a claim** — a task
   assigned to a person, or to nobody, is not in the queue. If you think something is yours,
   ask Jon to assign it rather than working around the filter. If the queue is empty but
   `held.scheduled` lists tasks, say when the next one comes due.

   To see the whole board (not just the queue) — e.g. when Jon asks "what's on the list" —
   use `get_tasks { listId: "aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36" }`.

2. **Present the tasks** to the user and ask which one(s) to work on.

3. **For each task**, follow the coding workflow:
   - `get_task` + `get_task_comments` — read the description AND its comments/attachments. A
     screenshot attached to the task is usually the fastest route to the real cause.
   - Move it to `Doing` (`set-task-status.ts`, OAuth — see `/fixall`) and post a strategy
     comment with `add_comment`.
   - RED regression test naming the task id → implement → green
   - Run `npm run predeploy` (plus the Mac suites for Mac tasks)
   - Fix any regressions
   - Post a completion report with `add_comment`, then `update_task { completed: true }`

4. **RE-CHECK THE QUEUE AFTER EVERY TASK — never work from the opening snapshot.** Call
   `get_agent_queue` again with the same arguments. New tasks arrive while work is in progress,
   and a REOPENED task looks exactly like one that was never done. A reopened task means the
   previous fix missed — re-read it and find a different cause rather than re-closing it on
   the same reasoning.

5. **When the queue is empty, push — do not ask** (Jon, 2026-09-06). Push `main`, then
   fast-forward `iosdev` and `macdev` to it and push both; that is two Xcode Cloud runs and a
   TestFlight build of each app, ready for Jon to look at. Say what went out and that a build
   is on the way. Pushing `main` itself starts nothing — the two Release workflows have been
   manual-only since 2026-08-27 — so an **App Store submission** is still a separate act that
   waits for an explicit go-ahead, and so is a local `:upload`.

   Push once, at the end, carrying the whole run. A push per task is what exhausted the Xcode
   Cloud allotment on 2026-08-18; see `/fixall` for what that looked like.
