# Astrid API Contract

This document defines the stable API contract between the Astrid web backend and its native clients (iOS/Mac and Windows, both through astrid-core). Changes to these endpoints follow strict versioning and deprecation policies.

## API Versioning

Versioning is **path-based**: all current endpoints live under `/api/v1/...`. There is no version header. Legacy unversioned `/api/...` routes remain server-side for old clients and must not be removed, but new client code always targets `/api/v1`.


## Effective feature configuration

`GET /api/v1/features` is an additive, authenticated endpoint shared by web
and iOS. It returns only the caller's effective feature values and a global
configuration version; rollout rules and targeted user identities are never
exposed. Unknown or absent features default to disabled.

The endpoint is never called during the first-ever client launch. Later
launches render cached/default values first and refresh after initial render,
with invalidation delivered over the existing `feature_flags_updated` SSE
event. Existing API endpoints and wire shapes remain unchanged.

## Endpoints

The paths the app calls are listed in [API_ENDPOINTS.md](./API_ENDPOINTS.md), generated from
the source and held in step by `APIEndpointInventoryTests`. This file does not repeat them; it
holds what that inventory cannot express: wire shapes, SSE events, errors, and versioning
policy.

---

## Deletion: a capped cursor, then tombstones

Sync is astrid-core's (`crates/astrid-core/src/sync/mod.rs`). A pass sends `updatedSince` and
applies the server's `deletedIds`, but once its stamp is older than 24 hours
(`sync::max_delta_age`, matching web's own cursor cap) it pulls everything instead and learns a
deletion by the row's absence.

The cap is the contract. The server attaches `deletedIds` only to a request that carries a valid
`updatedSince`, and web expires deletion tombstones after 30 days (`DELETION_LOG_RETENTION_DAYS`,
AWTD-993). A cursor older than that would yield a delta that no longer mentions the deletion, and
the local copy would stay visible forever with nothing raising anything. An Apple app can sit
unlaunched for months, so the full-pull fallback is not optional. The cap and its tests live in
astrid-core (`sync::max_delta_age`); the Swift side sends no cursor of its own. See AITD-427.

---

## Real-Time Updates

### GET `/api/v1/sse`
Server-Sent Events endpoint for real-time updates.

Event names: see §SSE events (current) below.

---

## Data Types

### Task Fields (V1)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | string | yes | UUID |
| title | string | yes | |
| description | string | yes | Can be empty |
| completed | boolean | yes | |
| isPrivate | boolean | yes | |
| repeating | enum | yes | `never`, `daily`, `weekly`, `monthly`, `yearly`, `custom` |
| repeatFrom | enum | yes | `DUE_DATE`, `COMPLETION_DATE` |
| occurrenceCount | number | yes | |
| priority | enum | yes | 0, 1, 2, 3 |
| createdAt | date | yes | ISO 8601 |
| updatedAt | date | yes | ISO 8601 |
| creatorId | string | yes | |
| assigneeId | string | no | Always `assigneeIds[0]` when the array is sent |
| previousOccurrenceId | string | no | The occurrence this task followed, where `list.supports.repeatMode` is `spawn`: completing a repeating task there sends a plain completion and the server makes the next occurrence as a new task. Absent elsewhere |
| syncState | string | no | `pending` while a task made on a GitHub Projects board is still being written to GitHub, `error` if that gave up (not sent yet). Null or absent is settled. Read through `TaskSyncState.mark(for:)`, which draws the row's chip |
| assigneeIds | string[] | no | Everyone assigned, primary first. More than one only where `list.supports.multipleAssignees`; absent from an older server. Read through `AssigneeResolver.assigneeIds(of:)` |
| dueDateTime | date | no | ISO 8601 |
| isAllDay | boolean | no | |
| lists | array | no | List references |

### TaskList Fields (V1)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | string | yes | UUID |
| name | string | yes | |
| privacy | enum | yes | `PRIVATE`, `SHARED`, `PUBLIC` |
| ownerId | string | yes | |
| createdAt | date | yes | ISO 8601 |
| updatedAt | date | yes | ISO 8601 |
| color | string | no | Hex color code |
| imageUrl | string | no | |
| description | string | no | |

### User Fields (V1)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | string | yes | UUID |
| email | string | yes | |
| name | string | no | |
| image | string | no | Avatar URL |

### Comment Fields (V1)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | string | yes | UUID |
| content | string | yes | |
| type | enum | yes | `TEXT`, `MARKDOWN`, `ATTACHMENT` |
| taskId | string | yes | |
| authorId | string | no | |
| createdAt | date | yes | ISO 8601 |
| updatedAt | date | yes | ISO 8601 |

---

## Error Responses

All errors follow this format:

```json
{
  "error": "Error message description"
}
```

### HTTP Status Codes

| Code | Meaning |
|------|---------|
| 400 | Bad Request - Invalid input |
| 401 | Unauthorized - Not authenticated |
| 403 | Forbidden - Insufficient permissions |
| 404 | Not Found - Resource doesn't exist |
| 409 | Conflict - Resource already exists |
| 429 | Too Many Requests - Rate limited |
| 500 | Internal Server Error |

---

## Rate Limiting

- Standard endpoints: 100 requests/minute
- Search endpoints: 30 requests/minute
- File upload: 10 requests/minute

Rate limit headers:
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1640000000
```

---

## Changelog

### v1 (Current)
- Initial stable API release

### SSE events (current)

Endpoint: `GET /api/v1/sse`. Event names use underscores: `task_created`, `task_updated`, `task_deleted`, `list_*`, `comment_added/created/updated/deleted`, `chat_message_created/updated/deleted`, `agent_typing_start/stop`, `my_tasks_preferences_updated`, `user_settings_updated`, `external_sync_refresh` (external-provider nudge).

### Task fields added since the original contract

`completedAt` (ISO, backdatable on completion), `completedSource` (`astrid|google|github|apple`), `parentTaskId` (subtasks), `clientRequestId` (idempotency echo), `repeatingData` (custom patterns).

### `GET /api/v1/tasks?omit=` — not sent, and why (AITD-498)

The server can leave `description` and `listMembers` out of this read (`?omit=description`
is 80% of a 1,000-task page). **Neither app sends `omit=description`**, because no read here is
a list view:

- the sync (astrid-core `fetch_all_tasks`) fills the replica the detail view renders offline;
- public / featured list browsing (`TaskService.fetchTasksForListFromServer`) hands the fetched
  rows straight to the detail view — those tasks are not in the store.

A read that only ever shows titles may take it, provided its detail path reads
`GET /api/v1/tasks/{id}` or the task event, both full shape.

**An omitted field is absent from the task object — not `null`, not `""` — and must be applied as
unchanged.** `meta.omitted` names what the server dropped (absent on a full response; an
unrecognised `omit` name is ignored, not rejected, so the echo is the only proof). The Swift
read refuses a page whose `meta.omitted` names a field it did not ask to drop
(`TasksResponse.requireOnlyOmitted`): `Task.description` is non-optional, so such a page
would otherwise decode to an empty list. Full parameter documentation is in astrid-web
`docs/API_CONTRACT.md`.

### Endpoint groups (summary)

- **Chat**: `/api/v1/chat/channels`, `/api/v1/chat/channels/{id}/messages` (GET/POST)
- **User prefs**: `/api/v1/users/me/{settings, my-tasks-preferences, smart-tasks, ai-preferences, available-agents}`
- **Uploads**: `/api/v1/secure-upload/request-upload` (<4MB), `/api/v1/secure-upload/get-upload-url` + direct blob (≥4MB)
  - `get-upload-url` answers with either or both of two shapes (AITD-558). **Presigned** —
    `presigned: { uploadUrl, headers }`, the whole PUT composed server-side with `@vercel/blob`'s
    `presignUrl`; the client sends it as given with no `Authorization`. **Legacy** —
    `uploadToken` + `uploadUrl`, PUT with `Authorization: Bearer <uploadToken>`; derived from
    `BLOB_READ_WRITE_TOKEN`, so it is removed only once builds that read nothing else have drained.
    When both are present the client takes `presigned`; with neither, the upload fails before Blob.
    `secure-files/{id}/upload-url` already returns `{ uploadUrl, headers }`, so it can switch to a
    presigned request with no client change.
- **GitHub (coding agent)**: `/api/v1/github/status`, `/api/v1/github/repositories`
- **OAuth**: `/api/v1/oauth/token` (client credentials)
- **Passkeys**: `/api/auth/webauthn/*` — the one unversioned path, on purpose (no v1 route)
- **External sync proxy**: `/api/v1/integrations` (+ `github|google/authorize`, `callback`), `/api/v1/sync/github/{repos, links, issues, task-links, comments}`, `/api/v1/sync/google/{tasklists, links, tasks, task-links}` — thin authenticated proxies; provider tokens never leave the server.
