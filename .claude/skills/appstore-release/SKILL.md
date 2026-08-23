---
name: appstore-release
description: Build the Astrid iOS or Mac app locally on this machine and upload it to App Store Connect, bypassing Xcode Cloud. Use when asked to "build locally and push to the App Store", "make a local build", "upload a build to TestFlight/App Store without Xcode Cloud", or when Xcode Cloud runs are being cancelled (usage allotment exhausted) and a build is still needed.
---

# Local build → App Store Connect

Archives `Astrid App` (iOS) or `Astrid Mac` on this machine and uploads the result to App Store
Connect. Normal day-to-day shipping goes through Xcode Cloud (push `iosdev` / `macdev`); use this
when Xcode Cloud can't or shouldn't run — most often when its monthly compute allotment is
exhausted and every run is created then immediately `CANCELED`.

## Credentials

Everything comes from `astrid-ios/.env.local`, by variable name only. **Never inline, echo, log, or
commit a key, id, password, or token** — not into this file, a command line, a commit message, or a
task comment. Required names (already present for Xcode Cloud):

`APPLE_ASC_KEY_ID`, `APPLE_ASC_ISSUER_ID`, `APPLE_ASC_PRIVATE_KEY`, `APPLE_APP_STORE_APP_ID`

If `.env.local` is missing: `cp ../astrid-web/.env.local .env.local`. The scripts write the signing
key mode-600 under `build/` and delete it on every exit path.

## Ask first

Uploading is outward-facing and effectively irreversible (a build number can never be reused).
**Confirm with the user before running without `--dry-run`**, and state the target, the marketing
version, and the build number that will be used. `CLAUDE.md` already requires asking before an App
Store release.

## Procedure

1. **Verify the tree.** `npm run predeploy` must pass (build + unit tests). For a Mac upload also
   run the Mac suite. Do not archive a tree you have not gated.
2. **Check what the store already has** — this decides whether a version bump is needed:
   ```bash
   node scripts/asc-appstore.mjs builds ios --limit 5     # or mac
   node scripts/asc-appstore.mjs versions ios
   ```
   If the current `MARKETING_VERSION` is `READY_FOR_SALE`, the upload still succeeds and reaches
   TestFlight, but it cannot become a *new* App Store release until `MARKETING_VERSION` is bumped
   in `Astrid App.xcodeproj/project.pbxproj` (bump every config; the two targets version
   independently — iOS is on a `1.8.x` train, Mac on `1.0.x`). Ask the user which version to cut.
3. **Dry run first** when anything about the setup is new (fresh machine, expired cert, first Mac
   App Store upload):
   ```bash
   npm run release:ios -- --dry-run
   ```
   This archives and exports to `build/appstore-export-ios/` without uploading, which is where
   signing problems surface.
4. **Upload** once the user has confirmed:
   ```bash
   npm run release:ios      # or: npm run release:mac
   ```
   The script picks the next free build number itself, archives with automatic signing
   (`-allowProvisioningUpdates` + the ASC API key, since the CLI has no Xcode account), exports
   with `method: app-store-connect` / `destination: upload`, then polls until the build is `VALID`.
5. **Verify before reporting.** An accepted upload is not an installable build. Only say "shipped"
   once the build reads `VALID`:
   ```bash
   node scripts/asc-appstore.mjs status ios 912
   ```
   Report the **build number** the script used — that is what appears in TestFlight. Do not quote
   `CURRENT_PROJECT_VERSION` from the repo; on this project it does not name the build.
6. **Submitting for review is manual.** The script stops at "build is VALID in App Store Connect".
   Creating the App Store version record, attaching the build, writing What's New, and submitting
   need screenshots and review info — the user does those in App Store Connect. Check state with
   `node scripts/asc-appstore.mjs versions ios`.

## Options

| Flag | Effect |
|------|--------|
| `--dry-run` | Archive + export to `build/`, no upload |
| `--build N` | Pin the build number instead of querying for the next free one |
| `--no-wait` | Upload and return immediately, skipping the `VALID` poll |
| `--arch arm64` | Mac only: build Apple silicon only. **Ask first** — the result will not run on Intel Macs |

## Things that will bite you

- **Build numbers are shared across both platforms here.** Xcode Cloud numbers builds with its *run
  number*, so iOS and macOS interleave in one ascending sequence. `asc-appstore.mjs next` takes the
  max across both platforms plus one; don't hand-pick a number below that.
- **The build number is passed on the xcodebuild command line, not written into `project.pbxproj`.**
  The checked-in value is not the source of truth, and editing it only dirties the repo.
- **iOS and Mac share one bundle id** (`Graceful-Tools-Inc.Astrid-App`) and one App Store Connect
  app record, distinguished by platform. Queries filter on the build's `preReleaseVersion.platform`.
- **Do not reuse the Developer ID path for this.** `npm run package:mac` builds the *direct
  download* DMG — different method, different entitlements file, different certificate. App Store
  uploads use the target's real entitlements (Sign in with Apple included); Developer ID exports
  must strip `com.apple.developer.applesignin`.
- **The Mac target cannot archive at HEAD (measured 2026-08-23, commit `7ccdd94`).** The Release
  build crashes `swift-frontend` — `EarlyPerfInliner` on `URLLoadCoordinator.deinit`,
  `Astrid App/Utilities/ImageCache.swift:9` — reproducibly, on **both** arm64 and x86_64, so
  `--arch` is not a way around it. The iOS target builds the same file and is unaffected, so this
  is the Mac target's Release optimizer settings meeting that generic `@MainActor` class. It will
  break the Mac Xcode Cloud release build too; the source has to be fixed before `release:mac`
  can work.
- **The Mac target archives universal (arm64 + x86_64) by default.** `--arch arm64` halves the
  archive time but drops Intel support — a product decision, so only pass it when asked.
- **Archiving is the slow part** (several minutes, full release build of both app and extensions).
  Run it in the background and check on it rather than blocking on a foreground call.
- If signing fails with "No Accounts" or a missing profile, the API key flags were dropped from the
  command — automatic signing on this machine only works with them.

## Related

- `ASTRID.md` — architecture; read before changing app code.
- `scripts/package-mac.sh` — the *other* Mac path: notarized DMG for direct download.
- `.claude/commands/predeploy.md` — the quality gate this skill assumes has passed.
