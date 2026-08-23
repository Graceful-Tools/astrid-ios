// asc-appstore.mjs — App Store Connect queries for the LOCAL App Store release flow.
//
// Reads its credentials from .env.local (APPLE_ASC_KEY_ID / APPLE_ASC_ISSUER_ID /
// APPLE_ASC_PRIVATE_KEY / APPLE_APP_STORE_APP_ID) — the same key Xcode Cloud and
// scripts/mac-devid-profile.mjs already use. Nothing is ever printed but ids and versions.
//
// Usage:
//   node scripts/asc-appstore.mjs next    <ios|mac> [--floor N]   → next free build number
//   node scripts/asc-appstore.mjs builds  <ios|mac> [--limit N]   → recent uploads + state
//   node scripts/asc-appstore.mjs status  <ios|mac> <buildNumber> → one build's processing state
//   node scripts/asc-appstore.mjs wait    <ios|mac> <buildNumber> [--timeout-min N]
//   node scripts/asc-appstore.mjs versions <ios|mac>              → App Store version states
import crypto from 'crypto';
import fs from 'fs';

const ROOT = new URL('..', import.meta.url).pathname;
const env = fs.readFileSync(ROOT + '.env.local', 'utf8');
const pick = k => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1]?.replace(/^["']|["']$/g, '');

// Match on the APPLE_ASC_PRIVATE_KEY= prefix, not the first PEM block in the file — .env.local
// holds other private keys and grabbing the wrong one fails ES256 signing with "invalid digest".
const jwt = () => {
  const key = pick('APPLE_ASC_PRIVATE_KEY')?.replace(/\\n/g, '\n');
  if (!key) die('APPLE_ASC_PRIVATE_KEY missing from .env.local');
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const unsigned = b64({ alg: 'ES256', kid: pick('APPLE_ASC_KEY_ID'), typ: 'JWT' }) + '.' +
    b64({ iss: pick('APPLE_ASC_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1' });
  return unsigned + '.' + crypto.sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
};

const die = m => { console.error(m); process.exit(1); };

const api = async path => {
  const r = await fetch('https://api.appstoreconnect.apple.com' + path, {
    headers: { Authorization: 'Bearer ' + jwt() },
  });
  const text = await r.text();
  const body = text ? JSON.parse(text) : null;
  if (r.status >= 300) die(`ASC ${r.status}: ${JSON.stringify(body?.errors ?? body).slice(0, 400)}`);
  return body;
};

const APP = pick('APPLE_APP_STORE_APP_ID') || die('APPLE_APP_STORE_APP_ID missing from .env.local');
const PLATFORM = { ios: 'IOS', mac: 'MAC_OS' };

const arg = (flag, dflt) => {
  const i = process.argv.indexOf(flag);
  return i === -1 ? dflt : process.argv[i + 1];
};

// iOS and macOS builds live under the same app record here (one bundle id, two platforms), so
// every query filters client-side on the included preReleaseVersion's platform.
const allBuilds = async (limit = 50) => {
  const res = await api(`/v1/builds?filter[app]=${APP}&sort=-version&limit=${limit}&include=preReleaseVersion`);
  const pre = Object.fromEntries((res.included ?? []).map(i => [i.id, i.attributes]));
  return res.data
    .map(b => ({
      number: b.attributes.version,
      state: b.attributes.processingState,
      expired: b.attributes.expired,
      uploaded: b.attributes.uploadedDate,
      marketing: pre[b.relationships?.preReleaseVersion?.data?.id]?.version,
      platform: pre[b.relationships?.preReleaseVersion?.data?.id]?.platform,
    }));
};

const buildsFor = async (platform, limit = 50) => (await allBuilds(limit)).filter(b => b.platform === platform);

const [cmd, target] = process.argv.slice(2);
const platform = PLATFORM[target] || die('Usage: node scripts/asc-appstore.mjs <next|builds|status|wait|versions> <ios|mac> [...]');

if (cmd === 'next') {
  // Apple rejects an upload whose build number is not strictly greater than every build already
  // uploaded for this platform. Xcode Cloud sets its own numbers (the run number), so the
  // pbxproj value is usually far behind what the store has seen — take the max of both.
  // Max across BOTH platforms, not just this one: Xcode Cloud numbers its builds with the run
  // number, so iOS and macOS share one ascending sequence. Staying above all of it keeps a local
  // upload from landing on a number CI is about to use.
  const floor = parseInt(arg('--floor', '0'), 10) || 0;
  const highest = (await allBuilds()).reduce((m, b) => Math.max(m, parseInt(b.number, 10) || 0), 0);
  console.log(Math.max(highest, floor) + 1);
} else if (cmd === 'builds') {
  const rows = (await buildsFor(platform, parseInt(arg('--limit', '10'), 10) * 5)).slice(0, parseInt(arg('--limit', '10'), 10));
  if (!rows.length) console.log('(no builds)');
  for (const b of rows) console.log(`${b.number}\t${b.marketing}\t${b.state}${b.expired ? '\tEXPIRED' : ''}\t${b.uploaded}`);
} else if (cmd === 'status') {
  const want = process.argv[4] || die('status needs a build number');
  const b = (await buildsFor(platform)).find(x => x.number === String(want));
  console.log(b ? `${b.number}\t${b.marketing}\t${b.state}` : 'NOT_FOUND');
} else if (cmd === 'wait') {
  // A successful upload does not mean an installable build: ASC processes it afterwards and can
  // still reject it. Poll to VALID before reporting anything as shipped.
  const want = String(process.argv[4] || die('wait needs a build number'));
  const deadline = Date.now() + (parseInt(arg('--timeout-min', '30'), 10) * 60_000);
  for (;;) {
    const b = (await buildsFor(platform)).find(x => x.number === want);
    const state = b?.state ?? 'NOT_FOUND';
    console.log(`  ${new Date().toISOString().slice(11, 19)}  build ${want}: ${state}`);
    if (state === 'VALID') break;
    if (state === 'INVALID' || state === 'FAILED') die(`Build ${want} came back ${state} — check App Store Connect for the reason.`);
    if (Date.now() > deadline) die(`Timed out waiting for build ${want} (last state: ${state}).`);
    await new Promise(r => setTimeout(r, 60_000));
  }
} else if (cmd === 'versions') {
  const res = await api(`/v1/apps/${APP}/appStoreVersions?filter[platform]=${platform}&limit=5`);
  for (const v of res.data) console.log(`${v.attributes.versionString}\t${v.attributes.appStoreState}\t${v.attributes.createdDate}`);
} else {
  die(`Unknown command "${cmd}"`);
}
