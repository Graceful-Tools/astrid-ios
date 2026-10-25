// Which Developer ID Application certificate a direct-download profile should be built on (AITD-447).
//
// Apple's original Developer ID Sub-CA expires 2027-02-01, and every certificate it issued with it.
// Replacements come from the G2 Sub-CA, and the App Store Connect API types those
// DEVELOPER_ID_APPLICATION_G2 — so a lookup for DEVELOPER_ID_APPLICATION alone finds only the old
// one, or nothing once it is revoked. While both exist, the one that expires last is the one to use.

export const DEVELOPER_ID_TYPES = ['DEVELOPER_ID_APPLICATION', 'DEVELOPER_ID_APPLICATION_G2'];

/** The newest usable Developer ID Application certificate in an ASC `/v1/certificates` list, or null. */
export function pickDeveloperIdCert(certificates, now = new Date()) {
  const expires = c => new Date(c.attributes.expirationDate ?? 0).getTime();
  return (certificates ?? [])
    .filter(c => DEVELOPER_ID_TYPES.includes(c.attributes?.certificateType))
    .filter(c => expires(c) > now.getTime())
    .sort((a, b) => expires(b) - expires(a))[0] ?? null;
}
