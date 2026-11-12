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

Commit what it writes, then build the Whitelabel schemes.

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
     "characterImage": "acme-mascot.png"
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
| `urlScheme` | the profile's `NEXT_PUBLIC_BRAND_APP_URL_SCHEME`, else `astrid` | the scheme the iOS app registers (`CFBundleURLSchemes`) and `Brand.urlScheme` answers: in-app links, deep links, the browser sign-in and OAuth callbacks |

**The URL scheme has to be the deployment's.** The server sends the browser back to
`<NEXT_PUBLIC_BRAND_APP_URL_SCHEME>://auth/callback`, so the app reads that same profile key, and
`ios.urlScheme` is only for a server that has been set to match. A partner on Astrid's own
deployment, like Whitelabel on astrid.cc, keeps `astrid`. The app also starts astrid-core with
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
- Art the profile does not name, or that cannot be found, leaves the committed art alone.

**Each app carries only its own brand's art.**
- The partner's icon and character live in `PartnerArt-iOS.xcassets` / `PartnerArt-Mac.xcassets`; Astrid's character lives in `AstridArt-iOS` / `AstridArt-Mac`.
- Each configuration excludes the other brand's catalogs and the other platform's (`EXCLUDED_SOURCE_FILE_NAMES`). The `brand-art-catalogs` source contract keeps it that way.
- Only the selected app icon is compiled.
- Check with `xcrun assetutil --info <app>/Assets.car`.

**The Mac Direct (Developer ID) channel.**
- `Whitelabel-Mac-Direct.entitlements` is the branded copy of `Astrid Mac Direct.entitlements`.
- `./scripts/package-mac.sh --whitelabel` packages the partner's DMG with it, and with its own Developer ID profile (`mac-devid-profile.mjs --bundle-id`).

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

## Building and signing a partner's apps

```bash
ASC_ENV_FILE=~/partners/acme/asc.env ./scripts/appstore-release.sh ios --brand acme   # build + sign only
ASC_ENV_FILE=~/partners/acme/asc.env ./scripts/appstore-release.sh mac --brand acme
```

`--brand` does three things:
1. It runs this script for the profile.
2. It archives and exports the Whitelabel scheme, signed with the partner's App Store Connect key. `ASC_ENV_FILE` names **their** credentials, and its `APPLE_APP_STORE_APP_ID` is their app, so the build number and version check ask about it.
3. It verifies the signed App Groups and ends with `RESULT:`, followed by the checklist of what is left outside this repository:
   - the App IDs and the App Group capability
   - the App Store Connect record
   - the deployment's `BRAND_APPLE_APP_IDS`, `APPLE_CLIENT_IDS`, `GOOGLE_ALLOWED_AUDIENCES` and URL scheme

`--upload` sends it, which is asked first, as for Astrid. A partner build pushes no `ios-build-N` tag; those track Astrid's releases.

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
  re-run the script and commit the result.
