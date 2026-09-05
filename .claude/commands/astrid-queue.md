Work the Astrid iOS agent queue from the astrid MCP server until it is empty.

Call `get_agent_queue` (astrid MCP) with agent `"claude"` and listId
`"aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36"` (Astrid iOS To-do). Work every task it returns to
completion, commenting progress on each one with `add_comment`. If it answers `empty:true`,
stop and say nothing is queued — but if `held.scheduled` is non-empty, say when the next one
comes due.

Per task: `get_task` + `get_task_comments` → strategy comment → branch → RED-GREEN TDD →
`npm run predeploy` → merge into `iosdev` → completion report → `update_task completed:true`.
Full rules in `/fixall`. Do not push unless Jon asks for a build.
