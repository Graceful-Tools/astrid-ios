// test-close-built-tasks.mjs — pins the rules in scripts/lib/built-task-closer.mjs.
//
// Doing filled up because closing a task waited on a session the quiet loop never started
// (2026-09-27). The closer runs unattended every tick, so what it must NOT close matters as much
// as what it must: a reopened task, a task with no marker, a build that does not carry the fix.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { awaitingSha, buildCarrying, closingComment } from './lib/built-task-closer.mjs';

const AGENT = 'ai-agent-claude';
const c = (createdAt, content, extra = {}) => ({ createdAt, content, authorId: AGENT, systemEventType: null, ...extra });
const marker = sha => `## Merged and pushed\n\n...\n\n**Awaiting build:** \`${sha}\``;

test('a marker from the agent names the fix commit', () => {
  assert.equal(awaitingSha([c('2026-09-27T10:00:00Z', marker('ABC1234'))], AGENT), 'abc1234');
});

test('no marker leaves the task alone', () => {
  assert.equal(awaitingSha([c('2026-09-27T10:00:00Z', '## Strategy')], AGENT), null);
});

// An interactive session posts through the astrid MCP or the OAuth comment script, and both
// write as Jon, not as the agent. Requiring the agent's id left AITD-454/458/459 in Doing after
// their builds were VALID, logging "no Awaiting build marker" every tick (2026-10-04).
test('a marker counts whoever posted it', () => {
  assert.equal(awaitingSha([c('2026-09-27T10:00:00Z', marker('abc1234'), { authorId: 'person' })]), 'abc1234');
});

test('a person\'s newer marker wins over the agent\'s older one', () => {
  assert.equal(awaitingSha([
    c('2026-09-27T10:00:00Z', marker('aaaaaaa')),
    c('2026-09-27T12:00:00Z', marker('bbbbbbb'), { authorId: 'person' }),
  ]), 'bbbbbbb');
});

test('the newest marker wins', () => {
  assert.equal(awaitingSha([
    c('2026-09-27T10:00:00Z', marker('aaaaaaa')),
    c('2026-09-27T12:00:00Z', marker('bbbbbbb')),
  ], AGENT), 'bbbbbbb');
});

test('a reopened task is not closed on the fix that missed', () => {
  assert.equal(awaitingSha([
    c('2026-09-27T10:00:00Z', marker('aaaaaaa')),
    c('2026-09-27T11:00:00Z', 'Claude Agent marked this as complete', { authorId: null, systemEventType: 'COMPLETED' }),
  ], AGENT), null);
});

test('a new marker after the reopen counts again', () => {
  assert.equal(awaitingSha([
    c('2026-09-27T10:00:00Z', marker('aaaaaaa')),
    c('2026-09-27T11:00:00Z', 'done', { authorId: null, systemEventType: 'COMPLETED' }),
    c('2026-09-27T13:00:00Z', marker('ccccccc')),
  ], AGENT), 'ccccccc');
});

const builds = [
  { number: '1074', state: 'VALID', sha: 'run1074' },
  { number: '1072', state: 'VALID', sha: 'run1072' },
  { number: '1076', state: 'PROCESSING', sha: 'run1076' },
];

test('picks the first VALID build that carries the fix', () => {
  const carries = (fix, run) => ['run1074', 'run1076'].includes(run);
  assert.equal(buildCarrying('fix', builds, carries)?.number, '1074');
});

test('a build still processing does not count', () => {
  const carries = (fix, run) => run === 'run1076';
  assert.equal(buildCarrying('fix', builds, carries), null);
});

test('no build carrying the fix means wait', () => {
  assert.equal(buildCarrying('fix', builds, () => false), null);
});

test('the comment names the builds and the commit', () => {
  const text = closingComment({ sha: 'abcdef123', ios: { number: '1074' }, mac: { number: '1075' } });
  assert.match(text, /iOS build \*\*1074\*\* and Mac build \*\*1075\*\*/);
  assert.match(text, /`abcdef1`/);
  assert.doesNotMatch(text, /shipped/i);
});
