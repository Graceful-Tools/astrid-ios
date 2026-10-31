import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'aitd-447-test-runner-')));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const scripts = join(root, 'scripts');
  const bin = join(root, 'bin');
  mkdirSync(join(scripts, 'lib'), { recursive: true });
  mkdirSync(join(root, 'Astrid AppUITests'));
  mkdirSync(bin);
  copyFileSync(resolve('scripts/run-tests.sh'), join(scripts, 'run-tests.sh'));
  chmodSync(join(scripts, 'run-tests.sh'), 0o755);
  for (const name of ['ios-destination.sh', 'uitest-session.sh']) {
    copyFileSync(resolve('scripts/lib', name), join(scripts, 'lib', name));
  }
  const session = join(root, 'Astrid AppUITests/UITestSession.plist');
  const marker = join(root, 'find-called');
  const teeMarker = join(root, 'tee-target');
  const logDir = join(root, 'logs');
  mkdirSync(logDir);
  writeFileSync(session, 'existing user session\n');
  writeFileSync(join(bin, 'find'), '#!/bin/bash\nprintf called > "$FIND_MARKER"\n');
  writeFileSync(join(bin, 'tee'), '#!/bin/bash\nprintf "%s" "$1" > "$TEE_MARKER"\ncat\n');
  writeFileSync(join(bin, 'xcodebuild'), '#!/bin/bash\necho fixture-unit-output\n');
  writeFileSync(join(bin, 'node'), '#!/bin/bash\nexit 0\n');
  writeFileSync(join(scripts, 'xcresult-summary.sh'), '#!/bin/bash\necho "1 passed"\n');
  for (const name of ['find', 'tee', 'xcodebuild', 'node']) chmodSync(join(bin, name), 0o755);
  chmodSync(join(scripts, 'xcresult-summary.sh'), 0o755);
  return { root, bin, session, marker, teeMarker, logDir };
}

function run(f, preserve, unit = false) {
  const env = {
    ...process.env,
    PATH: `${f.bin}:${process.env.PATH}`,
    FIND_MARKER: f.marker,
    TEE_MARKER: f.teeMarker,
    ASTRID_UNIT_TEST_LOG_DIR: f.logDir,
  };
  if (preserve) env.ASTRID_PRESERVE_TEST_RESULTS = '1';
  else delete env.ASTRID_PRESERVE_TEST_RESULTS;
  return spawnSync(join(f.root, 'scripts/run-tests.sh'), unit ? [] : ['--no-unit'], { encoding: 'utf8', env });
}

test('AITD-447: preserving results prevents the runner from pruning existing bundles', t => {
  const f = fixture(t);
  const result = run(f, true);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(f.marker), false);
});

test('AITD-447: a non-UI run leaves an existing UI test session alone', t => {
  const f = fixture(t);
  const result = run(f, true);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(f.session, 'utf8'), 'existing user session\n');
});

test('AITD-447: the normal runner still performs its existing results retention', t => {
  const f = fixture(t);
  const result = run(f, false);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(f.marker, 'utf8'), 'called');
});

test('AITD-447: the unit log can be placed in a private run-owned directory', t => {
  const f = fixture(t);
  const result = run(f, true, true);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.equal(readFileSync(f.teeMarker, 'utf8'), join(f.logDir, 'unit_tests.log'));
});
