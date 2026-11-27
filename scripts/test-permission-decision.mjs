// ADEV-249: a command the scheduled loop is not allowed to run becomes a decision on the task.
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  requestSignature, decisionComment, readAnswer, nextStep, hookOutput, taskFromClaims, approversOf, AGENT_ID,
} from './lib/permission-decision.mjs';

const bash = { tool_name: 'Bash', tool_input: { command: 'curl -s https://example.com', description: 'Fetch it' } };
const sig = requestSignature(bash);
const asked = (id = 'c1', at = '2026-11-24T10:00:00Z') => ({
  id, authorId: AGENT_ID, author: { isAIAgent: true }, createdAt: at, content: decisionComment(bash),
});
const ok = new Set(['jon']);
const reply = (content, at = '2026-11-24T10:01:00Z', id = 'r1') => ({
  id, authorId: 'jon', author: { isAIAgent: false }, createdAt: at, content,
});

test('ADEV-249 the signature is stable for the same request and differs for another', () => {
  assert.equal(sig, requestSignature({ ...bash }));
  assert.match(sig, /^[0-9a-f]{8}$/);
  assert.notEqual(sig, requestSignature({ tool_name: 'Bash', tool_input: { command: 'rm -rf build' } }));
});

test('ADEV-249 the comment is a decision with the command and three numbered options', () => {
  const md = decisionComment(bash);
  assert.match(md, /^\*\*Decision:\*\*/);
  assert.ok(md.includes('curl -s https://example.com'));
  assert.match(md, /\n- \*\*1\.\*\* Allow once\n- \*\*2\.\*\* Allow for this task\n- \*\*3\.\*\* Deny\n/);
  assert.ok(md.includes(`Request \`${sig}\``));
});

test('ADEV-249 a long command is shortened, and backticks cannot break out of the code span', () => {
  const md = decisionComment({ tool_name: 'Bash', tool_input: { command: 'echo `x` ' + 'a'.repeat(900) } });
  assert.ok(md.length < 1200);
  assert.ok(!md.includes('`x`'));
});

test('ADEV-249 a tapped card or a typed number is the answer; words are passed on', () => {
  assert.deepEqual(readAnswer('1 — Allow once'), { choice: 1 });
  assert.deepEqual(readAnswer('2'), { choice: 2 });
  assert.deepEqual(readAnswer(' 3 - Deny'), { choice: 3 });
  assert.deepEqual(readAnswer('use wget instead'), { words: 'use wget instead' });
  assert.deepEqual(readAnswer('2 days is fine'), { words: '2 days is fine' });
});

test('ADEV-249 with nothing asked yet, it asks', () => {
  assert.deepEqual(nextStep(bash, [], new Set(), ok), { step: 'ask' });
});

test('ADEV-249 an unanswered question is waited on, not asked twice', () => {
  assert.deepEqual(nextStep(bash, [asked()], new Set(), ok), { step: 'wait', commentId: 'c1' });
});

test('ADEV-249 Allow once allows once, then the next identical request asks again', () => {
  const comments = [asked(), reply('1 — Allow once')];
  assert.deepEqual(nextStep(bash, comments, new Set(), ok), { step: 'allow', consume: 'r1' });
  assert.deepEqual(nextStep(bash, comments, new Set(['r1']), ok), { step: 'ask' });
});

test('ADEV-249 Allow for this task keeps allowing the same request', () => {
  const comments = [asked(), reply('2 — Allow for this task')];
  assert.deepEqual(nextStep(bash, comments, new Set(), ok), { step: 'allow' });
  assert.deepEqual(nextStep(bash, comments, new Set(['r1']), ok), { step: 'allow' });
});

test('ADEV-249 Deny and a reply in words both deny; words send the agent to the comment', () => {
  assert.equal(nextStep(bash, [asked(), reply('3 — Deny')], new Set(), ok).step, 'deny');
  const words = nextStep(bash, [asked(), reply('use the API script instead')], new Set(), ok);
  assert.equal(words.step, 'deny');
  // The words are not relayed through the tool result, which the model rightly distrusts; the
  // agent is sent to the comment, read as any instruction on the task.
  assert.ok(!words.message.includes('use the API script instead'));
  assert.match(words.message, /get_task_comments/);
  assert.equal(words.commentId, 'r1');
});

test('ADEV-249 only a person answers: the agent\'s own comments and earlier replies do not count', () => {
  const agentReply = { ...reply('1'), authorId: AGENT_ID, author: { isAIAgent: true } };
  assert.equal(nextStep(bash, [asked(), agentReply], new Set(), ok).step, 'wait');
  const before = reply('1', '2026-11-24T09:00:00Z');
  assert.equal(nextStep(bash, [before, asked()], new Set(), ok).step, 'wait');
});

test('ADEV-249 another request\'s question does not answer this one', () => {
  const other = { tool_name: 'Bash', tool_input: { command: 'rm -rf build' } };
  const comments = [{ ...asked(), content: decisionComment(other) }, reply('2')];
  assert.deepEqual(nextStep(bash, comments, new Set(), ok), { step: 'ask' });
});

test('ADEV-249 only the list\'s owner or an admin can answer; another member cannot approve', () => {
  const member = { ...reply('2 — Allow for this task'), authorId: 'member' };
  assert.equal(nextStep(bash, [asked(), member], new Set(), ok).step, 'wait');
  assert.equal(nextStep(bash, [asked(), reply('2')], new Set(), new Set()).step, 'wait');
  const task = { lists: [{ ownerId: 'jon', listMembers: [
    { userId: 'jon', role: 'admin' }, { userId: 'member', role: 'member' }, { userId: AGENT_ID, role: 'admin' },
    { userId: 'other-admin', role: 'admin' },
  ] }] };
  assert.deepEqual([...approversOf(task)].sort(), ['jon', 'other-admin']);
});

test('ADEV-249 the hook prints the PermissionRequest decision shape', () => {
  assert.deepEqual(hookOutput('allow'), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow' } },
  });
  assert.deepEqual(hookOutput('deny', 'no').hookSpecificOutput.decision, { behavior: 'deny', message: 'no' });
});

test('ADEV-249 the task asked on is the run\'s latest claim', () => {
  assert.equal(taskFromClaims('a\nb\n'), 'b');
  assert.equal(taskFromClaims(''), null);
});
