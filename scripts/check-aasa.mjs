#!/usr/bin/env node
// check-aasa.mjs — does a partner's server name the partner's app for passkeys and links? (ADEV-107)
//
//   node scripts/check-aasa.mjs --host tasks.acme.example --app-id ABCDE12345.com.acme.tasks [--profile acme]
//
// Fetches https://<host>/.well-known/apple-app-site-association the way Apple does — HTTPS, no
// redirect, JSON — and checks <app-id> is listed under webcredentials and applinks. --profile (a
// path, or a name in ${ASTRID_WEB_DIR:-../astrid-web}/brands/) also checks the profile's own
// BRAND_APPLE_APP_IDS. --file reads a saved document instead of the network (tests).
//
// Exit 0: named. 1: not named, or the file is unusable. 2: usage. 3: the host could not be reached.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { APP_ID_PATTERN, checkAssociation, checkProfileAppIds } from './lib/apple-app-site-association.mjs';

const args = process.argv.slice(2);
const opt = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const host = opt('--host'), appId = opt('--app-id'), file = opt('--file'), profile = opt('--profile');
const usage = msg => { console.error(`${msg}\nUsage: node scripts/check-aasa.mjs --host <host> --app-id <TEAMID>.<bundle id> [--profile <name|path>]`); process.exit(2); };
if (!host || !appId) usage('--host and --app-id are required.');
if (!APP_ID_PATTERN.test(appId)) usage(`--app-id ${appId} is not <TEAM ID>.<bundle id>.`);

const url = `https://${host}/.well-known/apple-app-site-association`;
const problems = [];

let body;
if (file) {
  body = readFileSync(file, 'utf8');
} else {
  let response;
  try {
    response = await fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(15000) });
  } catch (error) {
    console.log(`✗ Could not reach ${url}: ${error.cause?.message ?? error.message}`);
    process.exit(3);
  }
  if (response.status >= 300 && response.status < 400) {
    problems.push(`${url} redirects (${response.status} to ${response.headers.get('location')}); Apple does not follow redirects for this file`);
  } else if (!response.ok) {
    problems.push(`${url} answered ${response.status}`);
  } else {
    body = await response.text();
  }
}

if (body !== undefined) {
  let doc;
  try { doc = JSON.parse(body); } catch { problems.push(`${url} is not JSON — is the host an astrid-web deployment?`); }
  if (doc) problems.push(...checkAssociation(doc, appId).problems);
}

if (profile) {
  const web = process.env.ASTRID_WEB_DIR || join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'astrid-web');
  const path = existsSync(profile) ? resolve(profile) : join(web, 'brands', `${profile}.brand.json`);
  if (existsSync(path)) {
    const value = JSON.parse(readFileSync(path, 'utf8'))?.env?.BRAND_APPLE_APP_IDS;
    const { ok, ids } = checkProfileAppIds(value, appId);
    if (!ok) {
      problems.push(`the profile's BRAND_APPLE_APP_IDS (${ids.join(', ') || 'unset'}) does not include ${appId}. ` +
        'The variant builds the iOS and Mac apps as ONE bundle id, so list exactly that, then redeploy the server from the profile');
    }
  } else {
    console.log(`  (profile ${profile} not found, so its BRAND_APPLE_APP_IDS was not checked)`);
  }
}

if (problems.length) {
  console.log(`✗ ${host} does not name ${appId} correctly:`);
  for (const p of problems) console.log(`  - ${p}`);
  process.exit(1);
}
console.log(`✓ ${host} names ${appId} for passkeys and links`);
