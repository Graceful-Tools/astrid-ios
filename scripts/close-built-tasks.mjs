// close-built-tasks.mjs — complete the /fixall tasks whose TestFlight build is ready.
//
// A task stays in Doing until a VALID build carries its fix (Jon, 2026-09-21). Closing it used
// to be a step inside a session, and scripts/fixall-loop.sh only starts a session when the queue
// has work, so on a quiet board nothing came back to close them and Doing filled up (Jon,
// 2026-09-27). The loop now runs this on every tick — no session, no tokens.
//
// What it closes: Doing tasks on the iOS board assigned to claude whose newest
// `**Awaiting build:** \`<sha>\`` comment (see .claude/commands/fixall.md) names a commit that a
// VALID TestFlight build contains. Everything else it leaves alone and says why in one line.
// The rules live in lib/built-task-closer.mjs and are pinned by test-close-built-tasks.mjs.
//
// Usage: node scripts/close-built-tasks.mjs [--dry-run]
// Needs ASTRID_OAUTH_CLIENT_ID / _SECRET in astrid-web/.env.local (ASTRID_WEB overrides the
// path) and the ASC key in this repo's .env.local. Exit 0 unless something could not be asked.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ascRequest, pick } from './lib/asc-jwt.mjs';
import { awaitingSha, buildCarrying, closingComment } from './lib/built-task-closer.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WEB = process.env.ASTRID_WEB || path.join(REPO, '..', 'astrid-web');
const API = 'https://www.astrid.cc';
const IOS_LIST_ID = 'aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36';
const AGENT_ID = 'ai-agent-claude';
const DRY = process.argv.includes('--dry-run');

const fail = m => { console.log(`close-built: could not check — ${m}`); process.exit(1); };

// ── Astrid (OAuth client credentials, the same pair the astrid-web scripts use) ──────────────
const webEnv = (() => { try { return fs.readFileSync(path.join(WEB, '.env.local'), 'utf8'); } catch { return ''; } })();
const webVar = k => (webEnv.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1]?.replace(/^["']|["']$/g, '');
const clientId = webVar('ASTRID_OAUTH_CLIENT_ID');
const clientSecret = webVar('ASTRID_OAUTH_CLIENT_SECRET');
if (!clientId || !clientSecret) fail(`no ASTRID_OAUTH_CLIENT_ID/_SECRET in ${WEB}/.env.local`);

const tokenRes = await fetch(`${API}/api/v1/oauth/token`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ grant_type: 'client_credentials', client_id: clientId, client_secret: clientSecret }),
}).catch(e => fail(e.message));
if (!tokenRes.ok) fail(`OAuth token HTTP ${tokenRes.status}`);
const { access_token: token } = await tokenRes.json();

const astrid = async (p, opts = {}) => {
  const r = await fetch(API + p, {
    ...opts,
    headers: { 'X-OAuth-Token': token, 'Content-Type': 'application/json', ...(opts.headers || {}) },
  });
  if (!r.ok) throw new Error(`${opts.method || 'GET'} ${p.split('?')[0]} → HTTP ${r.status}`);
  return r.json();
};

const doing = (await astrid(`/api/v1/tasks?listId=${IOS_LIST_ID}&statusRole=doing&assigneeId=${AGENT_ID}` +
  `&completed=false&limit=100`).catch(e => fail(e.message))).tasks ?? [];
if (doing.length === 0) { console.log('close-built: nothing in Doing'); process.exit(0); }

// ── Which fix each task is waiting on ─────────────────────────────────────────────────────────
const waiting = [];
for (const t of doing) {
  const name = t.identifier || t.id.slice(0, 8);
  const { comments = [] } = await astrid(`/api/v1/tasks/${t.id}/comments`).catch(e => fail(e.message));
  const sha = awaitingSha(comments, AGENT_ID);
  if (!sha) { console.log(`close-built: ${name} — no Awaiting build marker, left for a session`); continue; }
  waiting.push({ task: t, name, sha });
}
if (waiting.length === 0) process.exit(0);

// ── Which builds are VALID, and what each was built from ──────────────────────────────────────
// A build number IS its Xcode Cloud run number, and only the run knows the sha (see
// asc-appstore.mjs `runs`). A locally uploaded build has no run and so never matches here —
// that is a wait, not a wrong answer.
const asc = async p => {
  const { status, body } = await ascRequest(p).catch(e => fail(e.message));
  if (status >= 300) fail(`ASC ${status} on ${p.split('?')[0]}`);
  return body;
};
const APP = pick('APPLE_APP_STORE_APP_ID') || fail('APPLE_APP_STORE_APP_ID missing from .env.local');
const runSha = {};
for (const prod of (await asc('/v1/ciProducts?limit=10')).data ?? []) {
  const runs = await asc(`/v1/ciProducts/${prod.id}/buildRuns?limit=40&sort=-number`);
  for (const r of runs.data ?? []) {
    const a = r.attributes ?? {};
    if (a.number && a.sourceCommit?.commitSha) runSha[String(a.number)] = a.sourceCommit.commitSha;
  }
}
const res = await asc(`/v1/builds?filter[app]=${APP}&sort=-version&limit=80&include=preReleaseVersion`);
const platformOf = Object.fromEntries((res.included ?? []).map(i => [i.id, i.attributes?.platform]));
const builds = (res.data ?? []).map(b => ({
  number: b.attributes.version,
  state: b.attributes.processingState,
  platform: platformOf[b.relationships?.preReleaseVersion?.data?.id],
  sha: runSha[b.attributes.version],
}));

// ── Git: fetch once, then ask ancestry locally ────────────────────────────────────────────────
// core.fsmonitor off: a wedged fsmonitor daemon hung plain `git status` here on 2026-09-27, and
// an unattended tick must not hang on it.
const git = (...args) => execFileSync('git', ['-c', 'core.fsmonitor=false', ...args],
  { cwd: REPO, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
try { git('fetch', '-q', 'origin'); } catch { /* offline: ancestry of what we already have */ }
const known = sha => { try { git('cat-file', '-e', `${sha}^{commit}`); return true; } catch { return false; } };
const contains = (fix, run) => {
  if (!known(run)) return false;
  try { git('merge-base', '--is-ancestor', fix, run); return true; } catch { return false; }
};

let closed = 0;
for (const { task, name, sha } of waiting) {
  if (!known(sha)) { console.log(`close-built: ${name} — ${sha} is not a commit here, left alone`); continue; }
  const ios = buildCarrying(sha, builds.filter(b => b.platform === 'IOS'), contains);
  const mac = buildCarrying(sha, builds.filter(b => b.platform === 'MAC_OS'), contains);
  if (!ios && !mac) { console.log(`close-built: ${name} — no VALID build carries ${sha.slice(0, 7)} yet`); continue; }
  const label = [ios && `iOS ${ios.number}`, mac && `Mac ${mac.number}`].filter(Boolean).join(', ');
  if (DRY) { console.log(`close-built: ${name} — would close (${label})`); continue; }
  try {
    await astrid(`/api/v1/tasks/${task.id}/comments`, {
      method: 'POST', body: JSON.stringify({ content: closingComment({ sha, ios, mac }), type: 'MARKDOWN' }),
    });
    await astrid(`/api/v1/tasks/${task.id}`, { method: 'PUT', body: JSON.stringify({ completed: true }) });
    console.log(`close-built: ${name} — closed (${label})`);
    closed++;
  } catch (e) {
    console.log(`close-built: ${name} — could not close: ${e.message}`);
  }
}
console.log(`close-built: ${closed} closed, ${doing.length - closed} still in Doing`);
