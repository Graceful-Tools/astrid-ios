// asc-jwt.mjs — App Store Connect credentials and request signing, shared by asc-appstore.mjs,
// mac-ci-build.mjs and mac-devid-profile.mjs.
//
// Extracted because all three carried the same `pick` / `jwt` / `api` trio (2026-09-13 dedupe
// review), and only one of them validated that the key was present — the other two would
// `.replace()` on `undefined` and die with a stack trace instead of a sentence.
//
// Reads APPLE_ASC_KEY_ID / APPLE_ASC_ISSUER_ID / APPLE_ASC_PRIVATE_KEY from .env.local, or from
// the file named by ASC_ENV_FILE (check-version.sh and its self-test point both halves at one
// file). Nothing here prints a secret.
import crypto from 'crypto';
import fs from 'fs';

const ROOT = new URL('../..', import.meta.url).pathname;
const ENV_FILE = process.env.ASC_ENV_FILE || ROOT + '.env.local';
const env = fs.readFileSync(ENV_FILE, 'utf8');

/** One value from .env.local, unquoted. Anchored on the KEY= prefix, never on content. */
export const pick = k => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1]?.replace(/^["']|["']$/g, '');

/** A fresh 15-minute ES256 bearer token for the App Store Connect API. */
export const jwt = () => {
  // Match on the APPLE_ASC_PRIVATE_KEY= prefix, not the first PEM block in the file — .env.local
  // holds other private keys and grabbing the wrong one fails ES256 signing with "invalid digest".
  const key = pick('APPLE_ASC_PRIVATE_KEY')?.replace(/\\n/g, '\n');
  if (!key) throw new Error(`APPLE_ASC_PRIVATE_KEY missing from ${ENV_FILE}`);
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const unsigned = b64({ alg: 'ES256', kid: pick('APPLE_ASC_KEY_ID'), typ: 'JWT' }) + '.' +
    b64({ iss: pick('APPLE_ASC_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1' });
  return unsigned + '.' + crypto.sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
};

/** One authenticated request. Returns `{ status, body }`; callers decide what a non-2xx means. */
export const ascRequest = async (path, opts = {}) => {
  const r = await fetch('https://api.appstoreconnect.apple.com' + path, {
    ...opts,
    headers: { Authorization: 'Bearer ' + jwt(), 'Content-Type': 'application/json', ...(opts.headers || {}) },
  });
  const text = await r.text();
  return { status: r.status, body: text ? JSON.parse(text) : null };
};
