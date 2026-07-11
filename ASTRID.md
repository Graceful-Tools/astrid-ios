# Astrid iOS — Shared Agent Context

*Cross-agent context for the Astrid iOS app.*

**This file is read by ALL AI agents** (Claude Code, Codex, and others) working in this repo. Agent-specific operational detail lives in [CLAUDE.md](./CLAUDE.md) and [AGENTS.md](./AGENTS.md); project architecture and cross-platform contracts are documented in [CLAUDE.md](./CLAUDE.md) (Canonical Control Points, Repeating Tasks, Unified Outbox) and the web repo's [ASTRID.md](../astrid-web/ASTRID.md).

---

## Agent Working Agreements

Distilled from recurring friction across sessions. These apply to **every** AI agent working in this repo.

### Testing / Workflow
- **Always use TDD:** write a RED test first, then implement to green. All tests must pass before considering a task complete. Run `npm run predeploy` (localizations + build + unit tests) — or, for a quick local check, `xcodebuild build-for-testing` — before declaring a task done. Prefer the minimal, behavior-preserving change over a broad "clean" rewrite (over-eager rewrites have broken existing tests).

### Task Management / Tooling
- When filing/updating Astrid tasks (via the `astrid-web` scripts), use the correct **`listIds`** array field (not `listId`), and double-check **list ID vs task ID** before closing a task. The wrong field orphans tasks and causes `400`s on comment posts. The iOS To-do list id is `aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36`.

### Communication Style
- Keep responses concise; avoid exceeding output token limits during long builds or multi-file work (overlong turns have truncated sessions). Lead with the outcome, then supporting detail.

---

*This file is for all AI agents. For Claude-specific context see CLAUDE.md; for Codex see AGENTS.md.*
