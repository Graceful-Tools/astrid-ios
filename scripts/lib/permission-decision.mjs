// permission-decision.mjs: what the scheduled loop does with a command its allowlist does not cover
// (ADEV-249). Instead of being refused, the request is asked on the claimed task as a decision
// (astrid-web docs/DECISIONS.md), so the person answers it with a tap on the phone, web or Mac:
//   1. Allow once   2. Allow for this task   3. Deny   (a typed "allow" or "deny" counts too; any
//   other reply in words is a deny, and the agent is sent to read that comment the way it reads
//   any instruction on the task)
// A request that has a plain form the allowlist already covers is not asked at all the first
// time: it is sent straight back with the rewrite (`plainForm`), which costs no one 20 minutes.
// This file is the pure part: the comment, reading the thread, and the hook's answer. The hook
// that calls the API is scripts/fixall-permission-hook.mjs.

import { createHash } from 'node:crypto';

export const AGENT_ID = 'ai-agent-claude';
export const CHOICES = ['Allow once', 'Allow for this task', 'Deny'];
const MAX_SHOWN = 500;

/** Stable across runs for the same request. The model's `description` is left out: it words
 *  the same command differently each time. */
export function requestSignature({ tool_name, tool_input = {} }) {
  const { description: _ignored, ...rest } = tool_input;
  const stable = JSON.stringify(rest, Object.keys(rest).sort());
  return createHash('sha256').update(`${tool_name}\0${stable}`).digest('hex').slice(0, 8);
}

