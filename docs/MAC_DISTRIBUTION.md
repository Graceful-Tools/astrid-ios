# Astrid for Mac — Distribution (M3)

Two channels from one `Astrid Mac` target (see `docs/MAC_APP_SPEC.md` §8).

## Done (in-repo, verified)
- **App Sandbox entitlements** — `Astrid Mac/Astrid Mac.entitlements`: `app-sandbox`,
  `network.client` (OAuth/SSE), `files.user-selected.read-write` (attachments), `calendars`
  (EventKit). Sandboxed build launches + the global hotkey registers with no violation.
- **macOS CI lane** — `ci_scripts/ci_post_xcodebuild.sh` now also builds + unit-tests the
  `Astrid Mac` scheme on Xcode Cloud (blocks the build only on a genuine test failure).
- **Variant xcconfigs** — `Astrid Mac/Config/AppStore.xcconfig` (sandboxed store build) and
  `Direct.xcconfig` (Developer ID + Sparkle).
- **Sparkle wrapper** — `Astrid Mac/Support/UpdaterController.swift`, gated on
  `canImport(Sparkle)`: compiles/ships today as a no-op; lights up when the package is added.
  "Check for Updates…" appears in the app menu only when Sparkle is present.

## App Store channel — ready
The sandboxed build submits like iOS (same team/pipeline). No extra infra needed.

## Direct channel — remaining external, one-time setup (needs accounts/credentials)
These cannot be done from the repo; they require your Apple/Sparkle accounts:
1. **Developer ID Application** certificate + **notarization** credentials (`notarytool`).
2. **Sparkle**: add the SPM package to a duplicated `Astrid Mac (Direct)` scheme; run
   `generate_keys` to make an **EdDSA** key pair; set `SUPublicEDKey` + `SUFeedURL` in the
   Direct build's Info.plist; sign each release with `sign_update`.
3. **Appcast hosting**: publish `appcast.xml` + the notarized `.dmg`/`.zip` on your domain
   (the `SUFeedURL`).
4. (Optional) A dedicated Xcode Cloud workflow for the Direct archive if you want CI to
   produce notarized builds.

Once (1)–(3) are in place the `UpdaterController` Sparkle branch and the "Check for Updates…"
menu item become live automatically — no further code changes.
