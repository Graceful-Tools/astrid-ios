// ADEV-336: the Decision recognition rule, for checking what this repo's agents post.
// A port of astrid-web `lib/comment-formats.ts` `parseDecision` (PRODUCT_CONTRACT §8, the guide is
// `docs/DECISIONS.md`); `test-decision-format.mjs` holds it to the shared fixture
// `contracts/fixtures/decisions.json`. The apps draw cards through astrid-core; this is only the
// scripts' check, so a question the loop writes is known to draw before it is posted.

const DECISION_HEAD = /^\*\*Decision:\*\*\s*(.*)$/;
const OPTION_LINE = /^\s*(?:[-*+]|\d+[.)])\s+(?:\*\*([A-Za-z]|\d{1,2})(?:[.):])?\*\*[.):]?)\s*(.*)$/;
const RECOMMENDED = /\s*\(recommended\)\s*$/i;
const LIST_ITEM = /^\s*(?:[-*+]|\d+[.)])\s/;
const LIST_PREFIX = /^\s*(?:[-*+]|\d+[.)])\s+/;

function indentWidth(line) {
  let width = 0;
  for (const ch of line) {
    if (ch === ' ') width++;
    else if (ch === '\t') width += 4 - (width % 4);
    else break;
  }
  return width;
}

function fenceOpener(line) {
  const body = LIST_PREFIX.test(line) ? line.replace(LIST_PREFIX, '') : line;
  if (body === line && indentWidth(line) >= 4) return null;
  const m = /^\s*(`{3,}|~{3,})(.*)$/.exec(body);
  if (!m) return null;
  if (m[1][0] === '`' && m[2].includes('`')) return null;
  return m[1];
}

/** Lines markdown draws as code: a fence, or four columns of indent after a blank line or code. */
function codeLineIndexes(lines) {
  const code = new Set();
  let fence = null;
  lines.forEach((line, i) => {
    if (fence) {
      code.add(i);
      const close = /^(`{3,}|~{3,})\s*$/.exec(line.trim())?.[1];
      if (close && close[0] === fence[0] && close.length >= fence.length) fence = null;
      return;
    }
    const opener = fenceOpener(line);
    if (opener) {
      fence = opener;
      code.add(i);
      return;
    }
    const prev = i === 0 ? '' : lines[i - 1];
    if (line.trim() !== '' && indentWidth(line) >= 4 && (prev.trim() === '' || code.has(i - 1))) code.add(i);
  });
  return code;
}

/** The Decision in a comment body, or null when it is not exactly that shape. */
export function parseDecision(content) {
  if (!content) return null;
  const lines = content.split('\n');
  const code = codeLineIndexes(lines);
  const headIndex = lines.findIndex((line, i) => !code.has(i) && DECISION_HEAD.test(line.trim()));
  if (headIndex < 0) return null;

  const promptLines = [DECISION_HEAD.exec(lines[headIndex].trim())[1]];
  let i = headIndex + 1;
  while (i < lines.length && lines[i].trim() !== '' && !LIST_ITEM.test(lines[i])) {
    promptLines.push(lines[i].trim());
    i++;
  }
  while (i < lines.length && lines[i].trim() === '') i++;

  const options = [];
  while (i < lines.length && !code.has(i) && LIST_ITEM.test(lines[i])) {
    const m = OPTION_LINE.exec(lines[i]);
    if (!m) return null; // every item starts with a bold letter or number
    let text = m[2].trim();
    const recommended = RECOMMENDED.test(text);
    if (recommended) text = text.replace(RECOMMENDED, '').trim();
    options.push({ letter: m[1].toUpperCase(), number: options.length + 1, text, recommended });
    i++;
  }
  if (options.length < 2) return null;

  return {
    before: lines.slice(0, headIndex).join('\n').trim(),
    prompt: promptLines.join(' ').trim(),
    options,
    after: lines.slice(i).join('\n').trim(),
  };
}