/** What is asked for, in one line: the command, the file, or the input. */
function shown({ tool_name, tool_input = {} }) {
  const raw = tool_input.command ?? tool_input.file_path ?? tool_input.url ?? JSON.stringify(tool_input);
  const flat = String(raw).replace(/`/g, "'").replace(/\s+/g, ' ').trim();
  return flat.length > MAX_SHOWN ? `${flat.slice(0, MAX_SHOWN)}…` : flat;
}

export function decisionComment(request, waitMinutes = 20) {
  const why = request.tool_input?.description ? `${String(request.tool_input.description).replace(/`/g, "'")}. ` : '';
  return [
    `**Decision:** The scheduled run wants to use **${request.tool_name}**, which its allowlist does not cover: \`${shown(request)}\`. Allow it?`,
    '',
    // A bold number opens each option, or no client draws the cards (ADEV-336, DECISIONS.md).
    ...CHOICES.map((c, i) => `- **${i + 1}.** ${c}`),
    '',
    `${why}Request \`${requestSignature(request)}\`. Typing **allow** or **deny** works too. Any other reply denies it, and the agent reads your comment on the task instead. ` +
      `With no answer in ${waitMinutes} minutes the run stops asking and hands the task back to you.`,
  ].join('\n');
}

/** The option names, typed. Only the whole reply counts: a sentence that starts with "allow"
 *  may go on to say something else (ADEV-328: "Allow." was read as a deny and cost a night). */
const TYPED = {
  allow: 1, 'allow once': 1, 'allow it': 1, yes: 1, ok: 1, approve: 1, approved: 1,
  'allow for this task': 2, 'allow for task': 2,
  deny: 3, denied: 3, no: 3,
};

/** A tapped card posts `1 — Allow once`; a typed `2` or `allow` counts too. Anything else is words. */
export function readAnswer(content) {
  const text = String(content ?? '').trim();
  const m = text.match(/^([1-3])\s*(?:[—–\-.:)]|$)/);
  if (m) return { choice: Number(m[1]) };
  const typed = TYPED[text.toLowerCase().replace(/[.!\s]+$/, '').replace(/\s+/g, ' ')];
  return typed ? { choice: typed } : { words: text };
}

/** Shell operators outside quotes: chaining, pipes, redirects, substitution, a second line. */
function hasShellOperator(command) {
  let quote = null;
  for (let i = 0; i < command.length; i++) {
    const ch = command[i];
    if (quote) {
      if (ch === '\\' && quote === '"') i++;
      else if (ch === quote) quote = null;
      else if (quote === '"' && (ch === '`' || (ch === '$' && command[i + 1] === '('))) return true;
      continue;
    }
    if (ch === '\\') { i++; continue; }
    if (ch === '"' || ch === "'") { quote = ch; continue; }
    if (';|&<>`\n'.includes(ch) || (ch === '$' && command[i + 1] === '(')) return true;
  }
  return false;
}

/**
 * The plain form of a Bash request, when it has one: null, or what to tell the agent instead of
 * asking a person. The allowlist matches a command by its first words, so the same work passes
 * when it is one command per call with relative paths, and stalls for 20 minutes when it is not
 * (ADEV-328: `git -C /abs/astrid-core fetch && … | head` was asked twice; `git -C ../astrid-core
 * fetch` was allowed all along). `parentDir` is the folder the checkouts sit in.
 */
export function plainForm({ tool_name, tool_input = {} }, { parentDir } = {}) {
  if (tool_name !== 'Bash') return null;
  const command = String(tool_input.command ?? '').trim();
  const fixes = [];
  const prefix = parentDir ? `${String(parentDir).replace(/\/+$/, '')}/` : null;
  if (prefix && command.includes(prefix)) {
    const sibling = command.slice(command.indexOf(prefix) + prefix.length).split(/[\/\s'"]/)[0];
    fixes.push(`name the sibling checkout by its relative path (../${sibling}), as the allowlist does, not by an absolute one`);
  }
  // The board helpers are allowlisted as `cd ../astrid-web && npx tsx scripts/…`: that one chain
  // is the plain form, so it is not what gets split.
  if (hasShellOperator(command.replace(/^cd \.\.\/astrid-web && /, ''))) {
    fixes.push('send one plain command per call: no &&, ;, pipes, redirects, $( ) or second lines. ' +
      'Use the Read and Grep tools in place of head, tail, sed and grep');
  }
  if (fixes.length === 0) return null;
  return `Not asked: this has a plain form the allowlist most likely covers. ${fixes.join('; and ')}. ` +
    'In astrid-core worktrees use scripts/core/worktree.sh (see .claude/commands/fixall.md). ' +
    'If it truly cannot be written that way, send the identical request again and it will be put to the person.';
}

const isPerson = c => c.authorId !== AGENT_ID && !c.author?.isAIAgent;
const isApprover = approvers => c => isPerson(c) && approvers.has(c.authorId);

/** Who may answer: the task's lists' owners and admins. A list can have other members, and a
 *  member must not be able to approve a command on this Mac. */
export function approversOf(task) {
  const ids = new Set();
  for (const list of task?.lists ?? []) {
    if (list.ownerId) ids.add(list.ownerId);
    for (const m of list.listMembers ?? []) if (m.role === 'admin' || m.role === 'owner') ids.add(m.userId);
  }
  ids.delete(AGENT_ID);
  return ids;
}
const signatureIn = c => (String(c.content ?? '').match(/Request `([0-9a-f]{8})`/) || [])[1];
const time = c => Date.parse(c.createdAt);

/**
 * Given the task's comments, the answers already used up (Allow once is good for one call) and
 * who may answer, what to do with this request: `ask`, `wait` on the question already posted,
 * `allow`, or `deny`. Anyone else's reply is ignored.
 */
export function nextStep(request, comments, consumed, approvers) {
  const sig = requestSignature(request);
  const sorted = [...comments].sort((a, b) => time(a) - time(b));
  const questions = sorted.filter(c => c.authorId === AGENT_ID && signatureIn(c) === sig);
  if (questions.length === 0) return { step: 'ask' };
  const answers = isApprover(approvers);
  const answerTo = q => sorted.find(c => answers(c) && time(c) > time(q));

  if (questions.some(q => { const a = answerTo(q); return a && readAnswer(a.content).choice === 2; })) {
    return { step: 'allow' };
  }
  const latest = questions[questions.length - 1];
  const answer = answerTo(latest);
  if (!answer) return { step: 'wait', commentId: latest.id };
  const read = readAnswer(answer.content);
  if (read.choice === 1) return consumed.has(answer.id) ? { step: 'ask' } : { step: 'allow', consume: answer.id };
  if (read.choice === 3) {
    return { step: 'deny', message: 'Denied on the task by the person who answered. Do not retry it; find another way or say why in your report.' };
  }
  // Not quoted here: text inside a tool result is not the person speaking, and the model is right
  // to distrust it (seen in the ADEV-249 smoke run). The comment itself is read the usual way.
  return {
    step: 'deny',
    message: 'Not allowed: the person replied on the task with a comment instead of choosing. Read the ' +
      "task's latest comments (get_task_comments) and follow them.",
    commentId: answer.id,
  };
}

export function timeoutMessage(sig, waitMinutes) {
  return `No answer on the task within ${waitMinutes} minutes to request ${sig}. Do not retry it now. ` +
    'Hand the task back as .claude/commands/fixall.md describes (a comment ending AGENT-HANDBACK: claude, then ' +
    'assign-task.ts --handback), saying the run is waiting on that request. When it is answered, the resumed run ' +
    'is allowed or told why not.';
}

/** The JSON a PermissionRequest hook prints (code.claude.com/docs/en/hooks). */
export function hookOutput(behavior, message) {
  return {
    hookSpecificOutput: {
      hookEventName: 'PermissionRequest',
      decision: behavior === 'deny' ? { behavior, message } : { behavior },
    },
  };
}

/** The claims file holds one task id per claim, newest last. */
export function taskFromClaims(text) {
  const lines = String(text ?? '').split('\n').map(s => s.trim()).filter(Boolean);
  return lines.length ? lines[lines.length - 1] : null;
}
