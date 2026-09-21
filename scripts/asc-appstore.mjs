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
//   node scripts/asc-appstore.mjs testflight <ios|mac> <buildNumber> → is it live for testers?
//   node scripts/asc-appstore.mjs versions <ios|mac>              → App Store version states
//   node scripts/asc-appstore.mjs version-state <ios|mac> <x.y.z> → one version's state, or NOT_FOUND
// Credentials, signing and the env-file lookup (ASC_ENV_FILE) live in lib/asc-jwt.mjs.
import { pick, ascRequest } from './lib/asc-jwt.mjs';

const die = m => { console.error(m); process.exit(1); };

const api = async path => {
  const { status, body } = await ascRequest(path).catch(e => die(e.message));
  if (status >= 300) die(`ASC ${status}: ${JSON.stringify(body?.errors ?? body).slice(0, 400)}`);
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
      id: b.id,
      compliance: b.attributes.usesNonExemptEncryption,
      number: b.attributes.version,
      state: b.attributes.processingState,
      expired: b.attributes.expired,
      uploaded: b.attributes.uploadedDate,
      marketing: pre[b.relationships?.preReleaseVersion?.data?.id]?.version,
      platform: pre[b.relationships?.preReleaseVersion?.data?.id]?.platform,
    }));
};

const buildsFor = async (platform, limit = 50) => (await allBuilds(limit)).filter(b => b.platform === platform);


// TestFlight availability is a SEPARATE question from processing. A build can be VALID and still
// not reach anyone: export compliance may be unanswered, or the build may not be in a group.
// Internal testers here are covered automatically — the "Family" group has access to all builds —
// so a VALID build with compliance answered reaches them without any further step. External groups
// need a beta review submission, which Xcode Cloud builds do not get either.
const testflightState = async (platform, want) => {
  const b = (await buildsFor(platform)).find(x => x.number === String(want));
  if (!b) return { found: false };
  const detail = await api(`/v1/builds/${b.id}/buildBetaDetail`);
  return {
    found: true,
    processing: b.state,
    complianceAnswered: b.compliance !== null,
    internal: detail?.data?.attributes?.internalBuildState,
    external: detail?.data?.attributes?.externalBuildState,
  };
};

// `runs` is the only command here that is not per-platform, and the only one that can tie a
// TestFlight build back to a commit: nothing on /v1/builds carries a sha, but a build number IS
// its Xcode Cloud run number (measured 2026-08-18), and the run knows what it built. That is the
// question a task cannot be completed without answering — "is my fix in a build Jon can open?"
// See `.claude/commands/fixall.md`, "A task is DONE when the build carrying it is ready".
if (process.argv[2] === 'runs') {
  const limit = arg('--limit', '10');
  const products = await api('/v1/ciProducts?limit=10');
  for (const prod of products.data ?? []) {
    const runs = await api(`/v1/ciProducts/${prod.id}/buildRuns?limit=${limit}&sort=-number`);
    for (const r of runs.data ?? []) {
      const a = r.attributes ?? {};
      const subject = (a.sourceCommit?.message ?? '').split('\n')[0].slice(0, 60);
      console.log([
        a.number,
        a.completionStatus ?? a.executionProgress ?? '-',
        (a.sourceCommit?.commitSha ?? '-').slice(0, 7),
        subject,
      ].join('\t'));
    }
  }
  process.exit(0);
}

const [cmd, target] = process.argv.slice(2);
const platform = PLATFORM[target] || die('Usage: node scripts/asc-appstore.mjs <next|builds|status|wait|versions|released|version-state> <ios|mac> [...]\n       node scripts/asc-appstore.mjs runs [--limit N]   # build number -> commit');

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
    if (state === 'VALID') {
      const tf = await testflightState(platform, want);
      console.log(`  TestFlight: internal=${tf.internal}, export compliance ${tf.complianceAnswered ? 'answered' : 'NOT ANSWERED'}`);
      if (!tf.complianceAnswered) {
        die(`Build ${want} is VALID but its export-compliance question is unanswered, so testers cannot install it. Every target's Info.plist should carry ITSAppUsesNonExemptEncryption; answer it in App Store Connect > TestFlight for this build.`);
      }
      if (tf.internal !== 'IN_BETA_TESTING') {
        console.log(`  Note: internal state is ${tf.internal}, not IN_BETA_TESTING yet — it usually flips within a minute.`);
      }
      break;
    }
    if (state === 'INVALID' || state === 'FAILED') die(`Build ${want} came back ${state} — check App Store Connect for the reason.`);
    if (Date.now() > deadline) die(`Timed out waiting for build ${want} (last state: ${state}).`);
    await new Promise(r => setTimeout(r, 60_000));
  }
} else if (cmd === 'testflight') {
  const want = process.argv[4] || die('testflight needs a build number');
  const tf = await testflightState(platform, want);
  if (!tf.found) { console.log('NOT_FOUND'); }
  else console.log(`processing=${tf.processing}\tinternal=${tf.internal}\texternal=${tf.external}\tcompliance=${tf.complianceAnswered ? 'answered' : 'UNANSWERED'}`);
} else if (cmd === 'versions') {
  // The third column is createdDate — when the version RECORD was made, not when it went live.
  // It misled the 2026-09-13 diagnosis (AITD-396): 1.9.2 looked a day old while builds still
  // uploaded under it. Judge a version by its state, never by this date.
  const res = await api(`/v1/apps/${APP}/appStoreVersions?filter[platform]=${platform}&limit=5`);
  for (const v of res.data) console.log(`${v.attributes.versionString}\t${v.attributes.appStoreState}\t${v.attributes.createdDate}`);
} else if (cmd === 'released') {
  // Which version is LIVE on the store for this platform, as opposed to merely existing as a
  // record. Answers the one question `version-state` cannot: it needs a version to ask about,
  // and the point here is to find out which one that is (AITD-407).
  //
  // Only READY_FOR_SALE counts. REMOVED_FROM_SALE and REPLACED_WITH_NEW_INFO are "released" for
  // check-version.sh's purpose (Apple has closed them to new builds) but they are NOT installable,
  // so pointing the in-app Update card at one would nag every user toward a version they cannot
  // get — the loud failure this check exists to prevent.
  const res = await api(`/v1/apps/${APP}/appStoreVersions?filter[platform]=${platform}&filter[appStoreState]=READY_FOR_SALE&limit=5`);
  const live = res.data.map(v => v.attributes.versionString);
  console.log(live.length ? live[0] : 'NONE');
} else if (cmd === 'version-state') {
  // Asked by name, so a version older than the five `versions` lists is still found. Prints the
  // bare state (READY_FOR_SALE, PREPARE_FOR_SUBMISSION, …) or NOT_FOUND when App Store Connect
  // has no record for it — which is the normal answer for a freshly bumped MARKETING_VERSION.
  const want = process.argv[4] || die('version-state needs a version, e.g. 1.9.3');
  const res = await api(`/v1/apps/${APP}/appStoreVersions?filter[platform]=${platform}&filter[versionString]=${encodeURIComponent(want)}&limit=5`);
  const hit = res.data.find(v => v.attributes.versionString === want);
  console.log(hit ? hit.attributes.appStoreState : 'NOT_FOUND');
} else {
  die(`Unknown command "${cmd}"`);
}
