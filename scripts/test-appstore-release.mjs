// node --test scripts/test-appstore-release.mjs — Apple credential handling (AITD-447).
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  realpathSync, rmSync, symlinkSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

test('AITD-447: App Store releases keep credentials and temporary keys outside the checkout', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'astrid-appstore-release-')));
  const external = realpathSync(mkdtempSync(join(tmpdir(), 'astrid-appstore-keys-')));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  t.after(() => rmSync(external, { recursive: true, force: true }));
  const scripts = join(root, 'scripts');
  const lib = join(scripts, 'lib');
  const bin = join(root, 'bin');
  mkdirSync(lib, { recursive: true });
  mkdirSync(bin);
  copyFileSync(fileURLToPath(new URL('./appstore-release.sh', import.meta.url)), join(scripts, 'appstore-release.sh'));
  copyFileSync(fileURLToPath(new URL('./lib/asc-key.sh', import.meta.url)), join(lib, 'asc-key.sh'));

  const credentials = join(external, 'asc.env');
  const fixture = [
    "APPLE_ASC_KEY_ID='mock-key-id'",
    "APPLE_ASC_ISSUER_ID='mock-issuer-id'",
    "APPLE_ASC_PRIVATE_KEY='mock-private-line-1\\nmock-private-line-2'",
    "APPLE_APP_STORE_APP_ID='123'",
    '',
  ].join('\n');
  writeFileSync(credentials, fixture, { mode: 0o600 });
  writeFileSync(join(root, '.env.local'), fixture, { mode: 0o600 });
  writeFileSync(join(scripts, 'check-version.sh'), `#!/bin/sh
printf '%s\\n' "\${CHECK_VERSION_ENV_FILE:-}" > "$MOCK_CHECK_ENV"
exit 0
`, { mode: 0o755 });

  const commands = {
    node: `case "$1:$2" in
      scripts/asc-appstore.mjs:next)
        printf '%s\\n' "\${ASC_ENV_FILE:-}" > "$MOCK_ASC_ENV"
        echo 123 ;;
      *) exit 1 ;;
    esac`,
    xcodebuild: `case "$1" in
      -scheme)
        printf '    MARKETING_VERSION = 1.0\\n    CURRENT_PROJECT_VERSION = 1\\n    DEVELOPMENT_TEAM = TESTTEAM\\n' ;;
      archive|-exportArchive)
        action="$1"
        printf '%s\\n' "$@" >> "$MOCK_XCODE_ARGS"
        previous=
        for arg in "$@"; do
          if [ "$previous" = "-authenticationKeyPath" ]; then
            printf '%s\\n' "$arg" >> "$MOCK_KEY_PATHS"
            perl -e 'printf "%o\\n", (stat($ARGV[0]))[2] & 0777' "$arg" >> "$MOCK_KEY_MODES"
            perl -e 'printf "%o\\n", (stat($ARGV[0]))[2] & 0777' "$(dirname "$arg")" >> "$MOCK_KEY_DIR_MODES"
            cat "$arg" >> "$MOCK_KEY_CONTENT"
          fi
          previous="$arg"
        done
        if [ "$action" = "archive" ] && [ "\${MOCK_FAIL_ARCHIVE:-0}" = 1 ]; then
          echo 'mock archive failure'
          exit 1
        fi
        if [ "$action" = "-exportArchive" ]; then
          mkdir -p "$MOCK_ROOT/build/appstore-export-mac"
          touch "$MOCK_ROOT/build/appstore-export-mac/Astrid.pkg"
        fi
        echo 'mock xcodebuild succeeded' ;;
      *) exit 1 ;;
    esac`,
    rm: `if [ "$1" = "-rf" ]; then exit 0; fi
      [ "$1" = "-f" ] || exit 1
      shift
      [ "\${1:-}" = "--" ] && shift
      for path in "$@"; do
        case "$path" in
          "$MOCK_ROOT"/build/*|"$MOCK_KEYS"/*)
            [ "\${MOCK_FAIL_CLEANUP:-0}" != 1 ] || exit 1
            [ ! -e "$path" ] || /bin/unlink "$path" ;;
          *) exit 1 ;;
        esac
      done`,
  };
  for (const [command, body] of Object.entries(commands)) {
    writeFileSync(join(bin, command), `#!/bin/sh\n${body}\n`, { mode: 0o755 });
  }

  const baseEnv = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    TMPDIR: external,
    ASC_ENV_FILE: credentials,
    MOCK_ROOT: root,
    MOCK_KEYS: external,
  };
  const runRelease = (name, overrides = {}, target = 'mac') => {
    const env = {
      ...baseEnv,
      MOCK_KEY_PATHS: join(external, `${name}-paths`),
      MOCK_KEY_MODES: join(external, `${name}-modes`),
      MOCK_KEY_DIR_MODES: join(external, `${name}-dir-modes`),
      MOCK_KEY_CONTENT: join(external, `${name}-content`),
      MOCK_ASC_ENV: join(external, `${name}-asc-env`),
      MOCK_CHECK_ENV: join(external, `${name}-check-env`),
      MOCK_XCODE_ARGS: join(external, `${name}-xcode-args`),
      ...overrides,
    };
    const run = spawnSync('/bin/bash', [join(scripts, 'appstore-release.sh'), target], {
      cwd: root, env, encoding: 'utf8',
    });
    return { run, env };
  };

  const { run, env } = runRelease('success');
  assert.equal(run.status, 0, `${run.stdout}\n${run.stderr}`);
  assert.deepEqual(run.stdout.split('\n').filter(line => line.startsWith('RESULT:')).map(line => line.split(' — ')[0]), ['RESULT: OK']);
  const paths = readFileSync(env.MOCK_KEY_PATHS, 'utf8').trim().split('\n');
  assert.equal(paths.length, 2);
  assert.ok(paths.every(path => path.startsWith(`${external}/`) && !path.startsWith(`${root}/`)));
  assert.deepEqual(readFileSync(env.MOCK_KEY_MODES, 'utf8').trim().split('\n'), ['600', '600']);
  assert.deepEqual(readFileSync(env.MOCK_KEY_DIR_MODES, 'utf8').trim().split('\n'), ['700', '700']);
  assert.equal(readFileSync(env.MOCK_KEY_CONTENT, 'utf8'), 'mock-private-line-1\nmock-private-line-2\n'.repeat(2));
  assert.equal(readFileSync(env.MOCK_ASC_ENV, 'utf8').trim(), credentials);
  assert.equal(readFileSync(env.MOCK_CHECK_ENV, 'utf8').trim(), credentials);
  assert.match(readFileSync(env.MOCK_XCODE_ARGS, 'utf8'), /-authenticationKeyID\nmock-key-id\n-authenticationKeyIssuerID\nmock-issuer-id/);
  assert.ok(paths.every(path => !existsSync(path) && !existsSync(join(path, '..'))));
  assert.equal(readFileSync(credentials, 'utf8'), fixture);

  const inside = runRelease('inside', { ASC_ENV_FILE: join(root, '.env.local') });
  assert.notEqual(inside.run.status, 0);
  assert.match(`${inside.run.stdout}\n${inside.run.stderr}`, /credentials.*outside.*repository/i);
  assert.equal(existsSync(inside.env.MOCK_KEY_PATHS), false);

  const credentialLink = join(external, 'inside-repo.env');
  symlinkSync(join(root, '.env.local'), credentialLink);
  const linked = runRelease('linked', { ASC_ENV_FILE: credentialLink });
  assert.notEqual(linked.run.status, 0);
  assert.match(`${linked.run.stdout}\n${linked.run.stderr}`, /credentials.*outside.*repository/i);

  const defaultCredentials = runRelease('default', { ASC_ENV_FILE: '' });
  assert.notEqual(defaultCredentials.run.status, 0);
  assert.match(`${defaultCredentials.run.stdout}\n${defaultCredentials.run.stderr}`, /credentials.*outside.*repository/i);

  const unsafeTemp = join(root, 'unsafe-temp');
  mkdirSync(unsafeTemp);
  const temp = runRelease('temp', { TMPDIR: unsafeTemp });
  assert.notEqual(temp.run.status, 0);
  assert.match(`${temp.run.stdout}\n${temp.run.stderr}`, /temporary directory.*inside.*repository/i);
  assert.deepEqual(readdirSync(unsafeTemp), []);

  const tempLink = join(external, 'inside-repo');
  symlinkSync(unsafeTemp, tempLink);
  const linkedTemp = runRelease('linked-temp', { TMPDIR: tempLink });
  assert.notEqual(linkedTemp.run.status, 0);
  assert.match(`${linkedTemp.run.stdout}\n${linkedTemp.run.stderr}`, /temporary directory.*inside.*repository/i);
  assert.deepEqual(readdirSync(unsafeTemp), []);

  const emptyCredentials = join(external, 'empty-key.env');
  writeFileSync(emptyCredentials, fixture.replace('mock-private-line-1\\nmock-private-line-2', ''));
  const empty = runRelease('empty', { ASC_ENV_FILE: emptyCredentials });
  assert.notEqual(empty.run.status, 0);
  assert.match(`${empty.run.stdout}\n${empty.run.stderr}`, /APPLE_ASC_PRIVATE_KEY must not be empty/i);
  assert.ok(readdirSync(external).every(path => !path.startsWith('astrid-asc.')));

  const failure = runRelease('failure', { MOCK_FAIL_ARCHIVE: '1' });
  assert.notEqual(failure.run.status, 0);
  const failedPath = readFileSync(failure.env.MOCK_KEY_PATHS, 'utf8').trim();
  assert.ok(failedPath.startsWith(`${external}/`));
  assert.notEqual(failedPath, paths[0]);
  assert.equal(existsSync(failedPath), false);
  assert.equal(existsSync(join(failedPath, '..')), false);
  assert.match(failure.run.stdout, /RESULT: FAILED/);

  const ios = runRelease('ios', { MOCK_FAIL_ARCHIVE: '1' }, 'ios');
  assert.notEqual(ios.run.status, 0);
  const iosPath = readFileSync(ios.env.MOCK_KEY_PATHS, 'utf8').trim();
  assert.ok(iosPath.startsWith(`${external}/`));
  assert.equal(existsSync(iosPath), false);
  assert.equal(existsSync(join(iosPath, '..')), false);
  assert.match(ios.run.stdout, /RESULT: FAILED/);

  const cleanup = runRelease('cleanup', { MOCK_FAIL_CLEANUP: '1' });
  assert.notEqual(cleanup.run.status, 0);
  assert.match(`${cleanup.run.stdout}\n${cleanup.run.stderr}`, /could not remove temporary.*key/i);
  assert.match(cleanup.run.stdout, /RESULT: FAILED/);
  assert.doesNotMatch(cleanup.run.stdout, /RESULT: OK/);
});

