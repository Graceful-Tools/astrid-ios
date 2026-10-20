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
     "displayName": "Acme Tasks"
   }
   ```
3. **Arguments:** `--bundle-id`, `--app-group`, `--keychain-group`, `--team`, `--display-name`.

| Value | Default | Where it lands |
|---|---|---|
| `bundleId` | `Graceful-Tools-Inc.Whitelabel` | iOS and Mac apps; the Share extension is `<bundleId>.Share` |
| `appGroup` | `group.gracefultools.whitelabel` | `AppGroupIdentifier` in the iOS and Share plists, and every entitlements file |
| `keychainGroup` | same as `bundleId` | `keychain-access-groups` in the iOS entitlements |
| `developmentTeam` | `34K3P7PD2W` | `DEVELOPMENT_TEAM` of every Whitelabel build configuration |
| `displayName` | `Whitelabel` | iOS home-screen name; Mac `PRODUCT_NAME`, so `<displayName>.app`, "About/Quit <displayName>", and the Services item |

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

## Not configurable here

The `astrid://` URL scheme is frozen across platforms. Making it configurable is a separate
astrid-core task.

## What checks it

- `scripts/test-make-brand-variant.sh` (in `npm run test:scripts`) runs the script in a
  scratch copy with no astrid-web beside it. A profile without an `ios` block must reproduce
  the committed files exactly. An `ios` block must reach every place in the table above and
  change nothing outside the Whitelabel configurations.
- `BrandVariantTests` (unit tests) fails when Astrid's plists gain a key the copies lack, or
  when any permission prompt, Services item or Mac product name still says Astrid. To fix it,
  re-run the script and commit the result.
