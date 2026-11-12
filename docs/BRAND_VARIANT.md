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
     "googleClientId": "123456-abcdef.apps.googleusercontent.com"
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

## What it writes

- `Brands/Whitelabel/`: copies of Astrid's three Info.plists and three entitlements files,
  re-identified and branded, plus `variant.json`, the identity it last wrote.
- `Astrid App.xcodeproj/project.pbxproj`: **only** the `Whitelabel` build configurations. The
  Debug and Release configurations Astrid builds from are not touched.

A second run finds the values to replace by reading `variant.json`. Switching from one
partner's identity to another's is just another run. Don't edit the Whitelabel build settings
by hand: the next run only rewrites values it recognises.

## Not configurable here (yet)

- **Artwork.** The script copies none; a partner replaces `AppIcon-Whitelabel` in both catalogs and
  adds the character imageset twice by hand — AITD-618. Building and signing a partner's apps in
  one command is AITD-619.

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
