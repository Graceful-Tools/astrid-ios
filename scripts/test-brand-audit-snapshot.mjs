import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmdirSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const helper = resolve('scripts/lib/brand-audit-snapshot.sh');
const webHelper = resolve('scripts/lib/find-web-repo.sh');

function removeFixtureTree(root) {
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) removeFixtureTree(path);
    else unlinkSync(path);
  }
  rmdirSync(root);
}

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'aitd-447-brand-audit-'));
  const first = join(root, 'first.plist');
  const second = join(root, 'second.plist');
  writeFileSync(first, 'first original\n');
  writeFileSync(second, 'second original\n');
  t.after(() => removeFixtureTree(root));
  return { root, first, second };
}

function run(root, first, second, body) {
  return spawnSync('bash', ['-c', `
    set -e
    source "$1"
    shift
    brand_audit_begin "$@"
    brand_audit_prepare
    printf 'first branded\\n' > "\${BRAND_AUDIT_EXPECTED[0]}"
    printf 'second branded\\n' > "\${BRAND_AUDIT_EXPECTED[1]}"
    ${body}
  `, 'brand-audit-test', helper, first, second], {
    encoding: 'utf8',
    env: { ...process.env, TMPDIR: root },
  });
}

test('AITD-447: web discovery prefers the explicit or nested checkout and rejects a bad override', t => {
  const { root } = fixture(t);
  const project = join(root, 'astrid-ios-feature');
  const nested = join(project, 'astrid-web');
  const sibling = join(root, 'astrid-web-feature');
  for (const web of [nested, sibling]) {
    mkdirSync(web, { recursive: true });
    writeFileSync(join(web, 'package.json'), '{}\n');
  }
  const find = configured => spawnSync('bash', [
    '-c', 'source "$1"; find_web_repo "$2"', 'web-discovery-test', webHelper, project,
  ], {
    encoding: 'utf8',
    env: { ...process.env, ASTRID_WEB_DIR: configured },
  });
  const explicit = find(sibling);
  assert.equal(explicit.status, 0, explicit.stderr);
  assert.equal(explicit.stdout.trim(), sibling);
  const preferred = find('');
  assert.equal(preferred.status, 0, preferred.stderr);
  assert.equal(preferred.stdout.trim(), nested);
  const missing = find(join(root, 'missing'));
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /ASTRID_WEB_DIR/);
});

test('AITD-447: brand audit restores only its own changes without git checkout', t => {
  const { root, first, second } = fixture(t);
  const result = run(root, first, second, `
    brand_audit_install
    brand_audit_restore
    brand_audit_dispose
  `);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(first, 'utf8'), 'first original\n');
  assert.equal(readFileSync(second, 'utf8'), 'second original\n');
  assert.deepEqual(readdirSync(root).sort(), ['first.plist', 'second.plist']);
});

test('AITD-447: a concurrent edit is preserved and its original snapshot retained', t => {
  const { root, first, second } = fixture(t);
  const result = run(root, first, second, `
    brand_audit_install
    printf 'concurrent edit\\n' > "$1"
    if brand_audit_restore; then exit 9; fi
    printf '%s\\n' "$BRAND_AUDIT_DIR"
  `);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /changed during the brand audit/i);
  assert.equal(readFileSync(first, 'utf8'), 'concurrent edit\n');
  assert.equal(readFileSync(second, 'utf8'), 'second original\n');
  assert.equal(readFileSync(join(result.stdout.trim(), 'original-0'), 'utf8'), 'first original\n');
});

test('AITD-447: a changed input prevents any brand files being installed', t => {
  const { root, first, second } = fixture(t);
  const result = run(root, first, second, `
    printf 'concurrent edit\\n' > "$2"
    if brand_audit_install; then exit 9; fi
    brand_audit_dispose
  `);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /changed before the brand audit/i);
  assert.equal(readFileSync(first, 'utf8'), 'first original\n');
  assert.equal(readFileSync(second, 'utf8'), 'concurrent edit\n');
});

test('AITD-447: brand audit refuses symlinks rather than modifying their targets', t => {
  const { root, first, second } = fixture(t);
  unlinkSync(first);
  symlinkSync(second, first);
  const result = run(root, first, second, 'brand_audit_install');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /refuses a symlink/i);
  assert.equal(readFileSync(second, 'utf8'), 'second original\n');
});

function auditFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'aitd-447-brand-gate-'));
  t.after(() => removeFixtureTree(root));
  const project = join(root, 'project');
  const web = join(root, 'web');
  const bin = join(root, 'bin');
  for (const dir of [
    join(project, 'scripts', 'lib'),
    join(project, 'Astrid App'),
    join(project, 'Astrid Mac'),
    join(web, 'brands'),
    bin,
  ]) mkdirSync(dir, { recursive: true });

  for (const script of ['check-brands.sh', 'apply-brand.sh']) {
    copyFileSync(resolve('scripts', script), join(project, 'scripts', script));
    chmodSync(join(project, 'scripts', script), 0o755);
  }
  for (const script of ['find-web-repo.sh', 'ios-destination.sh', 'brand-audit-snapshot.sh']) {
    copyFileSync(resolve('scripts/lib', script), join(project, 'scripts/lib', script));
  }

  const plist = '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n' +
    '<plist version="1.0"><dict></dict></plist>\n';
  const files = [
    'Info.plist', 'Info-Debug.plist', 'Astrid Mac/Info.plist',
    'Astrid App/Astrid App.entitlements', 'Astrid Mac/Astrid Mac.entitlements',
    'Astrid Mac/Astrid Mac Direct.entitlements',
  ];
  for (const file of files) writeFileSync(join(project, file), plist);
  writeFileSync(join(web, 'package.json'), '{}\n');
  writeFileSync(join(web, 'brands', 'fixture.brand.json'), JSON.stringify({
    env: { NEXT_PUBLIC_BRAND_NAME: 'Fixture Partner' },
  }));
  writeFileSync(join(bin, 'git'), '#!/bin/bash\n[ "$1" = diff ]\n');
  writeFileSync(join(bin, 'xcodebuild'), `#!/bin/bash
grep -q 'Fixture Partner' "$FIXTURE_PROJECT/Info.plist" || exit 9
echo "$*" >> "$FIXTURE_CALLS"
if [ "\${FIXTURE_ACTION:-}" = edit ]; then printf 'concurrent edit\\n' > "$FIXTURE_PROJECT/Info.plist"; fi
if [ "\${FIXTURE_ACTION:-}" = interrupt ]; then kill -TERM "$PPID"; fi
exit 0
`);
  chmodSync(join(bin, 'git'), 0o755);
  chmodSync(join(bin, 'xcodebuild'), 0o755);
  return { root, project, web, bin, files, plist };
}

function runAudit(f, action = '') {
  return spawnSync(join(f.project, 'scripts/check-brands.sh'), [], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${f.bin}:${process.env.PATH}`,
      TMPDIR: f.root,
      ASTRID_WEB_DIR: f.web,
      FIXTURE_PROJECT: f.project,
      FIXTURE_CALLS: join(f.root, 'calls'),
      FIXTURE_ACTION: action,
    },
  });
}

test('AITD-447: the brand gate uses the explicit web checkout and restores every input', t => {
  const f = auditFixture(t);
  const result = runAudit(f);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.equal(readFileSync(join(f.root, 'calls'), 'utf8').trim().split('\n').length, 2);
  for (const file of f.files) assert.equal(readFileSync(join(f.project, file), 'utf8'), f.plist);
});

test('AITD-447: the brand gate preserves concurrent edits and fails visibly', t => {
  const f = auditFixture(t);
  const result = runAudit(f, 'edit');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /changed during the brand audit/i);
  assert.equal(readFileSync(join(f.project, 'Info.plist'), 'utf8'), 'concurrent edit\n');
  for (const file of f.files.slice(1)) assert.equal(readFileSync(join(f.project, file), 'utf8'), f.plist);
});

test('AITD-447: an interrupted brand gate restores the original inputs', t => {
  const f = auditFixture(t);
  const result = runAudit(f, 'interrupt');
  assert.equal(result.status, 143, `${result.stdout}\n${result.stderr}`);
  for (const file of f.files) assert.equal(readFileSync(join(f.project, file), 'utf8'), f.plist);
});
