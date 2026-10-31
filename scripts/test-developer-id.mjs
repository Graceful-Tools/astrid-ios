// node --test scripts/test-developer-id.mjs — the certificate choice behind mac-devid-profile.mjs (AITD-447).
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, X509Certificate } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
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

const certificateDir = mkdtempSync(join(tmpdir(), 'astrid-devid-certificates-'));
after(() => rmSync(certificateDir, { recursive: true, force: true }));
const makeCertificate = (name, days) => {
  const certificatePath = join(certificateDir, `${name}.pem`);
  const result = spawnSync('openssl', [
    'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', String(days),
    '-subj', `/CN=AITD-447 ${name}`, '-keyout', join(certificateDir, `${name}-key.pem`),
    '-out', certificatePath,
  ], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return new X509Certificate(readFileSync(certificatePath)).raw;
};
const oldCertificate = makeCertificate('old', 30);
const profileCertificate = makeCertificate('replacement', 365);
const oldFingerprint = createHash('sha1').update(oldCertificate).digest('hex').toUpperCase();
const profileFingerprint = createHash('sha1').update(profileCertificate).digest('hex').toUpperCase();
const teamId = '34K3P7PD2W';
const identityName = `Developer ID Application: Graceful Tools LLC (${teamId})`;
const identities = [
  `  1) ${oldFingerprint} "${identityName}"`,
  `  2) ${profileFingerprint} "${identityName}"`,
  '     2 valid identities found',
].join('\n');

test('AITD-447: select the profile certificate by fingerprint when names are identical', () => {
  assert.equal(
    findProfileSigningIdentity([profileCertificate], teamId, identities),
    profileFingerprint,
  );
});

test('AITD-447: select the newest profile certificate regardless of its position', () => {
  for (const certificates of [[oldCertificate, profileCertificate], [profileCertificate, oldCertificate]]) {
    assert.equal(findProfileSigningIdentity(certificates, teamId, identities), profileFingerprint);
  }
});

test('AITD-447: fail if the profile certificate has no installed private-key identity', () => {
  assert.throws(
    () => findProfileSigningIdentity([profileCertificate], teamId, identities.replace(profileFingerprint, 'B'.repeat(40))),
    /No valid installed Developer ID signing identity matches/,
  );
});

test('AITD-447: do not fall back to an older identity when the newest private key is missing', () => {
  assert.throws(
    () => findProfileSigningIdentity([oldCertificate, profileCertificate], teamId, identities.replace(profileFingerprint, 'B'.repeat(40))),
    /No valid installed Developer ID signing identity matches/,
  );
});

test('AITD-447: reject an identity for a different team or certificate type', () => {
  assert.throws(
    () => findProfileSigningIdentity([profileCertificate], 'OTHERTEAM1', identities),
    /No valid installed Developer ID signing identity matches/,
  );
  assert.throws(
    () => findProfileSigningIdentity([profileCertificate], teamId, identities.replaceAll('Developer ID Application', 'Apple Distribution')),
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
  DeveloperCertificates) printf '2\\n' ;;
  DeveloperCertificates.0) printf '%s\\n' "$MOCK_OLD_CERTIFICATE" ;;
  DeveloperCertificates.1) printf '%s\\n' "$MOCK_CERTIFICATE" ;;
  TeamIdentifier.0) printf '%s\\n' "$MOCK_TEAM" ;;
  *) exit 1 ;;
