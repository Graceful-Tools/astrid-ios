// node --test scripts/test-developer-id.mjs — the certificate choice behind mac-devid-profile.mjs (AITD-447).
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { findProfileSigningIdentity, pickDeveloperIdCert } from './lib/developer-id.mjs';

const cert = (id, certificateType, expirationDate) => ({ id, attributes: { certificateType, expirationDate } });
const now = new Date('2026-10-25T00:00:00Z');

test('a G2 replacement is found — the API types it DEVELOPER_ID_APPLICATION_G2', () => {
  const picked = pickDeveloperIdCert([cert('g2', 'DEVELOPER_ID_APPLICATION_G2', '2027-10-25T00:00:00Z')], now);
  assert.equal(picked?.id, 'g2');
});

test('with both, the one that expires last wins over the old Sub-CA certificate', () => {
  const picked = pickDeveloperIdCert([
    cert('old', 'DEVELOPER_ID_APPLICATION', '2027-02-01T22:12:00Z'),
    cert('g2', 'DEVELOPER_ID_APPLICATION_G2', '2027-10-25T00:00:00Z'),
  ], now);
  assert.equal(picked?.id, 'g2');
});

test('other certificate types and expired certificates are never picked', () => {
  assert.equal(pickDeveloperIdCert([
    cert('dist', 'DISTRIBUTION', '2027-10-25T00:00:00Z'),
    cert('gone', 'DEVELOPER_ID_APPLICATION', '2026-01-01T00:00:00Z'),
  ], now), null);
  assert.equal(pickDeveloperIdCert(undefined, now), null);
});

const profileCertificate = Buffer.from('AITD-447 replacement certificate');
const profileFingerprint = createHash('sha1').update(profileCertificate).digest('hex').toUpperCase();
const teamId = '34K3P7PD2W';
const identityName = `Developer ID Application: Graceful Tools LLC (${teamId})`;
const identities = [
  `  1) ${'A'.repeat(40)} "${identityName}"`,
  `  2) ${profileFingerprint} "${identityName}"`,
  '     2 valid identities found',
].join('\n');

test('AITD-447: select the profile certificate by fingerprint when names are identical', () => {
  assert.equal(
    findProfileSigningIdentity(profileCertificate, teamId, identities),
    profileFingerprint,
  );
});

test('AITD-447: fail if the profile certificate has no installed private-key identity', () => {
  assert.throws(
    () => findProfileSigningIdentity(profileCertificate, teamId, identities.replace(profileFingerprint, 'B'.repeat(40))),
    /No valid installed Developer ID signing identity matches/,
  );
});

test('AITD-447: reject an identity for a different team or certificate type', () => {
  assert.throws(
    () => findProfileSigningIdentity(profileCertificate, 'OTHERTEAM1', identities),
    /No valid installed Developer ID signing identity matches/,
  );
  assert.throws(
    () => findProfileSigningIdentity(profileCertificate, teamId, identities.replaceAll('Developer ID Application', 'Apple Distribution')),
    /No valid installed Developer ID signing identity matches/,
  );
});

test('AITD-447: the profile identity command returns only the matching fingerprint and team', t => {
  const dir = mkdtempSync(join(tmpdir(), 'astrid-devid-identity-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, 'security'), `#!/bin/sh
case "$1" in
  cms) printf '<plist/>' ;;
  find-identity) printf '%s\\n' "$MOCK_IDENTITIES" ;;
  *) exit 1 ;;
esac
`, { mode: 0o755 });
  writeFileSync(join(dir, 'plutil'), `#!/bin/sh
cat >/dev/null
case "$2" in
  DeveloperCertificates.0) printf '%s\\n' "$MOCK_CERTIFICATE" ;;
  TeamIdentifier.0) printf '%s\\n' "$MOCK_TEAM" ;;
  *) exit 1 ;;
