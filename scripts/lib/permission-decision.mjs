// permission-decision.mjs: what the scheduled loop does with a command its allowlist does not cover
// (ADEV-249). Instead of being refused, the request is asked on the claimed task as a decision
// (astrid-web docs/DECISIONS.md), so the person answers it with a tap on the phone, web or Mac:
//   1. Allow once   2. Allow for this task   3. Deny   (or a reply in words: denied, and the
//   agent is sent to read that comment the way it reads any instruction on the task)
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
    ...CHOICES.map((c, i) => `${i + 1}. ${c}`),
    '',
    `${why}Request \`${requestSignature(request)}\`. A reply in words denies it, and the agent reads your comment on the task instead. ` +
      `With no answer in ${waitMinutes} minutes the run stops asking and hands the task back to you.`,
  ].join('\n');
}

/** A tapped card posts `1 — Allow once`; a typed `2` counts too. Anything else is words. */
export function readAnswer(content) {
  const text = String(content ?? '').trim();
  const m = text.match(/^([1-3])\s*(?:[—–\-.:)]|$)/);
  return m ? { choice: Number(m[1]) } : { words: text };
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
