# Astrid for Mac — Login & Signing

The Mac app offers **Passkey (primary), Google, Apple, and "Continue without an account"
(offline/local mode)** — mirroring iOS, over the shared `AuthManager`.

## What works in an ad-hoc / unsigned dev build (no setup)
- **Continue without an account** (offline/local mode) — `ConnectionModeManager.createLocalUser()`.
- **Google** — `ASWebAuthenticationSession` (needs `network.client`, which the sandbox has).
  *(Known bug: OAuth authorizes but the app may not finish the session — tracked; needs runtime logs.)*
- **App icon** — bundled (generated for macOS from the 1024 iOS icon).

## What needs a signed build with capabilities
**Apple Sign-in** (`ASAuthorizationError 1000`) and **Passkey** (hangs) require developer
entitlements that **cannot be ad-hoc-signed** — so they're added via Xcode (which couples the
entitlement to provisioning), not hand-edited into the entitlements file.

### One-time Xcode setup
Xcode → **Astrid Mac** target → **Signing & Capabilities**:
1. **Team:** Graceful Tools (**34K3P7PD2W**) — log in if needed so the cert is available.
2. **Automatic** signing.
3. **+ Capability → Sign in with Apple**.
4. **+ Capability → Associated Domains** → add `webcredentials:astrid.cc` and `webcredentials:www.astrid.cc`.

Then **⌘R** — Xcode signs with the Graceful Tools dev cert and provisions the capabilities;
Apple Sign-in and Passkey work.

### Also required for Passkey (server side)
The `astrid.cc` **apple-app-site-association** must list the Mac App ID under `webcredentials`
(`34K3P7PD2W.Graceful-Tools-Inc.Astrid-Mac`) — **done in `astrid-web`**, but that repo must be
**deployed** for it to be live. Verify:
```bash
curl -s https://astrid.cc/.well-known/apple-app-site-association | jq .webcredentials
```

## Why not commit the entitlements?
`com.apple.developer.applesignin` and `com.apple.developer.associated-domains` require signing
with a development certificate. Committing them into `Astrid Mac.entitlements` makes **ad-hoc and
CI builds fail** ("entitlements require signing with a development certificate"). Adding them via
Xcode's Signing & Capabilities keeps the entitlement and the provisioning profile in sync and
leaves ad-hoc/CI builds working.
