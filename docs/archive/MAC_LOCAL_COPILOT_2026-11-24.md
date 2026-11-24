# Mac edition that runs Copilot locally, controlled from iOS and the web

*Investigation, 2026-11-24. Jon: "investigate using the copilot sdk local [CLI] in the Mac app and
allowing the iOS app or web app to control a version of copilot running on the Mac. We can do this
as a separate version of the Mac app." Nothing is built yet; this note records what exists, the
proposed shape and the decisions it needs.*

## Summary

It is feasible. Most of the plumbing already exists:

- **The command channel is Astrid itself.** Polling mode, the agent queue, claim/resume and
  `AGENT-HANDBACK` already describe "an agent that runs on the user's own machine and polls".
- **The output convention exists.** astrid-code / astrid-vscode post key messages (Goal, Turn
  result, Needs you, Stopped) as task comments, so every client sees them.

What is missing:

1. A **non-sandboxed Developer ID edition** of the Mac app. Both current Mac builds are sandboxed,
   and a sandboxed app cannot drive an agent that edits arbitrary repos and runs shell commands.
2. A **Swift client for the Copilot runtime.** There is no Swift SDK.
3. Turning **permission requests into answerable comments**. Here the decision UI just built
   (ADEV-229 to ADEV-243) is the natural fit.

## What the Copilot SDK is now

Sources: github.com/microsoft/copilot-sdk, its docs, and the GitHub changelog.

- **Status and names.**
  - Generally available since 2026-06-02.
  - v2 ("protocol 4") shipped 2026-11-24.
  - It is moving from GitHub to Microsoft: `@github/copilot-sdk` 1.0.x became
    `@microsoft/copilot-sdk` 2.0.x.
  - Breaking changes still happen despite GA, and the SDK and runtime must be upgraded together.
- **Languages.** TypeScript, Python, Go, .NET, Rust and Java. **No Swift.**
- **Architecture.** Every SDK speaks JSON-RPC to a standalone **Copilot runtime**
  (`copilot-runtime`, shipped in the copilot-cli release tarballs). It connects three ways:
  - in-process through a C ABI, the v2 default, with no crash isolation;
  - a spawned child over stdio or TCP;
  - attached to `copilot-runtime --server --port N`. A non-loopback host needs
    `COPILOT_CONNECTION_TOKEN`.
- **Sessions.**
  - Create, send, resume and list.
  - Choose the model (`auto` allowed).
  - Custom tools, MCP servers, and a working directory.
  - Streaming events: `assistant.message_delta`, `tool.execution_*`, `permission.requested`,
    `user_input.requested`, `exit_plan_mode.requested`, `session.idle`.
- **Asynchronous approvals.** A permission request carries a `requestId`. It is answered later
  with `session.permissions.handlePendingPermissionRequest`, so **a phone can answer it**. No
  maximum wait is documented.
- **Auth.**
  - Sign-in: the stored GitHub login, a GitHub OAuth user token, `COPILOT_GITHUB_TOKEN`, or BYOK
    (OpenAI, Anthropic, Foundry).
  - Needs a Copilot subscription unless BYOK; Free works for personal use.
  - Each prompt uses the user's AI credits, so the user pays, not Astrid.
- **Licence.**
  - The SDK is MIT.
  - The runtime is under the GitHub Copilot CLI License, which **allows redistributing unmodified
    copies inside an app that adds material functionality**, with its notices.
  - Developer ID distribution is fine under that licence. The Mac App Store is not realistic: the
    sandbox and an agent that edits arbitrary repos don't mix.
- **GitHub already offers remote control.** `copilot --remote` was GA on 2026-05-18 and is
  controlled from GitHub Mobile, github.com and VS Code. Through the SDK it is only an
  experimental read-only export. So "control Copilot on my Mac from my phone" exists already, but
  outside Astrid, tied to GitHub accounts, terminal sessions and org policy.

## What Astrid already has

- **Agent identities.**
  - `copilot@` is an agent mailbox (astrid-web `lib/brand/agent-emails.ts`).
  - Each mailbox has a mode: api, polling, webhook or off (`lib/ai/agent-execution-mode.ts`,
    `docs/AGENT_POLLING_MODE.md`).
  - In polling mode, "Astrid calls nothing. The task sits in the agent's queue and the user's own
    harness picks it up". astrid-core's agent row says the same.
- **Queue and attention.**
  - `GET /api/v1/agent-queue`, with Ready plus attention (unanswered comments, handback replies,
    and a `resume` context).
  - Claim / resume / release via `POST /api/v1/tasks/:id/claim` (behind `ASTRID_AGENT_CLAIM_API`).
- **Live updates.** The `/api/v1/agent/events` SSE stream with `?since=` replay, and astrid-core's
  realtime stream that the apps already use. Commands therefore arrive within seconds over an
  outbound connection, which works behind NAT.
- **Output convention.** astrid-vscode `src/agents/agentWork.ts` and `keyMessages.ts`. These post
  agent-signed comments with a `clientRequestId` and move the task's lane.
- **Copilot OAuth.** The `CopilotCredential` model and `/api/v1/integrations/copilot/*` already
  hold a per-user GitHub token. On the Apple side, `CopilotCommands.swift` and `AgentHubModel`
  show its status.
