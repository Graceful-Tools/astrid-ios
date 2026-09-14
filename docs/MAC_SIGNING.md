# Astrid for Mac — Signing, Sign in with Apple, and Passkeys

The Mac app offers **Passkey (primary), Google, Apple, and "Continue without an account"**
(offline/local mode), over the shared `AuthManager` and `PasskeyManager`. Passkeys use the
same Relying Party (`astrid.cc`) as web and iOS, so one credential works everywhere; the Mac
flow drives `ASAuthorizationPlatformPublicKeyCredentialProvider` with the window anchor from
`Platform.presentationAnchor()`. The sign-in UI is `MacLoginView` in
`Astrid Mac/App/MacAuthGateView.swift`.

## What works in an ad-hoc / unsigned dev build (no setup)

- **Continue without an account** — `ConnectionModeManager.createLocalUser()`.
- **Google** — `ASWebAuthenticationSession` (needs `network.client`, which the sandbox has).
- **App icon** — bundled (generated for macOS from the 1024 iOS icon).

## What needs a signed build with capabilities

**Sign in with Apple** (`ASAuthorizationError 1000`) and **Passkey** (hangs) need developer
entitlements that cannot be ad-hoc-signed. They are added through Xcode, which couples the
entitlement to provisioning, not hand-edited into the entitlements file.

### One-time Xcode setup

Xcode → **Astrid Mac** target → **Signing & Capabilities**:

1. **Team:** Graceful Tools (**34K3P7PD2W**), **Automatic** signing.
2. **+ Capability → Sign in with Apple**.
3. **+ Capability → Associated Domains** → add `webcredentials:astrid.cc` and
   `webcredentials:www.astrid.cc`.

Then **⌘R**. Xcode signs with the Graceful Tools dev cert and provisions both capabilities.

### Server side (astrid-web)

`https://astrid.cc/.well-known/apple-app-site-association` must list the Mac App ID
`34K3P7PD2W.Graceful-Tools-Inc.Astrid-Mac` under `webcredentials` (served as
`application/json`, no redirect). It is committed in `astrid-web/public/`; astrid-web deploys
are manual, so verify it is live:

```bash
curl -s https://astrid.cc/.well-known/apple-app-site-association | jq .webcredentials
# → apps should include 34K3P7PD2W.Graceful-Tools-Inc.Astrid-Mac
```

macOS caches the AASA; a fresh install or `swcutil reset` may be needed after first deploy.

## Why the entitlements are not committed

`com.apple.developer.applesignin` and `com.apple.developer.associated-domains` require signing
with a development certificate. Committing them into `Astrid Mac.entitlements` makes ad-hoc
and CI builds fail ("entitlements require signing with a development certificate"). Adding
them via Signing & Capabilities keeps the entitlement and the provisioning profile in sync
and leaves ad-hoc/CI builds working.

Sign in with Apple is also absent from the direct-download (Developer ID) build: Apple does
not issue that entitlement in Developer ID profiles, so the DMG hides the button rather than
showing one that fails (`MacSignInOptions`). See `MAC_DISTRIBUTION.md`.
