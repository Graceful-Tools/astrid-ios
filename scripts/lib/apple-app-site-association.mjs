// Does a deployment's apple-app-site-association name this app? (ADEV-107)
//
// A partner app's passkeys (`webcredentials`) and universal links (`applinks`) work only when the
// server it is compiled against lists `<TEAM ID>.<bundle id>`. astrid-web builds that file from
// BRAND_APPLE_APP_IDS; unset, it serves Astrid's own ids, and the partner's passkeys fail with no
// error anywhere. Nothing cross-checked the two until this.

/** Astrid's team id: a file listing only its apps is astrid-web's default, BRAND_APPLE_APP_IDS unset. */
const ASTRID_TEAM = '34K3P7PD2W';

export const APP_ID_PATTERN = /^[A-Z0-9]{10}\.[A-Za-z0-9.-]+$/;

const list = value => (Array.isArray(value) ? value.filter(v => typeof v === 'string') : []);

/** The app ids a document lists for passkeys and for links. */
export function associationIds(doc) {
  const passkeys = list(doc?.webcredentials?.apps);
  const links = [
    ...list(doc?.applinks?.apps),
    ...(Array.isArray(doc?.applinks?.details) ? doc.applinks.details : []).flatMap(d =>
      [...(typeof d?.appID === 'string' ? [d.appID] : []), ...list(d?.appIDs)]),
  ];
  return { passkeys, links };
}

/** `{ problems: string[], servesAstridDefault }` — no problems means the app is named for both. */
export function checkAssociation(doc, appId) {
  const { passkeys, links } = associationIds(doc);
  const all = [...passkeys, ...links];
  const servesAstridDefault = all.length > 0 && all.every(id => id.startsWith(`${ASTRID_TEAM}.`));
  const problems = [];
  if (!passkeys.includes(appId)) problems.push(`webcredentials.apps does not list ${appId}: passkeys will not offer themselves in the app`);
  if (!links.includes(appId)) problems.push(`applinks does not list ${appId}: shared task and list links will open in the browser`);
  if (problems.length && servesAstridDefault && !appId.startsWith(`${ASTRID_TEAM}.`)) {
    problems.push('the file lists only Astrid\'s own apps, so BRAND_APPLE_APP_IDS is unset on the deployment. Set it to ' +
      `${appId} (comma-separated, with any other apps) and redeploy`);
  }
  return { problems, servesAstridDefault, passkeys, links };
}

/** The profile's own BRAND_APPLE_APP_IDS, which the deployment is configured from. */
export function checkProfileAppIds(value, appId) {
  const ids = String(value ?? '').split(',').map(s => s.trim()).filter(Boolean);
  return { ok: ids.includes(appId), ids };
}
