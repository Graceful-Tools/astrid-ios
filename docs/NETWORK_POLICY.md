# What the app connects to

The Astrid iOS and Mac apps talk to **one server: the one they're pointed at.** That's Astrid's
own by default, or a partner's own deployment of astrid-web, chosen on the sign-in screen
("Use a different server", ADEV-118) or set by device management (`docs/MANAGED_CONFIG.md`).
This page is the policy a partner can review, and `npm run check:contracts` enforces it
(rule `talks-only-to-its-server`, ADEV-123).

## What the app contacts

| What | When | Who receives it |
|---|---|---|
| **The server in use** | Everything: sign-in, tasks, lists, comments, chat, sync, live updates, attachments, agent work. The `x-platform` analytics header goes only here. | Your server |
| **Addresses your server returns** | Images and files whose URLs come from your server's data: profile photos, attachments, list images. | Wherever those URLs point: your storage, or a photo host a user's sign-in provider gave |
| **Pages the person opens** | Links they tap: a help page for AI keys, a task link opened in the browser, your server's sign-in page. | That site, from the browser |
| **Apple** | The operating system: App Store installs and updates, and the crash reports and usage statistics the person chose to share with app developers. | Apple, then the app's publisher. See below. |
| **Google / Apple sign-in** | **Only on Astrid's own server.** On your server these buttons are hidden, and sign-in happens on your server's page. | Google or Apple |

## What never goes to Graceful Tools when the app is on your server

- No task, list, comment, chat, attachment or account data. The app has no endpoint of ours
  compiled in for any of it. The data core (astrid-core) refuses to start without a named
  server (`require-base-url`), so it can't fall back to ours.
- No analytics or telemetry. The app ships no analytics or crash-reporting SDK.
- No session. Switching servers signs out and wipes this device's copy of the previous server's
  data before talking to the new one. A server change made while the app was closed is caught
  at the next launch, before anything is sent (`SessionServerGuard`).

## The one caveat: Apple's developer reports

If a person opts in to *Share with App Developers* in iOS or macOS settings, Apple sends
anonymised crash logs and usage metrics to whoever **publishes** the app. For the stock Astrid
app that's Graceful Tools. These reports carry no task content and no account identity, but they
do reach us. A partner who can't accept that should ship a **branded build** under their own
Apple account (`docs/BRAND_VARIANT.md`). Then those reports go to the partner.

## Check it yourself

Put a device behind an intercepting proxy (mitmproxy, Charles or Proxyman), trust its
certificate, point the app at your server, sign in, and use it. Every request should go to
your server's host, apart from the rows above (Apple's own traffic, images at addresses your
server returned, and pages the person opened).

## How it's enforced

- **`talks-only-to-its-server`** (`scripts/check-source-contracts.mjs`, run by predeploy):
  - Any `http(s)://` host in app source must be on a short list, each with a stated reason:
    help pages, Google sign-in on Astrid's own server, development addresses and test fixtures.
  - Only five networking files may open a `URLSession`.
  - A new host or a new network path fails the build until this page and the rule both say so.
- **`core-base-url-required`**: the core is built without a default server.
- **`platform-header`**: the analytics header is sent only to the server in use, never to
  a third party.

## Limits

- **Universal Links** (tapping a link in Mail or Safari) open the app only for Astrid's own
  domain. A link to your server opens in the app when it's tapped inside the app. For your own
  domain, ship a branded build.
- **Your server must be new enough** for the app version (`meta.apiLevel`). Policy: astrid-web
  `docs/deployment/WHITE_LABEL_COMPATIBILITY.md`.