- **The decision UI is the approval UI.** A `**Decision:**` comment with "1. Allow once / 2. Allow
  for this session / 3. Deny" draws as tappable cards on iOS, Mac and the web. The tapped reply
  (`1 — Allow once`) is a normal comment the Mac can read back.
- **Variant mechanism.**
  - `Astrid Mac/Config/Direct.xcconfig` is Developer ID, notarised, Sparkle-updated and shipped as
    a DMG (`npm run package:mac`).
  - The Whitelabel configuration (`make-brand-variant.sh`) shows how a separate
    configuration, scheme, bundle id and entitlements set are added.

## Gaps

- **The sandbox.** Both Mac builds set `app-sandbox=true`, including Direct. The edition needs its
  own entitlements without the sandbox, plus the hardened runtime for notarisation. No Swift code
  uses `Process` today.
- **No Swift SDK.** Speak the JSON-RPC protocol from Swift to a bundled, version-pinned
  `copilot-runtime` over stdio. We control both ends, so the protocol only changes when we update
  the bundled runtime. The fallback is a Node sidecar with the TS SDK, which is heavier but is the
  supported path.
- **Device targeting.** Nothing says *which* Mac runs a task. Today a polling mailbox is one queue
  per account.
- **Mailbox mode.** `copilot@` may resolve to `api` when a credential exists. The edition must
  force polling, or get a mailbox of its own.
- **Docs disagree.** astrid-web `docs/COPILOT_SDK_INTEGRATION_PLAN.md` describes the SDK, while
  `lib/ai/providers/copilot-provider.ts` deliberately doesn't use it (the CLI binary exceeds
  Vercel's function size).
- **No token streaming.** No SSE event carries agent output token by token. Key messages are
  enough for a first version.

## Proposed shape

**"Astrid Mac Agent", a third Mac configuration** next to App Store and Direct:

- Developer ID only, not sandboxed;
- its own bundle id and Sparkle feed;
- a compile flag `ASTRID_LOCAL_AGENT`, so the shared code stays one tree.

The ordinary Mac app is unchanged. The work splits into five parts.

1. **Runtime host.**
   - Bundle `copilot-runtime`, pinned to a version, signed with our team, with its licence text.
   - Spawn it over stdio. A Swift `CopilotRuntimeClient` (JSON-RPC 2.0) handles create, resume,
     send, events, permissions and abort.
   - Auth: the runtime's own GitHub login first. Handing over the server's `CopilotCredential`
     token is a later convenience.
2. **Folder mapping.**
   - Each Astrid list (or task) points at a local repo folder, as astrid-code does. The folder is
     chosen once in the edition's settings.
   - The session's working directory is that folder.
3. **Runner loop.**
   - Subscribe to the agent events stream for this account's local-agent mailbox, polling the
     queue as a fallback.
   - Claim a Ready task, start or resume a session, and post key messages.
   - The task stays in Doing while the session runs, then goes to Review or Done according to the
     list's rules.
4. **Remote approvals and questions.**
   - On `permission.requested`, `user_input.requested` or `exit_plan_mode.requested`, post a
     `**Decision:**` comment with the options, ending in `AGENT-HANDBACK: <mailbox>`.
   - The reply wakes the runner through the existing resume path. The Mac maps `n — …` to the
     pending `requestId` and answers it.
   - Free-text replies become the next prompt.
   - The iPhone, the web and the Mac all already draw and answer these.
5. **iOS and web.**
   - No new screens for a first version: you assign a task to the local agent and talk to it in
     comments.
   - Later:
     - a "Run on my Mac" picker, which needs device presence on the server;
     - a Stop button that posts a control comment;
     - an optional live activity line from `agent_typing_*` events.

## Phases

| Phase | Outcome | Where |
|---|---|---|
| 0. Spike | A Swift command-line spike starts the bundled runtime, opens a session in a folder, streams one answer, and answers a permission request after a delay | astrid-ios, throwaway |
| 1. Edition | Configuration, scheme, xcconfig, entitlements, signing and DMG for "Astrid Mac Agent"; the runtime is bundled and its licence shown | astrid-ios |
| 2. Runner | Mailbox, folder mapping, claim, session, and key-message comments | astrid-ios, plus astrid-web for the mailbox and mode |
| 3. Approvals | Permission and question requests become Decision comments; replies resume the session | astrid-ios, plus a DECISIONS.md note |
| 4. Targeting | Device presence, "Run on my Mac", Stop | astrid-web, astrid-core, iOS and web |

## Decisions for Jon

1. **Build our own, or use GitHub's remote control?** GitHub Mobile already controls `copilot
   --remote` sessions. Ours keeps the work, approvals and history on the Astrid task, works for
   BYOK, and fits the board. Recommended: build ours, starting with the Phase 0 spike.
2. **Mailbox: reuse `copilot@` forced to polling, or a new `copilot-local@`?** A new mailbox keeps
   the cloud and local Copilot apart on the same account. Recommended: new mailbox.
3. **How to talk to the runtime: Swift JSON-RPC or a Node sidecar?** Recommended: Swift JSON-RPC
   to the bundled runtime, keeping the sidecar as a fallback if the protocol proves too unstable.
4. **Edition scope:** Developer ID only, non-sandboxed, no App Store. This is required, not a
   preference.
