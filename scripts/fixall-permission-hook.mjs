#!/usr/bin/env node
// fixall-permission-hook.mjs: Claude Code's PermissionRequest hook for the scheduled loop
// (ADEV-249). A request the allowlist does not cover is asked on the run's claimed task as a
// decision, and this waits for the answer (default 20 minutes) instead of refusing outright.
// scripts/fixall-loop.sh installs it for its own `claude -p` run only; interactive sessions
// keep their normal prompts. The rules are in lib/permission-decision.mjs.
//
// Reads the hook's JSON on stdin and prints the decision JSON. Every failure denies, saying why:
// a broken hook must never turn into an allow.
//
// Env: ASTRID_FIXALL_CLAIMS_FILE (set by the loop), ASTRID_WEB_DIR (astrid-web, for the OAuth
// pair in .env.local), FIXALL_APPROVAL_WAIT_SECONDS (1200), FIXALL_APPROVAL_POLL_SECONDS (15),
// FIXALL_APPROVALS_USED (file of used Allow-once answers), ASTRID_API (https://www.astrid.cc).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  AGENT_ID, approversOf, decisionComment, hookOutput, nextStep, requestSignature, taskFromClaims, timeoutMessage,
} from './lib/permission-decision.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WEB = process.env.ASTRID_WEB_DIR || process.env.ASTRID_WEB || path.join(REPO, '..', 'astrid-web');
const API = process.env.ASTRID_API || 'https://www.astrid.cc';
const WAIT = Number(process.env.FIXALL_APPROVAL_WAIT_SECONDS || 1200);
const POLL = Number(process.env.FIXALL_APPROVAL_POLL_SECONDS || 15);
const USED = process.env.FIXALL_APPROVALS_USED
  || path.join(os.homedir(), 'Library', 'Application Support', 'Astrid', 'fixall-approvals-used');
const waitMinutes = Math.round(WAIT / 60);

const answer = (behavior, message) => {
  process.stdout.write(JSON.stringify(hookOutput(behavior, message)) + '\n');
  process.exit(0);
};
const refuse = why => answer('deny', `${why} The request was not run.`);
const log = m => process.stderr.write(`fixall-permission: ${m}\n`);

let request;
try {
  request = JSON.parse(fs.readFileSync(0, 'utf8'));
} catch (e) {
  refuse(`The permission hook could not read its input (${e.message}).`);
}
log(`${request.tool_name} ${requestSignature(request)} ${JSON.stringify(request.tool_input ?? {}).slice(0, 200)}`);

const claims = (() => {
  try { return fs.readFileSync(process.env.ASTRID_FIXALL_CLAIMS_FILE || '', 'utf8'); } catch { return ''; }
})();
const claimed = taskFromClaims(claims);
if (!claimed) {
  refuse('This is outside the allowlist, and no task is claimed yet to ask on. Do without it, or claim a task first.');
}

try {
  const webEnv = (() => { try { return fs.readFileSync(path.join(WEB, '.env.local'), 'utf8'); } catch { return ''; } })();
  const webVar = k => (webEnv.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1]?.replace(/^["']|["']$/g, '');
  const tokenRes = await fetch(`${API}/api/v1/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'client_credentials',
      client_id: webVar('ASTRID_OAUTH_CLIENT_ID'),
      client_secret: webVar('ASTRID_OAUTH_CLIENT_SECRET'),
    }),
  });
  if (!tokenRes.ok) throw new Error(`OAuth token HTTP ${tokenRes.status}`);
  const { access_token: token } = await tokenRes.json();
  const astrid = async (p, opts = {}) => {
    const r = await fetch(API + p, {
      ...opts,
      headers: { 'X-OAuth-Token': token, 'Content-Type': 'application/json', ...(opts.headers || {}) },
    });
    if (!r.ok) throw new Error(`${opts.method || 'GET'} ${p.split('?')[0]} → HTTP ${r.status}`);
    return r.json();
  };

  // The claims file may name the task by identifier; comments are posted by uuid.
  const fetched = await astrid(`/api/v1/tasks/${encodeURIComponent(claimed)}`);
  const task = fetched.task ?? fetched;
  const taskId = task.id;
  // Only the list's owner and admins answer; another member's reply is ignored.
  const approvers = approversOf(task);
  if (approvers.size === 0) throw new Error('no owner or admin on the task\'s lists to answer');
  const comments = async () => (await astrid(`/api/v1/tasks/${taskId}/comments`)).comments ?? [];
  const used = () => {
    try { return new Set(fs.readFileSync(USED, 'utf8').split('\n').filter(Boolean)); } catch { return new Set(); }
  };

  const deadline = Date.now() + WAIT * 1000;
  let step = nextStep(request, await comments(), used(), approvers);
  if (step.step === 'ask') {
    await astrid(`/api/v1/tasks/${taskId}/comments`, {
      method: 'POST',
      body: JSON.stringify({ content: decisionComment(request, waitMinutes), type: 'MARKDOWN', aiAgentId: AGENT_ID }),
    });
    log(`asked on ${claimed}`);
    step = { step: 'wait' };
  }
  while (step.step === 'wait' && Date.now() < deadline) {
    await new Promise(r => setTimeout(r, POLL * 1000));
    step = nextStep(request, await comments(), used(), approvers);
    if (step.step === 'ask') step = { step: 'wait' };  // our question is not visible yet
  }
  if (step.step === 'allow') {
    if (step.consume) {
      fs.mkdirSync(path.dirname(USED), { recursive: true });
      fs.appendFileSync(USED, `${step.consume}\n`);
    }
    log(`allowed on ${claimed}`);
    answer('allow');
  }
  if (step.step === 'deny') answer('deny', step.message);
  answer('deny', timeoutMessage(requestSignature(request), waitMinutes));
} catch (e) {
  refuse(`The permission hook could not ask on ${claimed} (${e.message}).`);
}
