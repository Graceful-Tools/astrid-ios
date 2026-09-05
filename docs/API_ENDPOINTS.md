# API endpoints this app calls

Every `/api/v1` path in the iOS/Mac app, grouped by resource.

**Why this file exists.** `AstridAPIClient` is the one HTTP client (ASTRID.md §2a, task
`b1a05e99`), and it spends its paths as inline string literals — so without this list,
"which endpoints does the app use" is a question you answer by reading 1,500 lines. The
`APIEndpoint` enum it replaced gave that readability for free; this file buys it back, and
unlike a Swift enum, `astrid-web` can read it.

**It cannot silently rot.** `APIEndpointInventoryTests` fails when the source and this file
disagree, which is the only reason to trust a generated list at all.

Regenerate: see the test — it prints the expected list on failure.


## Current client — `AstridAPIClient` (47 paths)


### `/api/v1/capabilities`

- `/api/v1/capabilities`

### `/api/v1/chat`

- `/api/v1/chat/channels`
- `/api/v1/chat/channels/{id}/agent-response`
- `/api/v1/chat/channels/{id}/astrid-response`
- `/api/v1/chat/channels/{id}/messages`

### `/api/v1/comments`

- `/api/v1/comments/{id}`

### `/api/v1/contacts`

- `/api/v1/contacts`
- `/api/v1/contacts/recommended`
- `/api/v1/contacts/search`

### `/api/v1/custom-agents`

- `/api/v1/custom-agents/agents`
- `/api/v1/custom-agents/agents/{id}`
- `/api/v1/custom-agents/register`

### `/api/v1/github`

- `/api/v1/github/repositories`
- `/api/v1/github/status`

### `/api/v1/integrations`

- `/api/v1/integrations/copilot/authorize`
- `/api/v1/integrations/copilot/status`

### `/api/v1/lists`

- `/api/v1/lists`
- `/api/v1/lists/{id}`
- `/api/v1/lists/{id}/copy`
- `/api/v1/lists/{id}/invitations`
- `/api/v1/lists/{id}/leave`
- `/api/v1/lists/{id}/members`
- `/api/v1/lists/{id}/members/{id}`

### `/api/v1/projects`

- `/api/v1/projects`
- `/api/v1/projects/from-list`
- `/api/v1/projects/{id}`

### `/api/v1/public`

- `/api/v1/public/lists`

### `/api/v1/shortcodes`

- `/api/v1/shortcodes`
- `/api/v1/shortcodes/{id}`

### `/api/v1/tasks`

- `/api/v1/tasks`
- `/api/v1/tasks/{id}`
- `/api/v1/tasks/{id}/comments`

### `/api/v1/users`

- `/api/v1/users/me`
- `/api/v1/users/me/agent-modes`
- `/api/v1/users/me/ai-credentials`
- `/api/v1/users/me/ai-credentials/test`
- `/api/v1/users/me/ai-preferences`
- `/api/v1/users/me/available-agents`
- `/api/v1/users/me/available-models`
- `/api/v1/users/me/delete`
- `/api/v1/users/me/export`
- `/api/v1/users/me/my-tasks-preferences`
- `/api/v1/users/me/settings`
- `/api/v1/users/me/smart-tasks`
- `/api/v1/users/me/verify-email`
- `/api/v1/users/me/webhook-settings`
- `/api/v1/users/search`

## Legacy client — `APIEndpoint` (27 paths)


Closed to additions. These move to `AstridAPIClient` when task `2023c90f` is worked; the
five services still on this client are `AuthManager`, `AccountService`, `AttachmentService`,
`ProfileCache` and `RemoteResourceService`.

- `/api/v1/auth/apple`
- `/api/v1/auth/google`
- `/api/v1/auth/mobile-mcp-token`
- `/api/v1/auth/mobile-session`
- `/api/v1/auth/mobile-signup`
- `/api/v1/auth/signout`
- `/api/v1/comments/{id}`
- `/api/v1/lists`
- `/api/v1/lists/{id}`
- `/api/v1/lists/{id}/favorite`
- `/api/v1/lists/{id}/invite`
- `/api/v1/lists/{id}/leave`
- `/api/v1/reminders`
- `/api/v1/reminders/{id}/dismiss`
- `/api/v1/reminders/{id}/snooze`
- `/api/v1/tasks`
- `/api/v1/tasks/copy`
- `/api/v1/tasks/{id}`
- `/api/v1/tasks/{id}/comments`
- `/api/v1/tasks/{id}/copy`
- `/api/v1/upload`
- `/api/v1/users/me`
- `/api/v1/users/me/delete`
- `/api/v1/users/me/export`
- `/api/v1/users/me/verify-email`
- `/api/v1/users/me/webhook-settings`
- `/api/v1/users/search`
- `/api/v1/users/{id}/profile`