test('AITD-447: version checks read an external ASC_ENV_FILE without copying credentials', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'astrid-version-check-')));
  const external = realpathSync(mkdtempSync(join(tmpdir(), 'astrid-version-keys-')));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  t.after(() => rmSync(external, { recursive: true, force: true }));
  const scripts = join(root, 'scripts');
  const bin = join(root, 'bin');
  mkdirSync(scripts);
  mkdirSync(bin);
  for (const script of ['check-version.sh', 'check-app-version-table.sh']) {
    copyFileSync(fileURLToPath(new URL(`./${script}`, import.meta.url)), join(scripts, script));
  }
  const credentials = join(external, 'asc.env');
  writeFileSync(credentials, [
    'APPLE_ASC_KEY_ID=mock-key-id',
    'APPLE_ASC_ISSUER_ID=mock-issuer-id',
    'APPLE_ASC_PRIVATE_KEY=mock-private-key',
    'APPLE_APP_STORE_APP_ID=123',
    '',
  ].join('\n'), { mode: 0o600 });
  const table = join(external, 'app-version.ts');
  writeFileSync(table, "  ios: { latestVersion: '1.0' },\n");
  const calls = join(external, 'calls');
  writeFileSync(join(bin, 'node'), `#!/bin/sh
printf '%s\\n' "$ASC_ENV_FILE" >> "$MOCK_CALLS"
case "$2" in
  version-state) echo PREPARE_FOR_SUBMISSION ;;
  released) echo 1.0 ;;
  *) exit 1 ;;
esac
`, { mode: 0o755 });
  const env = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    TMPDIR: external,
    ASC_ENV_FILE: credentials,
    CHECK_VERSION_ENV_FILE: '',
    APP_VERSION_TABLE_FILE: table,
    MOCK_CALLS: calls,
  };
  const version = spawnSync('/bin/bash', [join(scripts, 'check-version.sh'), 'ios', '--version', '1.0'], {
    cwd: root, env, encoding: 'utf8',
  });
  assert.equal(version.status, 0, version.stderr);
  assert.match(version.stdout, /not released/);
  const appVersion = spawnSync('/bin/bash', [join(scripts, 'check-app-version-table.sh')], {
    cwd: root, env, encoding: 'utf8',
  });
  assert.equal(appVersion.status, 0, appVersion.stderr);
  assert.match(appVersion.stdout, /matches the App Store/);
  assert.deepEqual(readFileSync(calls, 'utf8').trim().split('\n'), [credentials, credentials]);
  assert.equal(existsSync(join(root, '.env.local')), false);

  const override = join(external, 'override.env');
  copyFileSync(credentials, override);
  const overridden = spawnSync('/bin/bash', [join(scripts, 'check-version.sh'), 'ios', '--version', '1.0'], {
    cwd: root, env: { ...env, CHECK_VERSION_ENV_FILE: override }, encoding: 'utf8',
  });
  assert.equal(overridden.status, 0, overridden.stderr);
  assert.equal(readFileSync(calls, 'utf8').trim().split('\n').at(-1), override);

  const missing = { ...env, ASC_ENV_FILE: join(external, 'missing.env') };
  for (const args of [
    [join(scripts, 'check-version.sh'), 'ios', '--version', '1.0'],
    [join(scripts, 'check-app-version-table.sh')],
  ]) {
    const skipped = spawnSync('/bin/bash', args, { cwd: root, env: missing, encoding: 'utf8' });
    assert.equal(skipped.status, 0);
    assert.match(skipped.stdout, /set ASC_ENV_FILE.*outside the repository/i);
    assert.doesNotMatch(skipped.stdout, /cp .*\.env\.local/i);
  }

  const noAppId = join(external, 'missing-app-id.env');
  writeFileSync(noAppId, readFileSync(credentials, 'utf8').replace('APPLE_APP_STORE_APP_ID=123\n', ''));
  const appstore = spawnSync(process.execPath, [
    fileURLToPath(new URL('./asc-appstore.mjs', import.meta.url)), 'next', 'ios',
  ], {
    env: { ...process.env, ASC_ENV_FILE: noAppId, NODE_OPTIONS: '' }, encoding: 'utf8',
  });
  assert.notEqual(appstore.status, 0);
  assert.match(appstore.stderr, /APPLE_APP_STORE_APP_ID.*credentials file/i);
  assert.doesNotMatch(appstore.stderr, /\.env\.local/);
});
