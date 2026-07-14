# Astrid for Mac — Passkey login

Passkeys on Mac use the **same Relying Party (`astrid.cc`) as web and iOS**, so the same
credentials work everywhere. The flow is the shared `PasskeyManager` (WebAuthn against
`/api/auth/webauthn/*`) driving native `ASAuthorizationPlatformPublicKeyCredentialProvider`
— identical architecture to iOS, adapted to AppKit (window anchor via `Platform.presentationAnchor()`).

## Done in-repo
- **Sign-in UI** — `MacLoginView` is passkey-first (primary button), with Google/Apple as
  alternatives and a "Create account with Passkey" sign-up. No email/password login. Mirrors
  the iOS `LoginView`, styled with the shared `Theme`.
- **Server vouches for the Mac app** — `astrid-web/public/.well-known/apple-app-site-association`
  now lists the Mac App ID under `webcredentials`:
  `34K3P7PD2W.Graceful-Tools-Inc.Astrid-Mac` (alongside the iOS app).

## Two steps to activate (can't be committed — coupled to signing/deploy)

### 1. Add the Associated Domains capability (Xcode)
Xcode → **Astrid Mac** target → **Signing & Capabilities**:
- Team: **Graceful Tools (34K3P7PD2W)**, automatic signing.
- **+ Capability → Associated Domains** → add:
  - `webcredentials:astrid.cc`
  - `webcredentials:www.astrid.cc`

Xcode writes the `com.apple.developer.associated-domains` entitlement **and** provisions it
(the App ID gets the capability). Doing it here — rather than hand-editing the entitlements
file — keeps the entitlement and the provisioning profile in sync and keeps ad-hoc/CI builds working.

### 2. Deploy the AASA (astrid-web)
The updated `apple-app-site-association` must be **live** at
`https://astrid.cc/.well-known/apple-app-site-association` (served as `application/json`, no
redirect). Deploy astrid-web (deploys are manual). Verify:
```bash
curl -s https://astrid.cc/.well-known/apple-app-site-association | jq .webcredentials
# → apps should include 34K3P7PD2W.Graceful-Tools-Inc.Astrid-Mac
```

Once both are done, **Sign in with Passkey** on Mac authenticates against `astrid.cc` and
resolves the same passkeys registered on web/iOS. (macOS caches AASA; a fresh install or
`swcutil reset` may be needed after first deploy.)
