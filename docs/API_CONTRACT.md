# Astrid API Contract


> **Versioning note (2026-07):** the iOS app calls path-versioned endpoints under `/api/v1/...` exclusively; there is no version header. Legacy `/api/...` routes remain server-side for old clients only.

This document defines the stable API contract between the Astrid web backend and mobile clients (iOS, Android). Changes to these endpoints follow strict versioning and deprecation policies.

## API Versioning

Versioning is **path-based**: all current endpoints live under `/api/v1/...`. There is no version header. Legacy unversioned `/api/...` routes remain server-side for old clients and must not be removed, but new client code always targets `/api/v1`.


## Authentication Endpoints

### POST `/api/v1/auth/mobile-signup`
Create a new account with passwordless authentication.

**Request:**
```json
{
  "email": "user@example.com",
  "name": "User Name"  // optional
}
```

**Response:**
```json
{
  "success": true,
  "message": "Check your email for sign-in link"
}
```

### POST `/api/v1/auth/apple`
Sign in with Apple.

**Request:**
```json
{
  "identityToken": "string",
  "authorizationCode": "string",
  "user": "string",
  "email": "string",       // optional
  "fullName": "string"     // optional
}
```

### POST `/api/v1/auth/google`
Sign in with Google.

**Request:**
```json
{
  "idToken": "string"
}
```

### GET `/api/v1/auth/mobile-session`
Get current session information.

**Response:**
```json
{
  "user": {
    "id": "string",
    "email": "string",
    "name": "string",
    "image": "string"
  }
}
```

### DELETE `/api/v1/auth/signout`
Sign out the current user.

### POST `/api/v1/auth/mobile-mcp-token`
Get MCP (Model Context Protocol) token for AI integrations.

---

## Task Endpoints

### GET `/api/v1/tasks`
Fetch all tasks accessible to the current user.

**Response:**
```json
{
  "tasks": [
    {
      "id": "string",
      "title": "string",
      "description": "string",
      "completed": false,
      "isPrivate": false,
      "repeating": "never",
      "repeatFrom": "DUE_DATE",
      "occurrenceCount": 0,
      "priority": 0,
      "createdAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z",
      "creatorId": "string",
      "assigneeId": "string",
      "dueDateTime": "2024-01-01T00:00:00Z",
      "isAllDay": true,
      "lists": [{ "id": "string", "name": "string" }],
      "creator": { "id": "string", "name": "string", "email": "string" },
      "assignee": { "id": "string", "name": "string", "email": "string" }
    }
  ]
}
```

### GET `/api/v1/tasks/{id}`
Get a specific task by ID.

### POST `/api/v1/tasks`
Create a new task.

**Request:**
```json
{
  "title": "string",
  "description": "string",
  "priority": 0,
  "repeating": "never",
  "isPrivate": false,
  "dueDateTime": "2024-01-01T00:00:00Z",
  "isAllDay": true,
  "listIds": ["string"],
  "assigneeId": "string"
}
```

### PUT `/api/v1/tasks/{id}`
Update an existing task.

**Request:** Partial task object with fields to update.

### DELETE `/api/v1/tasks/{id}`
Delete a task.

### PUT `/api/v1/tasks/{id}` (completion)
Mark task as complete/incomplete.

**Request:**
```json
{
  "completed": true
}
```

### POST `/api/v1/tasks/{id}/copy`
Copy a single task.

### POST `/api/v1/tasks/copy`
Batch copy multiple tasks.

**Request:**
```json
{
  "taskIds": ["string"]
}
```

---

## List Endpoints

### GET `/api/v1/lists`
Fetch all lists accessible to the current user.

**Response:**
```json
{
  "lists": [
    {
      "id": "string",
      "name": "string",
      "privacy": "PRIVATE",
      "ownerId": "string",
      "color": "string",
      "imageUrl": "string",
      "description": "string",
      "createdAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z"
    }
  ]
}
```

### GET `/api/v1/lists/{id}`
Get a specific list by ID.

### POST `/api/v1/lists`
Create a new list.

**Request:**
```json
{
  "name": "string",
  "description": "string",
  "color": "string",
  "privacy": "PRIVATE"
}
```

### PUT `/api/v1/lists/{id}`
Update an existing list.

### DELETE `/api/v1/lists/{id}`
Delete a list.

### PUT `/api/v1/lists/{id}/invite`
Invite users to a list.

**Request:**
```json
{
  "emails": ["user@example.com"]
}
```

### POST `/api/v1/lists/{id}/leave`
Leave a shared list.

### PUT `/api/v1/lists/{id}/favorite`
Toggle list as favorite.

