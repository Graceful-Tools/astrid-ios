// node --test scripts/test-check-aasa.mjs — a partner's server must name the partner's app (ADEV-107).
//
// With BRAND_APPLE_APP_IDS unset, a partner deployment serves Astrid's own association file, and
// passkeys and universal links in the partner's app fail without a word. Nothing checked it.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkAssociation, checkProfileAppIds } from './lib/apple-app-site-association.mjs';

const ACME = 'ABCDE12345.com.acme.tasks';
const paths = ['/s/*', '/tasks/*', '/lists/*'];
const partnerDoc = ids => ({
  webcredentials: { apps: ids },
  applinks: { apps: [], details: ids.map(appID => ({ appID, paths })) },
});
// What astrid-web serves with BRAND_APPLE_APP_IDS unset (lib/brand/apple-app-site-association.ts).
const astridDoc = {
  webcredentials: { apps: ['34K3P7PD2W.Graceful-Tools-Inc.Astrid-App', '34K3P7PD2W.Graceful-Tools-Inc.Astrid-Mac', '34K3P7PD2W.Graceful-Tools-Inc.Whitelabel'] },
  applinks: { apps: [], details: [
    { appID: '34K3P7PD2W.Graceful-Tools-Inc.Astrid-App', paths },
    { appID: '34K3P7PD2W.Graceful-Tools-Inc.Whitelabel', paths },
  ] },
};

test('ADEV-107: the association passes only when it names the app for passkeys AND links', () => {
  assert.deepEqual(checkAssociation(partnerDoc([ACME]), ACME).problems, []);
  // The newer `appIDs` array form counts too.
  assert.deepEqual(checkAssociation({ webcredentials: { apps: [ACME] }, applinks: { details: [{ appIDs: [ACME] }] } }, ACME).problems, []);

  const linksOnly = checkAssociation({ applinks: { details: [{ appID: ACME }] } }, ACME);
  assert.equal(linksOnly.problems.length, 1);
  assert.match(linksOnly.problems[0], /webcredentials.*passkeys/);
});

test('ADEV-107: Astrid\'s default file is called out as an unset BRAND_APPLE_APP_IDS', () => {
  const result = checkAssociation(astridDoc, ACME);
  assert.equal(result.servesAstridDefault, true);
  assert.match(result.problems.join('\n'), /BRAND_APPLE_APP_IDS is unset/);
  // Graceful Tools' own Whitelabel app IS in the default file.
  assert.deepEqual(checkAssociation(astridDoc, '34K3P7PD2W.Graceful-Tools-Inc.Whitelabel').problems, []);
});

test('ADEV-107: a profile whose BRAND_APPLE_APP_IDS misses the variant\'s one bundle id is caught', () => {
  // acme.brand.json lists separate iOS and Mac ids; the variant builds both apps as one bundle id.
  const acme = checkProfileAppIds('ACME000001.example.acme.Tasks,ACME000001.example.acme.TasksMac', 'ACME000001.example.acme.Tasks');
  assert.deepEqual(acme, { ok: true, ids: ['ACME000001.example.acme.Tasks', 'ACME000001.example.acme.TasksMac'] });
  const wrongTeam = checkProfileAppIds('ACME000001.example.acme.Tasks', 'ZZZZZ00000.example.acme.Tasks');
  assert.equal(wrongTeam.ok, false);
  assert.equal(checkProfileAppIds(undefined, ACME).ok, false);
});

test('ADEV-107: the CLI exits non-zero on a mismatch and names the fix', t => {
  const dir = mkdtempSync(join(tmpdir(), 'astrid-aasa-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const cli = fileURLToPath(new URL('./check-aasa.mjs', import.meta.url));
  const write = (name, value) => { const p = join(dir, name); writeFileSync(p, typeof value === 'string' ? value : JSON.stringify(value)); return p; };
  const run = (...args) => spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8', env: { ...process.env, ASTRID_WEB_DIR: join(dir, 'no-web') } });

  const good = run('--app-id', ACME, '--host', 'tasks.acme.example', '--file', write('good.json', partnerDoc([ACME])));
  assert.equal(good.status, 0, good.stdout + good.stderr);
  assert.match(good.stdout, /tasks\.acme\.example .*ABCDE12345\.com\.acme\.tasks/);

  const astrid = run('--app-id', ACME, '--host', 'tasks.acme.example', '--file', write('astrid.json', astridDoc));
  assert.equal(astrid.status, 1);
  assert.match(astrid.stdout, /BRAND_APPLE_APP_IDS is unset/);

  const profile = write('acme.brand.json', { env: { BRAND_APPLE_APP_IDS: 'ABCDE12345.com.acme.tasks.Mac' } });
  const badProfile = run('--app-id', ACME, '--host', 'tasks.acme.example', '--file', write('good2.json', partnerDoc([ACME])), '--profile', profile);
  assert.equal(badProfile.status, 1);
  assert.match(badProfile.stdout, /profile's BRAND_APPLE_APP_IDS .*does not include ABCDE12345\.com\.acme\.tasks/);

  const notJson = run('--app-id', ACME, '--host', 'tasks.acme.example', '--file', write('html.json', '<html>'));
  assert.equal(notJson.status, 1);
  assert.match(notJson.stdout, /not JSON/);

  assert.equal(run('--host', 'x').status, 2);
  assert.equal(run('--app-id', 'no-team', '--host', 'x').status, 2);
});
