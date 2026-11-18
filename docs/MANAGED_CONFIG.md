# Managed app configuration: pointing the app at your server

For IT admins who deploy the Astrid iOS or Mac app with device management (MDM) and run their
own Astrid server. The app reads Apple's **Managed App Configuration**
(`com.apple.configuration.managed`), so any MDM that can push an app configuration dictionary
works (Jamf, Intune, Kandji, Apple Business Essentials and others).

## Keys

| Key | Type | What it does |
|---|---|---|
| `serverURL` | String | The server the app uses, for example `https://tasks.example.com`. Only `https`. A bare host gets `https://`; a path is ignored. An address that doesn't parse is ignored, and the app keeps its current server. |
| `serverLocked` | Boolean | `true` hides "Use a different server" on the sign-in screen and the way back to Astrid's server in Settings, so nobody on the device can change the server. |

Example (an Intune or Jamf app configuration plist):

```xml
<dict>
  <key>serverURL</key>
  <string>https://tasks.example.com</string>
  <key>serverLocked</key>
  <true/>
</dict>
```

## What happens

- **Precedence:** the managed `serverURL`, then the server the person chose on the sign-in screen,
  then Astrid's own.
- **A change is a clean break.** When the configured server changes, while the app runs or
  before its next launch, the app signs out and removes this device's copy of the previous
  server's data before it talks to the new one. A session is never sent to a server it doesn't
  belong to.
- **Sign-in happens on your server's own page** (your SSO, Google with your own client, passkeys
  on your domain). The app's built-in passkey, Google and Apple buttons are bound to Astrid's
  domain and aren't shown.
- **Server version:** your server must be new enough for the app (`meta.apiLevel` in
  `GET /api/v1/capabilities`). Below that, the sign-in screen says the server needs an update.
  Policy: astrid-web `docs/deployment/WHITE_LABEL_COMPATIBILITY.md`.
- **Links:** links to your server open in the app when they're tapped inside it. Universal Links
  (tapping a link in Mail or Safari) only work for Astrid's own domain in the stock app. For your
  own domain, build a branded app instead (`docs/BRAND_VARIANT.md`).

Code: `ManagedServerConfig`, `ServerSelectionStore` and `SessionServerGuard` in
`Astrid App/Core/Networking/ServerSelection.swift`; `ServerSwitcher.reconcile()` in
`ServerSwitcher.swift`.