**Request:**
```json
{
  "favorite": true
}
```

---

## Comment Endpoints

### GET `/api/v1/tasks/{taskId}/comments`
Get comments for a task.

**Response:**
```json
{
  "comments": [
    {
      "id": "string",
      "content": "string",
      "type": "TEXT",
      "taskId": "string",
      "authorId": "string",
      "createdAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z",
      "author": { "id": "string", "name": "string", "email": "string" }
    }
  ]
}
```

### POST `/api/v1/tasks/{taskId}/comments`
Create a comment on a task.

**Request:**
```json
{
  "content": "string",
  "type": "TEXT"
}
```

### PUT `/api/v1/comments/{id}`
Update a comment.

**Request:**
```json
{
  "content": "string"
}
```

### DELETE `/api/v1/comments/{id}`
Delete a comment.

---

## Reminder Endpoints

### GET `/api/v1/reminders/status`
Get pending reminders for the current user.

### PUT `/api/v1/reminders/{id}/dismiss`
Dismiss a reminder.

### PUT `/api/v1/reminders/{id}/snooze`
Snooze a reminder.

**Request:**
```json
{
  "minutes": 15
}
```

---

## User Endpoints

### GET `/api/v1/users/search?q={query}`
Search for users by name or email.

**Query Parameters:**
- `q` (required): Search query (min 2 characters)
- `includeAIAgents` (optional): Include AI agent users
- `taskId` (optional): Filter by task context
- `listIds` (optional): Comma-separated list IDs

**Response:**
```json
{
  "users": [
    {
      "id": "string",
      "name": "string",
      "email": "string",
      "image": "string"
    }
  ]
}
```

### GET `/api/users/{userId}/profile`
Get a user's public profile.

---

## Account Endpoints

### GET `/api/account`
Get current user's account details.

### PUT `/api/account`
Update account settings.

**Request:**
```json
{
  "name": "string",
  "image": "string",
  "defaultDueTime": "09:00"
}
```

### POST `/api/account/verify-email?action={action}`
Manage email verification.

**Actions:** `send`, `resend`, `cancel`

### POST `/api/account/delete`
Delete the user's account.

**Request:**
```json
{
  "confirmationText": "delete my account"
}
```

### GET `/api/account/export?format={format}`
Export account data.

**Formats:** `json`, `csv`

---

## File Upload

### POST `/api/v1/secure-upload/request-upload`
Upload a file (multipart/form-data).

**Request:** Multipart form with `file` field.

**Response:**
```json
{
  "url": "string",
  "filename": "string"
}
```

---

## Real-Time Updates

### GET `/api/v1/sse`
Server-Sent Events endpoint for real-time updates.

**Events:**
- `task:created` - New task created
- `task:updated` - Task modified
- `task:deleted` - Task removed
- `list:created` - New list created
- `list:updated` - List modified
- `list:deleted` - List removed
- `comment:created` - New comment added

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
- All endpoints documented above

### SSE events (current)

Endpoint: `GET /api/v1/sse`. Event names use underscores: `task_created`, `task_updated`, `task_deleted`, `list_*`, `comment_added/created/updated/deleted`, `chat_message_created/updated/deleted`, `agent_typing_start/stop`, `my_tasks_preferences_updated`, `user_settings_updated`, `external_sync_refresh` (external-provider nudge).

### Task fields added since the original contract

`completedAt` (ISO, backdatable on completion), `completedSource` (`astrid|google|github|apple`), `parentTaskId` (subtasks), `clientRequestId` (idempotency echo), `repeatingData` (custom patterns).

### Endpoint groups not covered above (summary)

- **Chat**: `/api/v1/chat/channels`, `/api/v1/chat/channels/{id}/messages` (GET/POST)
- **User prefs**: `/api/v1/users/me/{settings, my-tasks-preferences, smart-tasks, ai-preferences, available-agents}`
- **Uploads**: `/api/v1/secure-upload/request-upload` (<4MB), `/api/v1/secure-upload/get-upload-url` + direct blob (≥4MB)
- **GitHub (coding agent)**: `/api/v1/github/status`, `/api/v1/github/repositories`
- **OAuth**: `/api/v1/oauth/token` (client credentials)
- **Passkeys**: `/api/auth/webauthn/*`
- **External sync proxy**: `/api/v1/integrations` (+ `github|google/authorize`, `callback`), `/api/v1/sync/github/{repos, links, issues, task-links, comments}`, `/api/v1/sync/google/{tasklists, links, tasks, task-links}` — thin authenticated proxies; provider tokens never leave the server.
