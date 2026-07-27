// Ensure a "Astrid Mac Developer ID" (MAC_APP_DIRECT) provisioning profile exists and is installed.
//
// The xcodebuild CLI has no signed-in Xcode account, so it cannot create one itself — it fails the
// export with "No Accounts". The App Store Connect API can, using the same key Xcode Cloud uses.
import crypto from 'crypto';
import fs from 'fs';
import os from 'os';

const ROOT = new URL('..', import.meta.url).pathname;
const env = fs.readFileSync(ROOT + '.env.local', 'utf8');
const pick = k => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1]?.replace(/^["']|["']$/g, '');

const jwt = () => {
  const key = pick('APPLE_ASC_PRIVATE_KEY').replace(/\\n/g, '\n');
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const unsigned = b64({ alg: 'ES256', kid: pick('APPLE_ASC_KEY_ID'), typ: 'JWT' }) + '.' +
    b64({ iss: pick('APPLE_ASC_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1' });
  return unsigned + '.' + crypto.sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
};

const api = async (path, opts = {}) => {
  const r = await fetch('https://api.appstoreconnect.apple.com' + path, {
    ...opts, headers: { Authorization: 'Bearer ' + jwt(), 'Content-Type': 'application/json', ...(opts.headers || {}) },
  });
  const text = await r.text();
  return { status: r.status, body: text ? JSON.parse(text) : null };
};

const NAME = 'Astrid Mac Developer ID';
const BUNDLE = 'Graceful-Tools-Inc.Astrid-App';
const dir = `${os.homedir()}/Library/MobileDevice/Provisioning Profiles`;

const install = p => {
  fs.mkdirSync(dir, { recursive: true });
  const path = `${dir}/${p.id}.provisionprofile`;
  fs.writeFileSync(path, Buffer.from(p.attributes.profileContent, 'base64'));
  console.log(`✓ Profile "${p.attributes.name}" (${p.attributes.profileState}) → ${path}`);
};

const existing = (await api('/v1/profiles?limit=200')).body?.data
  ?.find(p => p.attributes.name === NAME && p.attributes.profileState === 'ACTIVE');
if (existing) {
  // The list endpoint omits profileContent; fetch the profile itself to get it.
  install((await api(`/v1/profiles/${existing.id}`)).body.data);
} else {
  const bundleId = (await api(`/v1/bundleIds?filter[identifier]=${BUNDLE}&limit=5`)).body?.data
    ?.find(b => b.attributes.identifier === BUNDLE);
  const cert = (await api('/v1/certificates?limit=200')).body?.data
    ?.find(c => c.attributes.certificateType === 'DEVELOPER_ID_APPLICATION');
  if (!bundleId || !cert) { console.error('Missing bundle id or Developer ID certificate'); process.exit(1); }
  const created = await api('/v1/profiles', { method: 'POST', body: JSON.stringify({ data: {
    type: 'profiles',
    attributes: { name: NAME, profileType: 'MAC_APP_DIRECT' },
    relationships: {
      bundleId: { data: { type: 'bundleIds', id: bundleId.id } },
      certificates: { data: [{ type: 'certificates', id: cert.id }] },
    },
  }}) });
  if (created.status !== 201) { console.error('Profile creation failed', JSON.stringify(created.body?.errors ?? created.body).slice(0, 400)); process.exit(1); }
  install(created.body.data);
}