esac
`, { mode: 0o755 });
  const script = fileURLToPath(new URL('./mac-devid-identity.mjs', import.meta.url));
  const env = {
    ...process.env,
    PATH: `${dir}:${process.env.PATH}`,
    MOCK_CERTIFICATE: profileCertificate.toString('base64'),
    MOCK_TEAM: teamId,
    MOCK_IDENTITIES: identities,
  };
  const run = spawnSync(process.execPath, [script, 'profile.provisionprofile'], { env, encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stdout.trim(), `${profileFingerprint} ${teamId}`);

  const missing = spawnSync(process.execPath, [script, 'profile.provisionprofile'], {
    env: { ...env, MOCK_IDENTITIES: identities.replace(profileFingerprint, 'B'.repeat(40)) },
    encoding: 'utf8',
  });
  assert.equal(missing.status, 1);
  assert.match(missing.stderr, /No valid installed Developer ID signing identity matches/);
});

test('AITD-447: profile recreation keeps --print-path output machine-readable', t => {
  const dir = mkdtempSync(join(tmpdir(), 'astrid-devid-profile-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const privateKey = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey
    .export({ type: 'pkcs8', format: 'pem' }).replaceAll('\n', '\\n');
  const envFile = join(dir, 'asc.env');
  writeFileSync(envFile, `APPLE_ASC_KEY_ID=test\nAPPLE_ASC_ISSUER_ID=test\nAPPLE_ASC_PRIVATE_KEY="${privateKey}"\n`, { mode: 0o600 });
  const mock = join(dir, 'mock-asc.mjs');
  writeFileSync(mock, `
