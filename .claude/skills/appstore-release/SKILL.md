---
name: appstore-release
description: Build the Astrid iOS or Mac app on this machine and upload it to App Store Connect / TestFlight, without Xcode Cloud. Use when asked to "build locally", "make a local build", "push a build to the App Store or TestFlight", "cut a release", or when Xcode Cloud builds are being cancelled and a build is still needed.
---

# Local build → App Store Connect

## First: is Xcode Cloud the right answer?

Pushing `iosdev` / `macdev` builds and delivers to TestFlight on its own, and that is the normal
path. A local upload of a commit Xcode Cloud already built just duplicates it — measured
2026-08-27, a push produced builds 936/937 and a local upload of the identical commit produced
938/939 for nothing.

Use this skill only when Xcode Cloud can't or shouldn't run: its compute allotment is exhausted
(every run is created then immediately `CANCELED`), or a build is needed faster than the queue
allows. Otherwise push the dev branches and wait.

## The commands

Two of them. Pick by platform. Run them from the repo root.

| What you were asked for | Command |
|---|---|
| Check that iOS builds — nothing sent to Apple | `npm run release:ios` |
| Check that Mac builds — nothing sent to Apple | `npm run release:mac` |
| Send an iOS build to Apple | `npm run release:ios:upload` |
| Send a Mac build to Apple | `npm run release:mac:upload` |

Each takes 5–20 minutes. **Run it in the background and wait** — do not re-run it because it seems
slow, and do not run iOS and Mac at the same time.

Every run ends with one line starting `RESULT:`. That line is the answer. Report it to the user
as-is; there is nothing to interpret from the rest of the output.

```
RESULT: OK — ...        it worked; the line says what exists now
RESULT: FAILED — ...    it did not work; the line says why and what to do
```

## The rules

1. **Ask the user before running an `:upload` command.** It sends a build to Apple and cannot be
   undone. The build-only commands are always safe to run unasked.
2. **Do not add flags.** The defaults are right. (`--skip-gate`, `--build N`, `--arch arm64` and
   `--no-wait` exist for humans debugging a problem.)
3. **Do not edit `CURRENT_PROJECT_VERSION` or any version number** to make a build work. The script
   picks the build number itself.
4. **Do not touch signing, certificates, or provisioning profiles.** They are automatic.
5. If `RESULT: FAILED` names a fix, do that one thing and run the command again. Otherwise report
   the line to the user and stop. Do not improvise a different way to upload.

## What `:upload` does

Runs `npm run predeploy` (build + tests) → archives → exports to disk → **verifies the signed
entitlements on that .ipa** → uploads → waits until App Store Connect marks the build `VALID`,
which takes another 5–15 minutes. Only then does it print `RESULT: OK`.

The verification comes before the upload on purpose, so an unverified build cannot ship. It used
to come after, where it could never run at all: an upload export leaves no .ipa on disk, so the
check failed its own guard and every successful upload ended in `RESULT: FAILED` (task 3f964556).
The upload sends that same verified package with `xcrun altool --upload-app`, authenticated by the
App Store Connect key, so what was checked is byte-for-byte what Apple receives.
An upload that Apple accepted is not yet an installable build, so do not call anything shipped
before that line appears.

The build lands in **TestFlight**. Putting it on the actual App Store is a separate manual step in
App Store Connect (attach the build to a version, write What's New, submit for review) because it
needs screenshots and review notes. The `RESULT: OK` line spells this out.

## An upload needs an unreleased version number

Apple **closes a version's train once it has been released**: every further upload under that
version is rejected outright, TestFlight included. So if the app is currently on, say, 1.8.3 and
that version is on sale, no build of 1.8.3 can be uploaded ever again.

The run stops in preflight when this is the case, in about twenty seconds, and says so. The fix is
to raise `MARKETING_VERSION` for that target in `Astrid App.xcodeproj/project.pbxproj` (every build
config). **Ask the user which version number to use — do not pick one yourself.** The two targets
version independently: iOS is on a `1.8.x` train, Mac on a `1.0.x` train.

Building (`npm run release:ios`) is unaffected and works at any version.

## Useful checks (read-only, instant)

```bash
node scripts/asc-appstore.mjs builds ios      # recent uploads and their state (or: mac)
node scripts/asc-appstore.mjs versions ios    # App Store version states
node scripts/asc-appstore.mjs status ios 912  # one build
```

## Background for whoever maintains this

- Credentials are read from `.env.local` by name — `APPLE_ASC_KEY_ID`, `APPLE_ASC_ISSUER_ID`,
  `APPLE_ASC_PRIVATE_KEY`, `APPLE_APP_STORE_APP_ID`. Never inline, echo, or commit a key or token.
  The signing key is written mode-600 under `build/` and deleted on every exit path. If it is
  missing: `cp ../astrid-web/.env.local .env.local`.
- Signing is automatic via `-allowProvisioningUpdates` plus the API key, which stands in for the
  Xcode account the CLI does not have. If signing ever fails with "No Accounts", those flags were
  dropped from the xcodebuild command.
- **Build numbers are shared across both platforms.** Xcode Cloud numbers builds with its *run
  number*, so iOS and macOS interleave in one ascending sequence and `CURRENT_PROJECT_VERSION` in
  `project.pbxproj` names nothing anyone can install. The script uses
  `max(every uploaded build) + 1` and passes it on the xcodebuild command line, leaving the repo
  clean.
- **iOS and Mac share one bundle id** (`Graceful-Tools-Inc.Astrid-App`) and one App Store Connect
  app record, separated only by platform — every query filters on the build's
  `preReleaseVersion.platform`.
- **This is not the Developer ID path.** `npm run package:mac` builds the direct-download DMG:
  different method, different entitlements, different certificate. App Store uploads use the
  target's real entitlements; Developer ID exports must strip `com.apple.developer.applesignin`.
- The Mac target archives universal (arm64 + x86_64), which is why it takes roughly twice as long
  as iOS.
- A Release-only Swift optimizer crash blocked the Mac archive on 2026-08-23 (`EarlyPerfInliner` on
  `URLLoadCoordinator.deinit`, `Astrid App/Utilities/ImageCache.swift`). Fixed by writing that
  deinit by hand; `URLLoadCoordinatorDeinitTests` guards the shape. If a future archive dies inside
  `swift-frontend` with `-O`, that is the pattern: reproduce it in seconds with
  `swiftc -O -swift-version 5 -default-isolation=MainActor` on the offending file rather than
  waiting on full archives.
