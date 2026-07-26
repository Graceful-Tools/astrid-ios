# Security Audit — pre-release, Astrid for Mac (2026-07-25)

Conducted before the first public, directly-downloadable Mac build. Scope: everything an
attacker could reach in a shipped, notarized, sandboxed Mac app — plus the shared `Astrid App`
core it links against, so iOS inherits the same fixes.

**Result: 4 issues found and fixed, 0 open. 11 new regression tests.**
Gates after fixes: iOS 1145 unit tests, Mac 221 unit tests, 30 Mac UI tests — all green.

---

## Findings

### 1. OAuth `state` generated but never validated — MEDIUM (fixed)

`GoogleSignInManager.signIn()` generated a random `state` with the comment "Generate state for
CSRF protection" and sent it in the authorization request. The callback handler
(`exchangeCodeForTokens`) read only `code` and never compared `state`. The protection the
parameter exists for was entirely absent: a crafted redirect could inject an attacker's
authorization code into a victim's sign-in, binding the victim's Astrid session to the
attacker's Google identity.

PKCE (S256, correctly implemented) limited real-world exploitability — a foreign code will not
match our `code_verifier` — but state validation is the control that is supposed to stop this
and must not silently be missing.

**Fix:** `OAuthCallbackValidator` (pure, unit-tested) validates the redirect before the code is
spent: provider errors surface first, state must match, empty expected state never matches.
`GoogleSignInError.stateMismatch` is surfaced with a deliberately generic user-facing message.

### 2. Deep-link ids reached request paths unescaped — MEDIUM (fixed)

Task/list ids arrive from deep links (`astrid://tasks/<id>`, `https://astrid.cc/tasks/<id>`) —
attacker-supplied input, since any web page or message can open one. Those ids were interpolated
straight into `/api/v1/tasks/\(id)`, and Foundation does not normalize or escape the result.

Verified empirically: `astrid://tasks/abc%2F..%2Fadmin` → `URL.lastPathComponent` decodes to
`abc/../admin` → request URL `https://astrid.cc/api/v1/tasks/abc/../admin`, which servers and
CDNs typically normalize to `/api/v1/admin` — issued with the user's session cookie. A malicious
link could therefore drive the authenticated client at arbitrary API endpoints (forced-request /
CSRF-style; the attacker does not see responses).

**Fix — two independent guards, neither load-bearing alone:**
- `APIPathSafety.isValidIdentifier` at every deep-link entry point (`MacDeepLink`, iOS
  `DeepLinkManager` for tasks/lists/users/shortcodes): ids must be `[A-Za-z0-9-_]`, 1–128 chars.
- `APIPathSafety.isSafeRequestPath` as a backstop at both URL-construction sites in
  `AstridAPIClient`: any path containing a `.` or `..` segment (encoded or not) is refused
  before a request leaves the device.

`MacDeepLink` additionally now requires scheme `https` for `astrid.cc` links — `http://astrid.cc/...`
was previously routed as a trusted universal link.

### 3. macOS credentials stored in the legacy keychain — MEDIUM (fixed)

`KeychainService` used `SecItem*` without `kSecUseDataProtectionKeychain`. On iOS that is the
default; **on macOS it means the legacy file-based login keychain, where `kSecAttrAccessible` is
ignored** — so the `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` the code carefully specified had
no effect for the session cookie, MCP token, OAuth client secret, and OAuth access token on Mac.

**Fix:** all keychain operations go through a shared base query that sets
`kSecUseDataProtectionKeychain` on macOS, giving the Mac app per-app, sandbox-isolated storage
that honors accessibility. `get` transparently migrates an item found in the legacy keychain
(re-saves it under data protection, deletes the old copy) so existing Mac users are not signed
out; `delete` clears both keychains, so sign-out cannot leave a stale cookie behind.

### 4. Release tooling wrote the ASC signing key to shared `/tmp` — LOW (fixed)

`scripts/package-mac.sh` (added in this same session) materialized the App Store Connect private
key for `notarytool`. The first block used `mktemp` in `/tmp` with an EXIT trap; the second block
created another copy with **no trap**, so a failure between creation and cleanup left the
notarization key on disk in a world-readable directory.

**Fix:** one `write_asc_key` helper writes to `build/.asc-key.p8` (git-ignored) created under
`umask 077`, with a single trap on `EXIT INT TERM` that cannot alter the script's exit status.

---

## Areas reviewed and found sound

| Area | Finding |
|---|---|
| Entitlements | Minimal and justified: sandbox, network client, user-selected files, calendars, reminders, Sign in with Apple, `webcredentials:astrid.cc`. No JIT, no disabled library validation, no unsigned executable memory. |
| Hardened runtime | Enabled on the Mac target (`ENABLE_HARDENED_RUNTIME = YES`) alongside `ENABLE_APP_SANDBOX = YES`. |
| Transport security | No ATS exceptions in Release (`Info.plist`); the cleartext `localhost` / LAN exceptions live in `Info-Debug.plist`, referenced **only** by the iOS Debug configuration. Release base URL is `https://astrid.cc`. |
| TLS validation | No `URLSessionDelegate` challenge handling anywhere — no certificate-validation bypass, no pinning to misconfigure. |
| Secrets | No hardcoded secrets in shipped Swift. `.env.local` is git-ignored; git history contains no committed key material (filename and content scans). The Google OAuth **client id** in source is public by design; no client secret is present. |
| Logging | Auth logging records counts and status only — no token, cookie, or secret values, not even truncated. |
| Sign-out | Thorough: keychain items, `HTTPCookieStorage` (per-URL and domain-wide), user defaults, Core Data, Outbox journal, sync ledgers, and every image/profile/agent cache. |
| Third-party code | Zero SPM packages and zero npm dependencies — no supply-chain surface. |
| Process/deserialization | No `Process`/`NSTask`/`posix_spawn`/`dlopen`, no `NSKeyedUnarchiver`, no `WKWebView` or JS bridge. |
| UI-test isolation | `-uiTesting` runs are hermetic (in-memory local user, ephemeral Core Data store, temp Outbox journal) — see commit `a307320`. |

## Notes for the release

- The DMG must be notarized and stapled (`npm run package:mac` does both, for the app and the
  disk image). The one manual prerequisite is a **Developer ID Application** certificate, which
  Apple permits only the Account Holder to create.
- Finding 3's migration path is exercised on first launch after update. A Mac user who signed in
  with an older build keeps their session; a failed migration degrades to a normal sign-in prompt.
