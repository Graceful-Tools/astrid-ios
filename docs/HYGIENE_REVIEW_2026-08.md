# Hygiene review — astrid-ios, 2026-08-14

Companion to the web review (astrid-web `docs/architecture/REFACTORING_PROPOSAL.md`
§ "2026-08-13 review"). Task d6d42971.

Every number below is a command you can re-run. Nothing was fixed as part of this
review — each finding is filed as its own task on the Astrid iOS board.

## Scale

| Tree | Files | Lines |
|---|---:|---:|
| `Astrid App/` | 262 | 64,972 |
| `Astrid Mac/` | 123 | 11,764 |
| `Astrid AppTests/` | 153 | 25,917 |
| `Astrid MacTests/` | 123 | 7,494 |
| `Astrid AppUITests/` | 11 | 1,775 |
| **total** | **690** | **114,314** |

```bash
find . -name "*.swift" -not -path "./.git/*" -exec cat {} + | wc -l
```

## What the web review worried about, and whether it applies here

**The dual `/api/*` + `/api/v1/*` surface — does NOT apply.** 146 of 147 API path
literals in Swift are `/api/v1/…`. The single exception is a `hasPrefix("/api/")`
check in `ListImageHelper` that deliberately accepts older stored image URLs.

```bash
grep -rn '"/api/' --include="*.swift" "Astrid App" "Astrid Mac" | grep -vc "/api/v1/"
```

**"No client API layer" — does NOT apply in web's form.** No view calls the API
client directly; the service-layer rule in CLAUDE.md is actually holding.

```bash
grep -rn "AstridAPIClient.shared" --include="*.swift" "Astrid App/Views" "Astrid Mac" | wc -l   # 0
```

The 48 `JSONDecoder()` uses outside `Core/Networking` are also not web's problem
repeated: they decode Outbox payloads, Core Data JSON columns and SSE frames, not
HTTP responses. Worth stating plainly so nobody "fixes" them.

**God files — DOES apply.** Six files over 1,000 lines.

**Caching — under-documented.** See finding 5.

## Findings

### 1. Two networking clients, both live

| | `APIClient` | `AstridAPIClient` |
|---|---:|---:|
| lines | 175 (+ 282 in `APIEndpoint`) | 1,544 |
| how paths are expressed | 37 enum cases | 64 inline string literals |
| files using it | 5 | 23 |

`AccountService` and `RemoteResourceService` name their reference `legacyClient`,
so this is known — but nothing records which of the two a new endpoint belongs in,
and the answer is currently "whichever the neighbouring code used".

### 2. The session cookie is persisted by only one of them — and nothing ever renews it

**Checked against astrid-web on 2026-08-14, and the answer changed the finding.**

The asymmetry is real: `APIClient` re-reads `Set-Cookie` on every response and
writes it back to the Keychain, while `AstridAPIClient` reads the stored cookie in
three places and never writes one.

But it is **moot as stated**, because no v1 route emits `Set-Cookie` at all. There
is nothing to save. What the check turned up instead is worse:

- The web app uses NextAuth with `strategy: "jwt"` and `maxAge: 30 days`
  (`lib/auth-config.ts`). With no explicit `updateAge`, NextAuth's default is 24h,
  so **web** users get a re-issued token roughly daily while active and never see
  an expiry.
- iOS never calls NextAuth's `/api/auth/session`. Its only session endpoint is
  `/api/v1/auth/mobile-session`, which **validates and never renews** — it decodes
  the JWT, and on `exp < now` returns 401.
- `AuthManager` calls that endpoint and, on 401, signs the user out
  (`AuthManager.swift:173`).

So an iOS session expires absolutely, 30 days after sign-in, no matter how
actively the app is used — and the user is signed out. Web users in the same
position stay signed in. The database-session path (Apple/Google sign-in) has the
same shape: the route reads `session.expires` directly and never extends it.

Fixing this spans both repos — the renewal has to come from the server — so it is
filed separately rather than patched on the client.

```bash
grep -n "strategy\|maxAge" ../astrid-web/lib/auth-config.ts
grep -n "Set-Cookie" ../astrid-web/app/api/v1/auth/mobile-session/route.ts   # none
```

### 3. Six files over 1,000 lines

| Lines | File |
|---:|---|
| 1,954 | `Astrid App/Views/Tasks/TaskDetailViewNew.swift` |
| 1,898 | `Astrid App/Views/Tasks/CommentSectionViewEnhanced.swift` |
| 1,641 | `Astrid App/Views/Tasks/TaskListView.swift` |
| 1,560 | `Astrid App/Core/Services/TaskService.swift` |
| 1,544 | `Astrid App/Core/Networking/AstridAPIClient.swift` |
| 1,443 | `Astrid Mac/App/MacRootView.swift` |

The web review's conclusion is worth repeating: what worked there was tiny
extractions, one per change, not a restructure.

### 4. Two large surfaces with no tests

- `GoogleTasksSyncService` — 1,209 lines, zero tests. The existing "Google Tasks"
  tests cover feature flags and the connect callback, not the sync engine. This is
  the code that decides what to create, update and delete against a user's real
  Google account.
- `CommentSectionViewEnhanced` — 1,898 lines, zero test references.

```bash
grep -rl "GoogleTasksSyncService" "Astrid AppTests" "Astrid MacTests" | wc -l   # 0
```

### 5. Cache invalidation is undocumented

`ListService` and `TaskService` each hold an in-memory dictionary plus Core Data,
and `ImageCache` holds memory + disk. There are 15 invalidation calls across the
services and no single description of what invalidates what. Jon's brief asks for
"MVC with caching on clients" without compromising performance, so the caches
should stay — but the invalidation rules are the part that rots silently, and
right now they can only be learned by reading every call site.

## Not findings, deliberately

- The 48 non-networking `JSONDecoder()` uses (see above).
- `Astrid Mac/` duplication of `Astrid App/` UI: the Mac tree is a separate
  platform UI over a shared `Core/`, which is the intended shape, and the shared
  helpers (`ListSubtaskVisibility`, `NewTaskDefaults`, `ListPermissions`,
  `MacDetailPresentation`) show the pattern is being followed.
