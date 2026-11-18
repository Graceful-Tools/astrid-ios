# Astrid for Mac — Distribution (M3)

Two channels from one `Astrid Mac` target (see `docs/archive/MAC_APP_SPEC.md` §8).

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

`npm run package:mac` installs the `Astrid Mac Developer ID` profile in Xcode's current and
legacy profile directories, then selects it by UUID and signs with its newest certificate. Its
matching private key must be in the keychain; an older Developer ID certificate with the same
display name can remain installed during renewal. App Store Connect credentials are read from
the private file named by `ASC_ENV_FILE`, which must be outside this public repository.
Notarization uses a mode-600 temporary key in a private directory outside the repository; it
is removed on exit. Set `TMPDIR` outside the repository as well.

## A partner's Mac app

A client's Mac app (the `Whitelabel Mac` scheme, written by `make-brand-variant.sh`; see
`docs/BRAND_VARIANT.md`) is signed by **the client's** Apple Developer team, not Graceful
Tools'.

- **App Store channel.** `ASC_ENV_FILE=<partner's credentials> ./scripts/appstore-release.sh mac --brand <profile>`.
  The partner's App IDs, app record and first signing are covered in `docs/BRAND_VARIANT.md`
  → *Before the first build*.
- **Direct channel (DMG).** You need three things:
  1. The partner's **Developer ID Application** certificate and its private key, imported into
     the login keychain as a `.p12` the partner exports. Only their Account Holder can create the
     certificate.
  2. Their App Store Connect key in `ASC_ENV_FILE`. It creates the Developer ID profile for
     their bundle id and notarizes under their team.
  3. `MAC_DEVID_IDENTITY` set to the SHA-1 of that identity, as listed by
     `security find-identity -v -p codesigning`.

  ```bash
  MAC_DEVID_IDENTITY=<sha1> ASC_ENV_FILE=~/partners/acme/asc.env ./scripts/package-mac.sh --whitelabel
  ```

  `--whitelabel` refuses to run without `MAC_DEVID_IDENTITY`. It also stops if the identity is
  not installed, or if the partner's profile signs with a different one (ADEV-107). A build Mac
  usually holds Graceful Tools' own Developer ID too, and the first one in the keychain must
  never sign a partner's app.
