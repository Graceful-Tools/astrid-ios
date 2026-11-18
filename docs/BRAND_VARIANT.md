# Building a brand as its own app

A brand can be built as a **second app** that installs beside Astrid, with its own App Store
record, rather than as Astrid with different colours. The "Whitelabel" build configuration
(schemes `Whitelabel App` and `Whitelabel Mac`) builds it from the files
`scripts/make-brand-variant.sh` writes. The brand itself — its name, domain, colours, copy —
comes from a `*.brand.json` profile. See astrid-web
[`docs/WHITELABELING.md`](https://github.com/Graceful-Tools/astrid-web/blob/main/docs/WHITELABELING.md)
§6 for what a profile can set.

```bash
./scripts/make-brand-variant.sh whitelabel-partner                  # ../astrid-web/brands/whitelabel-partner.brand.json
./scripts/make-brand-variant.sh ~/acme/acme.brand.json              # your own profile; no astrid-web checkout needed
./scripts/make-brand-variant.sh acme --team ABCDE12345 --bundle-id com.acme.tasks
```

Then build the Whitelabel schemes. **What to commit depends on whose app it is:**

- **Graceful Tools' own Whitelabel app** (`whitelabel-partner`, no `ios` block) is what `main`
  holds. Commit a re-run of it, for example after Astrid's plists gained a key.
- **A client's app** (any other identity) is **never committed to `main`.** The repo's own checks
  (`test-make-brand-variant.sh`, `BrandVariantTests`) compare against the committed Whitelabel
  files, so a client's variant on `main` turns predeploy red and leaves the shared `/fixall` tree
  dirty. Build it in a worktree of its own, and keep it on a branch there if it needs keeping:

  ```bash
  git worktree add ../astrid-ios-acme -b partner/acme origin/main
  cd ../astrid-ios-acme && ASC_ENV_FILE=~/partners/acme/asc.env ./scripts/appstore-release.sh ios --brand acme
  ```

  Rebase or recreate the worktree from fresh `main` before each release; a stale one builds an
  old app.

## The app's identity

These come from three places. Later ones win:

1. **Defaults:** Graceful Tools' own Whitelabel app.
2. **The profile's optional `ios` block.** Every key is optional:

   ```json
   "ios": {
     "bundleId": "com.acme.tasks",
     "appGroup": "group.com.acme.tasks",
     "keychainGroup": "com.acme.tasks",
     "developmentTeam": "ABCDE12345",
     "displayName": "Acme Tasks",
     "urlScheme": "acmetasks",
     "googleClientId": "123456-abcdef.apps.googleusercontent.com",
     "appIcon": "acme-icon-1024.png",
     "characterImage": "acme-mascot.png",
     "copyright": "Copyright © 2026 Acme Inc."
   }
   ```
3. **Arguments:** `--bundle-id`, `--app-group`, `--keychain-group`, `--team`, `--display-name`,
   `--url-scheme`.

| Value | Default | Where it lands |
|---|---|---|
| `bundleId` | `Graceful-Tools-Inc.Whitelabel` | iOS and Mac apps; the Share extension is `<bundleId>.Share` |
| `appGroup` | `group.gracefultools.whitelabel` | `AppGroupIdentifier` in the iOS and Share plists, and every entitlements file |
| `keychainGroup` | same as `bundleId` | `keychain-access-groups` in the iOS entitlements |
| `developmentTeam` | `34K3P7PD2W` | `DEVELOPMENT_TEAM` of every Whitelabel build configuration |
| `displayName` | `Whitelabel` | iOS home-screen name; Mac `PRODUCT_NAME`, so `<displayName>.app`, "About/Quit <displayName>", and the Services item |
| `googleClientId` | none (Astrid's own app keeps Astrid's) | `BrandGoogleClientId`, and the reversed-client URL type Google returns sign-in to. With no client, the build registers no Google redirect and draws no Google button, even when the server offers Google. Create an **iOS** OAuth client for the partner's bundle id in Google Cloud Console (docs/GOOGLE_OAUTH_SETUP.md) |
| `copyright` | Whitelabel's Graceful Tools line; a re-identified app gets `Copyright © <year> <brand name>. All rights reserved.` | the Mac About box (`NSHumanReadableCopyright` of the app configurations) |
| `urlScheme` | the profile's `NEXT_PUBLIC_BRAND_APP_URL_SCHEME`; `astrid` only for Whitelabel itself — a re-identified app without one is refused | the scheme the iOS app registers (`CFBundleURLSchemes`) and `Brand.urlScheme` answers: in-app links, deep links, the browser sign-in and OAuth callbacks |

**The URL scheme has to be the deployment's.** The server sends the browser back to
`<NEXT_PUBLIC_BRAND_APP_URL_SCHEME>://auth/callback`, so the app reads that same profile key, and
`ios.urlScheme` is only for a server that has been set to match. A partner on Astrid's own
deployment, like Whitelabel on astrid.cc, keeps `astrid`. The app's own URL type is named
`<bundleId>` rather than `cc.astrid.app`. The app also starts astrid-core with
the scheme and its hand-off client id.

Two system identifiers are always re-identified from `bundleId`, so the two apps never share
them: the board's drag type (`<bundleId>.board-card`) and the background sync task
(`<bundleId>.sync`). The app reads both back from its own Info.plist.

The brand's name (`NEXT_PUBLIC_BRAND_NAME`) is what the permission prompts say — "Acme uses
your camera…". It can differ from `displayName`.

## Artwork

- **`appIcon`** is a 1024×1024 PNG, with its path relative to the profile.
  - Every size the `AppIcon-Whitelabel` sets name is generated from it, in the iOS and Mac catalogs.
  - The iOS copy is flattened, since App Store Connect rejects an iOS icon with alpha.
  - Any other size is refused.
- **`characterImage`** is the mascot on sign-in, welcome and empty states. Without it, the script uses the profile's `NEXT_PUBLIC_BRAND_LOGO` under astrid-web's `public/`.
  - It becomes `<file stem>.imageset`, the name `Brand.characterImage` resolves, and the previous partner's imageset is removed.
- A profile passed by path from outside astrid-web looks for `NEXT_PUBLIC_BRAND_LOGO` beside it
  (`<profile dir>/../public/`), then in the paired astrid-web checkout's `public/`.
- For Whitelabel itself, art the profile does not name, or that cannot be found, leaves the
  committed art alone.
- **A re-identified app (any `bundleId` but Whitelabel's) is refused** when it names no
  `appIcon`, when art it names cannot be found, or when it has no URL scheme of its own
  (ADEV-108). Each would otherwise ship Whitelabel's icon or character, or register `astrid://`.

**What stays Astrid's on purpose.** The keychain service name `com.astrid.ios`
(`Constants.swift`) is not an identity: items are scoped by the keychain access group, which
is the variant's own, so the two apps never see each other's tokens. Renaming it would sign
every existing Astrid user out. The test targets' bundle IDs never ship.

**Each app carries only its own brand's art.**
- The partner's icon and character live in `PartnerArt-iOS.xcassets` / `PartnerArt-Mac.xcassets`; Astrid's character lives in `AstridArt-iOS` / `AstridArt-Mac`.
- Each configuration excludes the other brand's catalogs and the other platform's (`EXCLUDED_SOURCE_FILE_NAMES`). The `brand-art-catalogs` source contract keeps it that way.
- Only the selected app icon is compiled.
- Check with `xcrun assetutil --info <app>/Assets.car`.

**The Mac Direct (Developer ID) channel.**
- `Whitelabel-Mac-Direct.entitlements` is the branded copy of `Astrid Mac Direct.entitlements`.
- `./scripts/package-mac.sh --whitelabel` packages the partner's DMG with it, and with its own Developer ID profile (`mac-devid-profile.mjs --bundle-id`).
- It must be signed with the **partner's** Developer ID identity, named explicitly. See `docs/MAC_DISTRIBUTION.md` → *A partner's Mac app*.

## What it writes

- `Brands/Whitelabel/`: copies of Astrid's three Info.plists and four entitlements files,
  re-identified and branded, plus `variant.json`, the identity it last wrote.
- `PartnerArt-iOS.xcassets` and `PartnerArt-Mac.xcassets`: the icon and character art, when the
  profile names them.
- `Astrid App.xcodeproj/project.pbxproj`: **only** the `Whitelabel` build configurations. The
  Debug and Release configurations Astrid builds from are not touched.

A second run finds the values to replace by reading `variant.json`. Switching from one
partner's identity to another's is just another run. Don't edit the Whitelabel build settings
by hand: the next run only rewrites values it recognises.

## Before the first build: the partner's Apple account and server

A client's app is published from **the client's own Apple Developer account**, not Graceful
Tools'. Work through this once per partner, before the first `--brand` run. The script's closing
checklist repeats it, but by then a build has already been spent.

**1. The host is compiled in, so settle it first.**
- The server the app talks to is the profile's `NEXT_PUBLIC_BRAND_DOMAIN`. It is written into
  the Info.plist as `BrandHost` and read by `Brand.host`.
- A Release build has no way to change it: there is no ATS exception and no `debug_server_url`
  setting. The setting exists only in Debug.
- So it must be the **final, public HTTPS host**, already serving astrid-web, before the first
  build.
- Changing the host means a rebuild and a re-upload. It also invalidates every passkey
  registered so far, because the host is the passkey relying-party id
  (`PasskeyManager.performAuthentication`). Users would have to register passkeys again.

**2. The partner's Apple Developer team.**
- `ios.developmentTeam` is their 10-character team id (developer.apple.com → Membership).
- Under Identifiers, register these App IDs:

  | App ID | Capabilities |
  |---|---|
  | `<bundleId>` (one id, used by both the iOS and the Mac app) | App Groups (`appGroup`), Associated Domains, plus Sign in with Apple and Push Notifications if the profile keeps them |
  | `<bundleId>.Share` (the Share extension) | App Groups |

  codesign drops an App Group the App ID lacks without failing. The script catches that
  afterwards by checking the signed entitlements.
- **The first signing of each new App ID** needs one of two things: one Xcode sign-in to the
  partner's team (open the project, pick the `Whitelabel App` / `Whitelabel Mac` scheme, and let
  Signing & Capabilities create the profiles), or an **Admin**-role App Store Connect key.
  Automatic signing only uses Xcode-managed profiles, and a Developer- or App Manager-role key
  cannot create one. The script then stops with "this App ID has no Xcode-managed signing
  profile yet". After the first signing, any of their keys works.

**3. The partner's App Store Connect.**
- Create an app record for `<bundleId>` (iOS and macOS platforms).
- Make an API key: Users and Access → Integrations.
- Put both in the partner's own credentials file, outside this repository, and point
  `ASC_ENV_FILE` at it:
  `APPLE_ASC_KEY_ID`, `APPLE_ASC_ISSUER_ID`, `APPLE_ASC_PRIVATE_KEY`, and
  `APPLE_APP_STORE_APP_ID` (the record's numeric Apple ID).
- Build numbers and the released-version check ask about that app, not Astrid.

**4. The partner's server names the app.**
- Passkeys and universal links work only if
  `https://<host>/.well-known/apple-app-site-association` lists `<team>.<bundleId>`.
- astrid-web builds that file from `BRAND_APPLE_APP_IDS`. **Unset, it serves Astrid's own ids,
  and the partner's passkeys fail without an error anywhere.**
- The variant builds the iOS and Mac apps as **one** bundle id, so list that single
  `<team>.<bundleId>`. Separate iOS and Mac ids, as `acme.brand.json` shows, would name a Mac
  app this script never builds.
- `--brand` checks this before it archives:

  ```bash
  node scripts/check-aasa.mjs --host tasks.acme.example --app-id ABCDE12345.com.acme.tasks --profile acme
  ```

  It checks two things: that the live file names the app for both `webcredentials` and
  `applinks`, without a redirect, and that the profile's own `BRAND_APPLE_APP_IDS` includes the
  app.
  - A build-only run warns.
  - An `--upload` stops, unless `--skip-aasa` is passed.

The server's other settings (`APPLE_CLIENT_IDS`, `GOOGLE_ALLOWED_AUDIENCES`, the URL scheme) are
in the checklist printed at the end of each run.

## Building and signing a partner's apps

```bash
ASC_ENV_FILE=~/partners/acme/asc.env ./scripts/appstore-release.sh ios --brand acme   # build + sign only
ASC_ENV_FILE=~/partners/acme/asc.env ./scripts/appstore-release.sh mac --brand acme
```

`--brand` does four things:
1. It runs this script for the profile.
2. It asks the partner's server whether its apple-app-site-association names the app (above).
   With `--upload`, a server that does not stops the run before archiving.
3. It archives and exports the Whitelabel scheme, signed with the partner's App Store Connect key. `ASC_ENV_FILE` names **their** credentials, and its `APPLE_APP_STORE_APP_ID` is their app, so the build number and version check ask about it.
4. It verifies the signed App Groups and ends with `RESULT:`, followed by the checklist of what is left outside this repository:
   - the App IDs and the App Group capability
   - the App Store Connect record
   - the deployment's `BRAND_APPLE_APP_IDS`, `APPLE_CLIENT_IDS`, `GOOGLE_ALLOWED_AUDIENCES` and URL scheme

`--upload` sends it, which is asked first, as for Astrid. A partner build pushes no `ios-build-N` tag; those track Astrid's releases.

**The gate runs before the variant is written.** With `--upload`, `npm run predeploy` runs on the
committed tree first, then `--brand` writes the client's variant. The repo's checks would fail on
the variant itself. If the checkout already holds a variant (a previous partner's run), the script
refuses and says how to restore it. `--skip-gate` remains for a checkout you have just gated.

## Not configurable here (yet)

Nothing on the app side: everything above comes from the profile.

The cross-client plan — one brand profile schema in astrid-core with `cargo xtask gen-brand`
writing every client's resources — is astrid-core
[`docs/CROSS_CLIENT_REVIEW_2026-11.md`](https://github.com/Graceful-Tools/astrid-core/blob/main/docs/CROSS_CLIENT_REVIEW_2026-11.md)
(AWTD2-158).

## What checks it

- `scripts/test-make-brand-variant.sh` (in `npm run test:scripts`) runs the script in a
  scratch copy with no astrid-web beside it. A profile without an `ios` block must reproduce
  the committed files exactly. An `ios` block must reach every place in the table above and
  change nothing outside the Whitelabel configurations.
- `BrandVariantTests` (unit tests) fails when Astrid's plists gain a key the copies lack, or
  when any permission prompt, Services item or Mac product name still says Astrid. To fix it,
  re-run the script for `whitelabel-partner` and commit the result. Both checks expect Graceful
  Tools' Whitelabel app, which is why a client's variant stays off `main` (above).
