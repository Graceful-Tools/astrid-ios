# Copilot bootstrap

Keep this file thin. Read [ASTRID.md](../ASTRID.md) first for architecture, API,
release, and TDD rules, then [AGENTS.md](../AGENTS.md) for current operational
workflow. Verify commands and behavior against `package.json`, `scripts/`, and
`.github/workflows/`. If those sources disagree with README, CONTRIBUTING,
`.claude/`, or each other, stop and surface the drift rather than guessing.

## Actions and `/fixall`

- Local workflows target the dedicated `[self-hosted, astrid-ios]` runner.
  `macos-latest` is an explicit manual backup only; there is no automatic
  failover, so jobs queue while the local runner is offline.
- Use the Astrid OAuth client pair only for structured queue retrieval and atomic
  claims. Use `ASTRID_MCP_TOKEN` only for the authenticated coding-agent trigger.
  Authenticated UI tests use a short-lived UI session: mint it from the pinned
  `astrid-web` helper in Actions, mask it, scope it to the UI-test step, and never
  print or persist it.
- Consume the queue's structured output, never human-readable summaries. Dry runs
  must not mutate tasks. A real run must atomically claim each still-eligible task
  before invoking the authenticated trigger; listing or summarizing tasks is not
  execution.

## Validation

- `npm run predeploy:quick`: localization and brand checks plus iOS build.
- `npm run predeploy`: quick coverage plus partner-brand audit and iOS unit tests.
- `npm run predeploy:full`: standard coverage plus authenticated iOS UI tests and
  the Mac test suite.

Prepare and reuse the exact iPhone 17 simulator with
`npm run simulator:prepare`. Serialize simulator-sensitive work on the single
local runner, cancel superseded same-ref runs, and inspect an existing slow run
before starting another.

## Astrid task state

`Ready` is a task state, not a list. Queue eligibility is the intersection of
Astrid iOS To-do board membership, eligible state, assignee, and due-date rules.
After the required completion report, transition finished work to `Done`; neither
removing board membership nor posting a comment completes it. Re-fetch the task
and verify it is no longer queue-eligible.
