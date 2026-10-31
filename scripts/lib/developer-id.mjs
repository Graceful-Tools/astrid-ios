// Which Developer ID Application certificate a direct-download profile should be built on (AITD-447).
//
// Apple's original Developer ID Sub-CA expires 2027-02-01, and every certificate it issued with it.
// Replacements come from the G2 Sub-CA, and the App Store Connect API types those
// DEVELOPER_ID_APPLICATION_G2 — so a lookup for DEVELOPER_ID_APPLICATION alone finds only the old
// one, or nothing once it is revoked. While both exist, the one that expires last is the one to use.

import { createHash } from 'node:crypto';

export const DEVELOPER_ID_TYPES = ['DEVELOPER_ID_APPLICATION', 'DEVELOPER_ID_APPLICATION_G2'];

/** The newest usable Developer ID Application certificate in an ASC `/v1/certificates` list, or null. */
export function pickDeveloperIdCert(certificates, now = new Date()) {
  const expires = c => new Date(c.attributes.expirationDate ?? 0).getTime();
  return (certificates ?? [])
    .filter(c => DEVELOPER_ID_TYPES.includes(c.attributes?.certificateType))
    .filter(c => expires(c) > now.getTime())
    .sort((a, b) => expires(b) - expires(a))[0] ?? null;
}

/** Match the profile's certificate to an installed, valid Developer ID signing identity. */
export function findProfileSigningIdentity(certificate, teamId, identities) {
  if (!Buffer.isBuffer(certificate) || certificate.length === 0 || !/^[A-Z0-9]{10}$/.test(teamId)) {
    throw new Error('The provisioning profile is missing its signing certificate or team ID');
  }
  const fingerprint = createHash('sha1').update(certificate).digest('hex').toUpperCase();
  const matches = identities.split('\n').some(line => {
    const identity = line.match(/^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"Developer ID Application: .+ \(([A-Z0-9]{10})\)"\s*$/);
    return identity && identity[1].toUpperCase() === fingerprint && identity[2] === teamId;
  });
  if (!matches) {
    throw new Error(`No valid installed Developer ID signing identity matches the provisioning profile (${fingerprint}, team ${teamId})`);
  }
  return fingerprint;
}
