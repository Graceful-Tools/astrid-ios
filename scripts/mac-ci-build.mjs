// Download the latest Xcode Cloud macOS build and run it locally — the exact CI binary, without
// TestFlight. Uses the DEVELOPMENT export: the app-store export is signed for the Mac App Store
// and refuses to launch outside it.
//
// Usage: node scripts/mac-ci-build.mjs [--open]
import crypto from 'crypto';
import fs from 'fs';
import { execSync } from 'child_process';

const ROOT = new URL('..', import.meta.url).pathname;
const env = fs.readFileSync(ROOT + '.env.local', 'utf8');
const pick = k => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1]?.replace(/^["']|["']$/g, '');
const jwt = () => {
  const key = pick('APPLE_ASC_PRIVATE_KEY').replace(/\\n/g, '\n');
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const u = b64({ alg: 'ES256', kid: pick('APPLE_ASC_KEY_ID'), typ: 'JWT' }) + '.' +
    b64({ iss: pick('APPLE_ASC_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1' });
  return u + '.' + crypto.sign('sha256', Buffer.from(u), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
};
const api = async p => {
  const r = await fetch('https://api.appstoreconnect.apple.com' + p, { headers: { Authorization: 'Bearer ' + jwt() } });
  return r.json();
};

const PRODUCT = 'AE1AD027-7DFE-4BBE-99DD-C5465D836CCB';
const wfs = await api(`/v1/ciProducts/${PRODUCT}/workflows?limit=25`);
const mac = wfs.data.find(w => /mac/i.test(w.attributes.name));
const runs = await api(`/v1/ciWorkflows/${mac.id}/buildRuns?limit=10&sort=-number`);

let asset;
for (const run of runs.data) {
  const acts = await api(`/v1/ciBuildRuns/${run.id}/actions`);
  const archive = acts.data.find(a => a.attributes.actionType === 'ARCHIVE' && a.attributes.completionStatus === 'SUCCEEDED');
  if (!archive) continue;
  const arts = await api(`/v1/ciBuildActions/${archive.id}/artifacts`);
  asset = (arts.data ?? []).find(a => a.attributes.fileName.includes('development'));
  if (asset) { console.log(`Xcode Cloud build #${run.attributes.number}: ${asset.attributes.fileName}`); break; }
}
if (!asset) { console.error('No successful macOS archive with a development export found'); process.exit(1); }

const dir = '/tmp/astrid-mac-ci';
fs.rmSync(dir, { recursive: true, force: true });
fs.mkdirSync(dir, { recursive: true });
const zip = `${dir}/app.zip`;
fs.writeFileSync(zip, Buffer.from(await (await fetch(asset.attributes.downloadUrl)).arrayBuffer()));
execSync(`unzip -q -o "${zip}" -d "${dir}"`);
const app = execSync(`find "${dir}" -name "*.app" -maxdepth 3 | head -1`).toString().trim();
console.log('→', app);
console.log(execSync(`codesign -dv --verbose=2 "${app}" 2>&1 | grep -E "Authority|Identifier" | head -3`).toString());
if (process.argv.includes('--open')) execSync(`open "${app}"`);
