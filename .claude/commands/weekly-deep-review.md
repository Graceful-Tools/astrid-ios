Run the weekly deep review over both Astrid repos. This repo drives it.

The review itself is shared and canonical:
**`../astrid-web/scripts/weekly-deep-review.prompt.md`** — read that file from disk and
execute it. This file holds only what is different about running it from here.

## Why the driver lives here

The `astrid` MCP server is configured for this project and not for astrid-web, so an agent
working from this repo is the only one that can read and write **both** boards over MCP —
and it can still `cd ../astrid-web` for the OAuth scripts. The paired guard task on the web
board is not a second review; it only checks that this one ran.

## What is different here

- **Never `git push`.** A push starts four Xcode Cloud runs and has exhausted the monthly
  compute allotment before. A review never pushes.
- **Never run `xcodebuild`, `npm test`, `npm run test:mac`, `npm run predeploy`, or
  `monkey:*`.** Static analysis only — a review has no budget for a simulator run, and
  `predeploy` files its own Astrid tasks.
- **The week's diff baseline is `origin/iosdev`, not `origin/main`** — that is the branch iOS
  ships from.
- **`ASTRID.md` supplies two lenses.** §0's nine rules are the architecture checklist; §8's
  six rows are the cross-platform contract-drift checklist. The Step 2 grep counts in the
  prompt are the mechanical form of §0 rules 1, 2, 6 and 9.
- **Filing goes through the OAuth scripts, not MCP `create_task`.** MCP's schema exposes
  `listId` (singular) while the API wants `listIds` (array), and the mismatch is silent — the
  task is created, returns an id, and is attached to no list at all. Verified 2026-09-06.
  Use MCP freely for *reads* (`get_tasks`, `get_task`, `get_task_comments`) and for
  `add_comment` / `update_task`; just not for creating.

  ```bash
  cd ../astrid-web && npx tsx scripts/file-ios-task.ts "[deep-review] <title>" "<desc>" -p 2   # iOS board
  cd ../astrid-web && npx tsx scripts/create-task.ts   "[deep-review] <title>" "<desc>" -p 2   # web board
  ```

Operational detail — trigger, driver/guard coordination, verification — is in
`../astrid-web/docs/WEEKLY_DEEP_REVIEW.md`.
