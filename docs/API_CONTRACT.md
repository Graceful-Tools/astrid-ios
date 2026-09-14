# Astrid API Contract

## Effective feature configuration

`GET /api/v1/features` is an additive, authenticated endpoint shared by web
and iOS. It returns only the caller's effective feature values and a global
configuration version; rollout rules and targeted user identities are never
exposed. Unknown or absent features default to disabled.

The endpoint is never called during the first-ever client launch. Later
launches render cached/default values first and refresh after initial render,
with invalidation delivered over the existing `feature_flags_updated` SSE
event. Existing API endpoints and wire shapes remain unchanged.


This document defines the stable API contract between the Astrid web backend and mobile clients (iOS, Android). Changes to these endpoints follow strict versioning and deprecation policies.

## API Versioning

Versioning is **path-based**: all current endpoints live under `/api/v1/...`. There is no version header. Legacy unversioned `/api/...` routes remain server-side for old clients and must not be removed, but new client code always targets `/api/v1`.


## Endpoints

The paths the app calls are listed in [API_ENDPOINTS.md](./API_ENDPOINTS.md), generated from
the source and held in step by `APIEndpointInventoryTests`. This file does not repeat them; it
holds what that inventory cannot express: wire shapes, SSE events, errors, and versioning
policy.

---

## Real-Time Updates

### GET `/api/v1/sse`
Server-Sent Events endpoint for real-time updates.

**Events:**
- `task_created` - New task created
- `task_updated` - Task modified
- `task_deleted` - Task removed
- `list_created` - New list created
- `list_updated` - List modified
- `list_deleted` - List removed
- `comment_created` - New comment added

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
| assigneeId | string | no | |
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

### Endpoint groups (summary)

- **Chat**: `/api/v1/chat/channels`, `/api/v1/chat/channels/{id}/messages` (GET/POST)
- **User prefs**: `/api/v1/users/me/{settings, my-tasks-preferences, smart-tasks, ai-preferences, available-agents}`
- **Uploads**: `/api/v1/secure-upload/request-upload` (<4MB), `/api/v1/secure-upload/get-upload-url` + direct blob (≥4MB)
- **GitHub (coding agent)**: `/api/v1/github/status`, `/api/v1/github/repositories`
- **OAuth**: `/api/v1/oauth/token` (client credentials)
- **Passkeys**: `/api/auth/webauthn/*`
- **External sync proxy**: `/api/v1/integrations` (+ `github|google/authorize`, `callback`), `/api/v1/sync/github/{repos, links, issues, task-links, comments}`, `/api/v1/sync/google/{tasklists, links, tasks, task-links}` — thin authenticated proxies; provider tokens never leave the server.