globalThis.fetch = async (url, options = {}) => {
  const path = new URL(url).pathname;
  const json = (data, status = 200) => new Response(JSON.stringify(data), { status });
  if (path === '/v1/certificates') return json({ data: [{ id: 'new-cert', attributes: { certificateType: 'DEVELOPER_ID_APPLICATION_G2', expirationDate: '2099-01-01T00:00:00Z' } }] });
  if (path === '/v1/profiles' && !options.method) return json({ data: [{ id: 'old-profile', attributes: { name: 'Astrid Mac Developer ID', profileState: 'ACTIVE' } }] });
  if (path === '/v1/profiles/old-profile/certificates') return json({ data: [{ id: 'old-cert' }] });
  if (path === '/v1/profiles/old-profile' && options.method === 'DELETE') return new Response(null, { status: 204 });
  if (path === '/v1/bundleIds') return json({ data: [{ id: 'bundle', attributes: { identifier: 'Graceful-Tools-Inc.Astrid-App' } }] });
  if (path === '/v1/profiles' && options.method === 'POST') return json({ data: { id: 'new-profile', attributes: { name: 'Astrid Mac Developer ID', profileState: 'ACTIVE', uuid: '7bba23d7-553e-42b0-aa64-2f98b596a04a', profileContent: 'cHJvZmlsZQ==' } } }, 201);
  throw new Error('Unexpected mocked ASC request: ' + path);
};
`);
  const script = fileURLToPath(new URL('./mac-devid-profile.mjs', import.meta.url));
  const run = spawnSync(process.execPath, ['--import', mock, script, '--recreate', '--print-path'], {
    env: { ...process.env, HOME: dir, ASC_ENV_FILE: envFile, NODE_OPTIONS: '' },
    encoding: 'utf8',
  });
  const legacyProfilePath = join(dir, 'Library/MobileDevice/Provisioning Profiles/new-profile.provisionprofile');
  const profilePath = join(dir, 'Library/Developer/Xcode/UserData/Provisioning Profiles/7bba23d7-553e-42b0-aa64-2f98b596a04a.provisionprofile');
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stdout.trim(), profilePath);
  assert.equal(readFileSync(profilePath, 'utf8'), 'profile');
  assert.equal(readFileSync(legacyProfilePath, 'utf8'), 'profile');
  assert.match(run.stderr, /Deleted the old "Astrid Mac Developer ID" profile/);
  assert.match(run.stderr, /Profile "Astrid Mac Developer ID"/);

  writeFileSync(mock, readFileSync(mock, 'utf8').replace(
    "uuid: '7bba23d7-553e-42b0-aa64-2f98b596a04a'",
    "uuid: '../invalid'",
  ));
  const invalid = spawnSync(process.execPath, ['--import', mock, script, '--recreate', '--print-path'], {
    env: { ...process.env, HOME: dir, ASC_ENV_FILE: envFile, NODE_OPTIONS: '' },
    encoding: 'utf8',
  });
  assert.notEqual(invalid.status, 0);
  assert.match(invalid.stderr, /did not return a valid UUID/);
});

test('AITD-447: Mac packaging exports and signs with the exact profile and identity', t => {
  const dir = mkdtempSync(join(tmpdir(), 'astrid-package-mac-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const scriptsDir = join(dir, 'scripts');
  const binDir = join(dir, 'bin');
  mkdirSync(scriptsDir);
  mkdirSync(binDir);
  copyFileSync(fileURLToPath(new URL('./package-mac.sh', import.meta.url)), join(scriptsDir, 'package-mac.sh'));
  const credentials = join(dir, 'asc-credentials.env');
  writeFileSync(credentials, [
    "APPLE_ASC_PRIVATE_KEY='mock-private-line-1\\nmock-private-line-2'",
    "APPLE_ASC_KEY_ID='mock-key-id'",
    "APPLE_ASC_ISSUER_ID='mock-issuer-id'",
    '',
  ].join('\n'));

  const commands = {
    security: `printf '%s\\n' '  1) ${'A'.repeat(40)} "${identityName}"' '  2) ${profileFingerprint} "${identityName}"'`,
    node: `case "$1" in
      scripts/mac-devid-profile.mjs) [ "$2" = "--print-path" ] && printf '%s\\n' "$MOCK_PROFILE" ;;
      scripts/mac-devid-identity.mjs) [ "$2" = "$MOCK_PROFILE" ] && printf '%s %s\\n' "$MOCK_FINGERPRINT" "$MOCK_TEAM" ;;
      *) exit 1 ;;
    esac`,
    xcodebuild: `case "$1" in
      -scheme) printf '    MARKETING_VERSION = 1.0\\n    CURRENT_PROJECT_VERSION = 1\\n    FULL_PRODUCT_NAME = Astrid.app\\n' ;;
      archive) printf '%s\\n' "$@" > "$MOCK_ARCHIVE_ARGS" ;;
      -exportArchive) mkdir -p build/export/Astrid.app ;;
      *) exit 1 ;;
    esac`,
    ditto: 'touch "$5"',
    xcrun: `if [ "$1" = "notarytool" ]; then
      cat build/.asc-key.p8 >> "$MOCK_NOTARY_KEY"
      printf '%s\\n' "$@" >> "$MOCK_NOTARY_ARGS"
    fi`,
    hdiutil: 'touch "$9"',
    codesign: 'printf "%s\\n" "$@" >> "$MOCK_CODESIGN_ARGS"',
    spctl: 'exit 0',
  };
  for (const [command, body] of Object.entries(commands)) {
    writeFileSync(join(binDir, command), `#!/bin/sh\n${body}\n`, { mode: 0o755 });
  }
  const uuid = '7bba23d7-553e-42b0-aa64-2f98b596a04a';
  const env = {
    ...process.env,
    PATH: `${binDir}:${process.env.PATH}`,
    MOCK_PROFILE: join(dir, `${uuid}.provisionprofile`),
    MOCK_FINGERPRINT: profileFingerprint,
    MOCK_TEAM: teamId,
    MOCK_ARCHIVE_ARGS: join(dir, 'archive-args'),
    MOCK_CODESIGN_ARGS: join(dir, 'codesign-args'),
    MOCK_NOTARY_ARGS: join(dir, 'notary-args'),
    MOCK_NOTARY_KEY: join(dir, 'notary-key'),
    ASC_ENV_FILE: credentials,
    SKIP_NOTARIZE: '0',
  };
  const run = spawnSync('/bin/bash', [join(scriptsDir, 'package-mac.sh')], { cwd: dir, env, encoding: 'utf8' });
  assert.equal(run.status, 0, `${run.stdout}\n${run.stderr}`);
  const options = readFileSync(join(dir, 'build/ExportOptions.plist'), 'utf8');
  assert.ok(options.includes(`<key>signingCertificate</key><string>${profileFingerprint}</string>`));
  assert.ok(options.includes(`<key>Graceful-Tools-Inc.Astrid-App</key><string>${uuid}</string>`));
  assert.match(readFileSync(env.MOCK_ARCHIVE_ARGS, 'utf8'), new RegExp(`DEVELOPMENT_TEAM=${teamId}`));
  assert.match(readFileSync(env.MOCK_CODESIGN_ARGS, 'utf8'), new RegExp(`--sign\\n${profileFingerprint}\\n--timestamp`));
  assert.match(readFileSync(env.MOCK_NOTARY_ARGS, 'utf8'), /--key-id\nmock-key-id\n--issuer\nmock-issuer-id/);
  assert.equal(readFileSync(env.MOCK_NOTARY_KEY, 'utf8'), 'mock-private-line-1\nmock-private-line-2\n'.repeat(2));
  assert.equal(existsSync(join(dir, 'build/.asc-key.p8')), false);
});