esac
`, { mode: 0o755 });
  const script = fileURLToPath(new URL('./mac-devid-identity.mjs', import.meta.url));
  const env = {
    ...process.env,
    PATH: `${dir}:${process.env.PATH}`,
    MOCK_OLD_CERTIFICATE: oldCertificate.toString('base64'),
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
  const dir = realpathSync(mkdtempSync(join(tmpdir(), 'astrid-package-mac-')));
  const keyTempDir = realpathSync(mkdtempSync(join(tmpdir(), 'astrid-package-mac-keys-')));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  t.after(() => rmSync(keyTempDir, { recursive: true, force: true }));
  const scriptsDir = join(dir, 'scripts');
  const binDir = join(dir, 'bin');
  mkdirSync(scriptsDir);
  mkdirSync(binDir);
  copyFileSync(fileURLToPath(new URL('./package-mac.sh', import.meta.url)), join(scriptsDir, 'package-mac.sh'));
  const credentials = join(keyTempDir, 'asc-credentials.env');
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
      previous=
      for arg in "$@"; do
        if [ "$previous" = "--key" ]; then
          printf '%s\\n' "$arg" >> "$MOCK_NOTARY_PATHS"
          perl -e 'printf "%o\\n", (stat($ARGV[0]))[2] & 0777' "$arg" >> "$MOCK_NOTARY_MODES"
          perl -e 'printf "%o\\n", (stat($ARGV[0]))[2] & 0777' "$(dirname "$arg")" >> "$MOCK_NOTARY_DIR_MODES"
          cat "$arg" >> "$MOCK_NOTARY_KEY"
        fi
        previous="$arg"
      done
      printf '%s\\n' "$@" >> "$MOCK_NOTARY_ARGS"
      [ "\${MOCK_NOTARY_FAIL:-0}" != 1 ] || exit 1
    fi`,
    hdiutil: 'touch "$9"',
    codesign: 'printf "%s\\n" "$@" >> "$MOCK_CODESIGN_ARGS"',
    spctl: 'exit 0',
    rm: `if [ "$1" = "-rf" ]; then exit 0; fi
      [ "$1" = "-f" ] || exit 1
      shift
      [ "\${1:-}" = "--" ] && shift
      for path in "$@"; do
        case "$path" in
          "$MOCK_REPO"/build/*|"$MOCK_KEY_TMP"/*)
            [ ! -e "$path" ] || /bin/unlink "$path" ;;
          *) exit 1 ;;
        esac
      done`,
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
    MOCK_NOTARY_PATHS: join(dir, 'notary-paths'),
    MOCK_NOTARY_MODES: join(dir, 'notary-modes'),
    MOCK_NOTARY_DIR_MODES: join(dir, 'notary-dir-modes'),
    MOCK_REPO: dir,
    MOCK_KEY_TMP: keyTempDir,
    TMPDIR: keyTempDir,
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
  const keyPaths = readFileSync(env.MOCK_NOTARY_PATHS, 'utf8').trim().split('\n');
  assert.equal(keyPaths.length, 2);
  assert.ok(keyPaths.every(path => path.startsWith(`${keyTempDir}/`) && !path.startsWith(`${dir}/`)));
  assert.deepEqual(readFileSync(env.MOCK_NOTARY_MODES, 'utf8').trim().split('\n'), ['600', '600']);
  assert.deepEqual(readFileSync(env.MOCK_NOTARY_DIR_MODES, 'utf8').trim().split('\n'), ['700', '700']);
  assert.ok(keyPaths.every(path => !existsSync(path)));

  const unsafeTempDir = join(dir, 'unsafe-temp');
  mkdirSync(unsafeTempDir);
  const unsafe = spawnSync('/bin/bash', [join(scriptsDir, 'package-mac.sh')], {
    cwd: dir,
    env: { ...env, TMPDIR: unsafeTempDir },
    encoding: 'utf8',
  });
  assert.notEqual(unsafe.status, 0);
  assert.match(`${unsafe.stdout}\n${unsafe.stderr}`, /temporary directory.*inside.*repository/i);
  assert.deepEqual(readdirSync(unsafeTempDir), []);

  const unsafeTempLink = join(keyTempDir, 'inside-repo');
  symlinkSync(unsafeTempDir, unsafeTempLink);
  const linkedTemp = spawnSync('/bin/bash', [join(scriptsDir, 'package-mac.sh')], {
    cwd: dir,
    env: { ...env, TMPDIR: unsafeTempLink },
    encoding: 'utf8',
  });
  assert.notEqual(linkedTemp.status, 0);
  assert.match(`${linkedTemp.stdout}\n${linkedTemp.stderr}`, /temporary directory.*inside.*repository/i);
  assert.deepEqual(readdirSync(unsafeTempDir), []);

  const unsafeCredentials = join(dir, '.env.local');
  copyFileSync(credentials, unsafeCredentials);
  const inside = spawnSync('/bin/bash', [join(scriptsDir, 'package-mac.sh')], {
    cwd: dir,
    env: { ...env, ASC_ENV_FILE: '' },
    encoding: 'utf8',
  });
  assert.notEqual(inside.status, 0);
  assert.match(`${inside.stdout}\n${inside.stderr}`, /credentials.*outside.*repository/i);

  const unsafeCredentialsLink = join(keyTempDir, 'inside-repo.env');
  symlinkSync(unsafeCredentials, unsafeCredentialsLink);
  const linkedCredentials = spawnSync('/bin/bash', [join(scriptsDir, 'package-mac.sh')], {
    cwd: dir,
    env: { ...env, ASC_ENV_FILE: unsafeCredentialsLink },
    encoding: 'utf8',
  });
  assert.notEqual(linkedCredentials.status, 0);
  assert.match(`${linkedCredentials.stdout}\n${linkedCredentials.stderr}`, /credentials.*outside.*repository/i);

  const failedPaths = join(dir, 'failed-notary-paths');
  const failed = spawnSync('/bin/bash', [join(scriptsDir, 'package-mac.sh')], {
    cwd: dir,
    env: { ...env, MOCK_NOTARY_FAIL: '1', MOCK_NOTARY_PATHS: failedPaths },
    encoding: 'utf8',
  });
  assert.notEqual(failed.status, 0);
  const failedKey = readFileSync(failedPaths, 'utf8').trim();
  assert.ok(failedKey.startsWith(`${keyTempDir}/`));
  assert.equal(existsSync(failedKey), false);
  assert.equal(existsSync(join(failedKey, '..')), false);

  const missingKey = join(keyTempDir, 'missing-key.env');
  writeFileSync(missingKey, 'APPLE_ASC_KEY_ID=mock-key-id\nAPPLE_ASC_ISSUER_ID=mock-issuer-id\n');
  const incomplete = spawnSync('/bin/bash', [join(scriptsDir, 'package-mac.sh')], {
    cwd: dir,
    env: { ...env, ASC_ENV_FILE: missingKey },
    encoding: 'utf8',
  });
  assert.notEqual(incomplete.status, 0);
  assert.match(incomplete.stderr, /APPLE_ASC_PRIVATE_KEY is missing/);
  assert.ok(readdirSync(keyTempDir).every(path => !path.startsWith('astrid-asc.')));
});
