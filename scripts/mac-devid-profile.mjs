// Ensure a "Astrid Mac Developer ID" (MAC_APP_DIRECT) provisioning profile exists and is installed.
//
// The xcodebuild CLI has no signed-in Xcode account, so it cannot create one itself — it fails the
// export with "No Accounts". The App Store Connect API can, using the same key Xcode Cloud uses.
import fs from 'fs';
import os from 'os';
//
// `--recreate` replaces an existing profile that is not built on the newest Developer ID certificate
// — the step after issuing a G2 replacement for the Sub-CA that expires 2027-02-01 (AITD-447).
import { pick, ascRequest as api } from './lib/asc-jwt.mjs';
import { pickDeveloperIdCert } from './lib/developer-id.mjs';


const NAME = 'Astrid Mac Developer ID';
const BUNDLE = 'Graceful-Tools-Inc.Astrid-App';
const legacyDir = `${os.homedir()}/Library/MobileDevice/Provisioning Profiles`;
const xcodeDir = `${os.homedir()}/Library/Developer/Xcode/UserData/Provisioning Profiles`;
const printPath = process.argv.includes('--print-path');
const report = message => (printPath ? console.error(message) : console.log(message));

const install = p => {
  const uuid = p.attributes.uuid;
  if (!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(uuid ?? '')) {
    throw new Error('App Store Connect did not return a valid UUID for the provisioning profile');
  }
  const content = Buffer.from(p.attributes.profileContent, 'base64');
  fs.mkdirSync(legacyDir, { recursive: true });
  fs.mkdirSync(xcodeDir, { recursive: true });
  fs.writeFileSync(`${legacyDir}/${p.id}.provisionprofile`, content);
  const path = `${xcodeDir}/${uuid}.provisionprofile`;
  fs.writeFileSync(path, content);
  report(`✓ Profile "${p.attributes.name}" (${p.attributes.profileState}) → ${path}`);
  if (printPath) console.log(path);
};

const recreate = process.argv.includes('--recreate');
const cert = pickDeveloperIdCert((await api('/v1/certificates?limit=200')).body?.data);

let existing = (await api('/v1/profiles?limit=200')).body?.data
  ?.find(p => p.attributes.name === NAME && p.attributes.profileState === 'ACTIVE');
if (existing && cert) {
  // A profile on the old certificate stops working with it; say so, and replace it on request.
  const onCerts = (await api(`/v1/profiles/${existing.id}/certificates?limit=50`)).body?.data ?? [];
  if (!onCerts.some(c => c.id === cert.id)) {
    if (!recreate) {
      console.warn(`! "${NAME}" is not built on the newest Developer ID certificate (${cert.attributes.certificateType}, ` +
        `expires ${cert.attributes.expirationDate}). Rerun with --recreate to replace it.`);
    } else {
      const removed = await api(`/v1/profiles/${existing.id}`, { method: 'DELETE' });
      if (removed.status !== 204) { console.error('Profile delete failed', removed.status); process.exit(1); }
      report(`✓ Deleted the old "${NAME}" profile`);
      existing = null;
    }
  }
}
if (existing) {
  // The list endpoint omits profileContent; fetch the profile itself to get it.
  install((await api(`/v1/profiles/${existing.id}`)).body.data);
} else {
  const bundleId = (await api(`/v1/bundleIds?filter[identifier]=${BUNDLE}&limit=5`)).body?.data
    ?.find(b => b.attributes.identifier === BUNDLE);
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
