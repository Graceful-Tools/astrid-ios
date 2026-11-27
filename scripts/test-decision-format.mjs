// ADEV-336: questions this repo's agents post must draw as Decision cards on every client.
// The ADEV-333 question wrote `1. **Leave it web-only…**` — a plain list number, then bold text —
// which no client recognises, so it drew as prose. The rule (astrid-web `docs/DECISIONS.md`,
// PRODUCT_CONTRACT §8) is a bold marker opening every option: `- **1.** Ship today (recommended)`.
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseDecision } from './lib/decision-format.mjs';
import { decisionComment } from './lib/permission-decision.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const webDir = process.env.ASTRID_WEB_DIR || join(root, '..', 'astrid-web');
const fixture = join(webDir, 'contracts', 'fixtures', 'decisions.json');

test('ADEV-336 the port agrees with the shared contract fixture', { skip: !existsSync(fixture) && 'no astrid-web checkout' }, () => {
  const { decisions } = JSON.parse(readFileSync(fixture, 'utf8'));
  assert.ok(decisions.length > 5);
  for (const { name, text, parsed } of decisions) {
    assert.deepEqual(parseDecision(text), parsed, name);
  }
});

test('ADEV-336 a plain list number before bold text is not a Decision', () => {
  const adev333 = '**Decision:** Build it?\n\n1. **Leave it web-only (recommended).** Why.\n2. **Build part.** Why.';
  assert.equal(parseDecision(adev333), null);
  const right = '**Decision:** Build it?\n\n- **1.** Leave it web-only (recommended)\n- **2.** Build part';
  assert.deepEqual(parseDecision(right).options.map(o => [o.number, o.text, o.recommended]),
    [[1, 'Leave it web-only', true], [2, 'Build part', false]]);
});

test('ADEV-336 the approval hook asks with tappable cards', () => {
  const md = decisionComment({ tool_name: 'Bash', tool_input: { command: 'curl -s https://example.com' } });
  const parsed = parseDecision(md);
  assert.ok(parsed, md);
  assert.deepEqual(parsed.options.map(o => o.text), ['Allow once', 'Allow for this task', 'Deny']);
});

test('ADEV-336 the example fixall.md teaches is one', () => {
  const doc = readFileSync(join(root, '.claude', 'commands', 'fixall.md'), 'utf8');
  const example = /```markdown\n(\*\*Decision:\*\*[\s\S]*?)```/.exec(doc);
  assert.ok(example, 'fixall.md shows a fenced Decision example');
  const parsed = parseDecision(example[1]);
  assert.ok(parsed, example[1]);
  assert.equal(parsed.options.filter(o => o.recommended).length, 1);
  assert.match(example[1], /AGENT-HANDBACK: claude\s*$/);
});
