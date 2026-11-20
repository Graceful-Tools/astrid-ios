#!/usr/bin/env node
// report-design-metrics.mjs — how much of the iOS and Mac UI is written out by hand instead of
// asked of the design system and the string catalog (AITD-608).
//
//   npm run design:metrics                 # print the counts, iOS and Mac
//   npm run check:design                   # fail if any count rose above its budget (predeploy, CI)
//   npm run design:metrics -- --update     # lower the budgets to today's counts (never raises)
//   npm run design:metrics -- --json       # machine-readable counts
//   npm run design:metrics -- --root <dir> # count another checkout
//
// The mirror of astrid-web's `scripts/report-design-metrics.ts` (web PR #700). The rules being
// audited are astrid-web `docs/specs/DESIGN_SYSTEM.md` and the register in astrid-core
// `design/README.md`.
//
// Every count is a place where a value that has a shared home was typed out instead: a colour,
// a size, a duration, a sentence. Counts only go DOWN. A change that needs one more should have
// used `Theme` / `AstridTokens` or a `Localizable.strings` key. `--update` never raises a budget,
// so raising one is a hand edit to `scripts/design-metrics.budget.json`, and the commit message
// has to say why.
//
// Totals per metric per target, not per file: the direction is what matters, and a per-file table
// would be edited by every change.
//
// Self-tests: scripts/test-design-metrics.mjs, in `npm run test:scripts`. Each metric has a fixture
// that must trip it.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const BUDGET_FILE = 'scripts/design-metrics.budget.json'

/** The two app targets. `Astrid App/Core` is built into both but counted once, under iOS. */
export const TARGETS = {
  ios: ['Astrid App'],
  mac: ['Astrid Mac'],
}

/**
 * The shared homes: where a literal value is the DEFINITION, so it is not counted.
 * AstridTokens.swift is the vendored astrid-core register (AITD-605); Theme.swift maps it onto
 * the themes; Brand.swift holds the brand defaults (check-brand.sh polices those).
 */
export const EXEMPT = /(^|\/)(Theme|Brand|AstridTokens)\.swift$/

const SYSTEM_COLOURS =
  'red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|gray|grey|black|white'

/** Calls whose first argument is a colour, so `.green` there is `Color.green` (ADEV-167). */
const COLOUR_CALLS =
  'foregroundColor|foregroundStyle|tint|accentColor|fill|stroke|strokeBorder|background|' +
  'listRowBackground|border|overlay|backgroundStyle'

/** Dimension labels of a `.frame(…)`. */
const FRAME_DIMENSIONS = '(?:min|max|ideal)?(?:[Ww]idth|[Hh]eight)'

/**
 * Values of the vendored register that are distinctive enough to recognise when retyped: the
 * radii, and every fractional value with two significant decimals (1.28, 0.85, 0.22…). A plain
 * `8` or `0.5` is too common to attribute to one token; `cornerRadius: 14` or `1.28` is not.
 */
export function tokenValues(tokensSource) {
  const radii = new Set()
  const fractions = new Set()
  for (const [, name, value] of tokensSource.matchAll(/static let (\w+):\s*(?:CGFloat|Double)\s*=\s*(\d+(?:\.\d+)?)\b/g)) {
    if (/[Rr]adius$/.test(name)) radii.add(value)
    if (/^\d+\.\d[1-9]$/.test(value)) fractions.add(value)
  }
  const radiusBlock = tokensSource.match(/enum Radius \{([^}]*)\}/)
  for (const [, value] of radiusBlock?.[1].matchAll(/=\s*(\d+(?:\.\d+)?)/g) ?? []) radii.add(value)
  return { radii: [...radii], fractions: [...fractions] }
}

const esc = (value) => value.replace('.', '\\.')

/** The pattern for `tokenEqualLiterals`, built from the register in `root` (null: no register). */
export function tokenEqualPattern(tokensSource) {
  if (!tokensSource) return null
  const { radii, fractions } = tokenValues(tokensSource)
  const parts = []
  if (radii.length) parts.push(`cornerRadius(?::\\s*|\\(\\s*)(?:${radii.map(esc).join('|')})(?![\\d.])`)
  if (fractions.length) parts.push(`(?<![\\w.])(?:${fractions.map(esc).join('|')})(?![\\d])`)
  return parts.length ? new RegExp(parts.join('|'), 'g') : null
}

export const TOKENS_FILE = 'Astrid App/Utilities/AstridTokens.swift'

/**
 * The SwiftUI and AppKit calls whose first string argument is shown to a person. In SwiftUI a
 * literal there is a LocalizedStringKey, so a KEY (`"settings.title"`) is fine. A sentence
 * (`"Add a comment..."`) is English that no other language ever sees.
 */
const COPY_CALLS =
  'Text|Button|Label|TextField|SecureField|Toggle|Section|Menu|Picker|LabeledContent|' +
  'navigationTitle|alert|confirmationDialog|help|accessibilityLabel|accessibilityHint'
const COPY = new RegExp(`(?<![\\w.])\\.?(?:${COPY_CALLS})\\(\\s*"((?:[^"\\\\\\n]|\\\\.)*)"`, 'g')

/** A Localizable.strings key: dotted, lowercase. Not copy. */
const KEY = /^[a-z0-9_]+(?:\.[a-z0-9_-]+)+$/

/** Copy a person reads: two words, or one capitalised word of three letters or more. */
export function isCopy(literal) {
  if (KEY.test(literal)) return false
  const text = literal.replace(/\\\([^)]*\)/g, ' ').trim() // drop interpolations
  if (/[A-Za-z]{2,}\s+[A-Za-z]{2,}/.test(text)) return true
  return /^[A-Z][a-z]{2,}\b/.test(text)
}

export const METRICS = [
  {
    id: 'colourLiterals',
    what: 'colours written out: Color(red:…), Color(hex…), UIColor/NSColor(red:…)',
    instead: 'a Theme colour (AstridTokens); Brand.* for the brand',
    pattern: /\b(?:Color|UIColor|NSColor)\(\s*(?:red:|hex|\.sRGB|white:\s*[\d.])/g,
  },
  {
    id: 'namedSystemColours',
    what: 'named system colours (Color.blue, .systemBlue, …)',
    instead: 'a Theme colour, a status or priority token',
    pattern: new RegExp(
      `\\b(?:Color\\.(?:${SYSTEM_COLOURS})|(?:UI|NS)Color\\.(?:system[A-Z]\\w*|${SYSTEM_COLOURS}))\\b`,
      'g',
    ),
  },
  {
    // ADEV-167: `.foregroundColor(.green)` is Color.green without the prefix, and the pattern
    // above needs the prefix, so ~160 sites passed uncounted.
    id: 'shorthandSystemColours',
    what: 'shorthand system colours in a colour argument (.foregroundColor(.green), color: .black)',
    instead: 'a Theme colour, a status or priority token',
    pattern: new RegExp(
      `(?:\\.(?:${COLOUR_CALLS})\\(\\s*|\\bcolor:\\s*)\\.(?:${SYSTEM_COLOURS})\\b`,
      'g',
    ),
  },
  {
    // ADEV-167: the Mac writes `.macFont(.system(size: 13))`, which `.font(` never matched.
    id: 'fontSizes',
    what: '.font(.system(size: N…) and .macFont(.system(size: N…)',
    instead: 'a text style, or the type scale (TypeSize)',
    pattern: /\.(?:font|macFont)\(\s*\.system\(\s*size:\s*\d/g,
  },
  {
    id: 'cornerRadii',
    what: 'literal corner radii',
    instead: 'the radius scale',
    pattern: /cornerRadius(?::\s*|\(\s*)\d/g,
  },
  {
    id: 'paddingLiterals',
    what: '.padding( with a number',
    instead: 'the spacing scale',
    pattern: /\.padding\(\s*(?:(?:\.[A-Za-z]+|\[[^\]\n]*\])\s*,\s*)?\d/g,
  },
  {
    id: 'spacingLiterals',
    what: 'stack and grid spacing: N',
    instead: 'the spacing scale (AstridTokens.Space)',
    pattern: /\bspacing:\s*\d/g,
  },
  {
    id: 'opacityLiterals',
    what: '.opacity( with a number',
    instead: 'a state token (disabledOpacity, completedMarkOpacity, …) or a palette colour',
    pattern: /\.opacity\(\s*\.?\d/g,
  },
  {
    id: 'lineWidthLiterals',
    what: 'lineWidth: N',
    instead: 'a size token (hairline, selectionOutline)',
    pattern: /\blineWidth:\s*\.?\d/g,
  },
  {
    id: 'frameLiterals',
    what: '.frame( with a literal width or height',
    instead: 'a size or layout token',
    pattern: new RegExp(`\\.frame\\([^)\\n]*?\\b${FRAME_DIMENSIONS}:\\s*\\d`, 'g'),
  },
  {
    // ADEV-167: a value the register already names, typed out again (1.28, cornerRadius: 14).
    // Built from AstridTokens.swift by `measure`, so it follows the register.
    id: 'tokenEqualLiterals',
    what: 'literals equal to a register value (cornerRadius: 14, 1.28, 0.85)',
    instead: 'the token that holds that value',
    pattern: null,
  },
  {
    id: 'shadowLiterals',
    what: '.shadow( with literal values',
    instead: 'a shadow token',
    pattern: /\.shadow\([^)\n]*\d/g,
  },
  {
    id: 'durationLiterals',
    what: 'animation durations written out (duration: 0.2, response: 0.3)',
    instead: 'a motion token (motion.fast, motion.panel, …)',
    pattern: /\b(?:duration|response):\s*\.?\d/g,
  },
  {
    id: 'darkSchemeTernaries',
    what: '`colorScheme == .dark ?` ternaries',
    instead: 'one palette per theme, resolved once (register DS8)',
    pattern: /colorScheme\s*==\s*\.dark\s*\?/g,
  },
  {
    // AITD-623. The ternaries above reached 0 (AITD-611), but the same two-arm pick survives as
    // a fixed palette read (`Theme.Dark.bgPrimary`) or a string comparison
    // (`effectiveTheme == "dark" ? …`). Neither can serve a fourth theme or a partner's.
    id: 'fixedThemePicks',
    what: 'fixed Theme.Dark.* / Theme.Ocean.* reads and `== "dark"` theme-string comparisons',
    instead: 'the resolved palette for the current theme (register DS8)',
    pattern: /\bTheme\.(?:Dark|Ocean)\.|[!=]=\s*"(?:dark|ocean|light)"/g,
  },
  {
    // ADEV-167 (register DS1, DS8). On iOS `Theme.textPrimary` is `light.textPrimary`, fixed, so
    // a view reading it shows light-theme text on Dark and Ocean. The Mac's is themed, so this
    // counts iOS only.
    id: 'staticThemeText',
    what: 'static Theme.text* reads (fixed to the light palette on iOS)',
    instead: 'the resolved palette for the current theme (register DS8)',
    pattern: /\bTheme\.text[A-Z]\w*/g,
    targets: ['ios'],
  },
  {
    id: 'hardcodedCopy',
    what: 'sentences typed into UI calls instead of a Localizable.strings key',
    instead: 'a Localizable.strings key in every language',
    pattern: COPY,
    filter: (match) => isCopy(match[1]),
  },
  {
    id: 'uniqueHardcodedStrings',
    what: 'distinct hardcoded sentences',
    instead: 'a Localizable.strings key in every language',
    pattern: COPY,
    filter: (match) => isCopy(match[1]),
    distinct: (match) => match[1].replace(/\s+/g, ' ').trim(),
  },
]

/**
 * Comments blanked out, line structure kept. String literals survive: `"https://x"` is not a
 * comment. A comment about a literal (`// was Color.blue`) is not a literal.
 */
export function withoutComments(source) {
  let out = ''
  let i = 0
  let inString = false
  let multiline = false
  while (i < source.length) {
    const c = source[i]
    if (inString) {
      if (c === '\\') { out += source.slice(i, i + 2); i += 2; continue }
      if (multiline ? source.startsWith('"""', i) : c === '"') {
        const close = multiline ? '"""' : '"'
        out += close; i += close.length; inString = false; continue
      }
      if (c === '\n' && !multiline) inString = false // unterminated: do not swallow the file
      out += c; i += 1; continue
    }
    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] !== '\n') { out += ' '; i += 1 }
      continue
    }
    if (source.startsWith('/*', i)) {
      let depth = 0 // Swift block comments nest
      do {
        if (source.startsWith('/*', i)) { depth += 1; out += '  '; i += 2 }
        else if (source.startsWith('*/', i)) { depth -= 1; out += '  '; i += 2 }
        else { out += source[i] === '\n' ? '\n' : ' '; i += 1 }
      } while (depth > 0 && i < source.length)
      continue
    }
    if (c === '"') {
      multiline = source.startsWith('"""', i)
      const open = multiline ? '"""' : '"'
      out += open; i += open.length; inString = true; continue
    }
    out += c; i += 1
  }
  return out
}

/** How many times `metric` fires across `files` ([{ path, source }]). */
export function count(metric, files) {
  if (!metric.pattern) return 0
  const seen = new Set()
  let total = 0
  for (const { path: rel, source } of files) {
    if (EXEMPT.test(rel)) continue
    for (const match of withoutComments(source).matchAll(metric.pattern)) {
      if (metric.filter && !metric.filter(match)) continue
      if (metric.distinct) seen.add(metric.distinct(match))
      else total += 1
    }
  }
  return metric.distinct ? seen.size : total
}

function swiftFiles(root, dir) {
  const out = []
  const walk = (rel) => {
    let entries
    try { entries = fs.readdirSync(path.join(root, rel), { withFileTypes: true }) } catch { return }
    for (const entry of entries) {
      const child = `${rel}/${entry.name}`
      if (entry.isDirectory()) {
        if (entry.name === 'build' || entry.name.startsWith('.')) continue
        walk(child)
      } else if (entry.name.endsWith('.swift')) {
        out.push({ path: child, source: fs.readFileSync(path.join(root, child), 'utf8') })
      }
    }
  }
  walk(dir)
  return out
}

/** { ios: { metricId: n }, mac: { … } } for the checkout at `root`. */
export function measure(root) {
  const tokensPath = path.join(root, TOKENS_FILE)
  const tokensSource = fs.existsSync(tokensPath) ? fs.readFileSync(tokensPath, 'utf8') : null
  const metrics = METRICS.map((m) =>
    m.id === 'tokenEqualLiterals' ? { ...m, pattern: tokenEqualPattern(tokensSource) } : m)
  const result = {}
  for (const [target, dirs] of Object.entries(TARGETS)) {
    const files = dirs.flatMap((dir) => swiftFiles(root, dir))
    result[target] = Object.fromEntries(metrics
      .filter((m) => !m.targets || m.targets.includes(target))
      .map((m) => [m.id, count(m, files)]))
  }
  return result
}

/** Every count above its budget. A metric with no budget is over: a new metric needs one. */
export function overBudget(counts, budget) {
  const over = []
  for (const [target, metrics] of Object.entries(counts)) {
    for (const [id, n] of Object.entries(metrics)) {
      const limit = budget?.[target]?.[id]
      if (limit === undefined || n > limit) over.push({ target, id, count: n, budget: limit })
    }
  }
  return over
}

/** Budgets lowered to `counts` where they fell. Never raised; a missing one is set. */
export function lowered(counts, budget) {
  const next = {}
  for (const [target, metrics] of Object.entries(counts)) {
    next[target] = {}
    for (const [id, n] of Object.entries(metrics)) {
      const limit = budget?.[target]?.[id]
      next[target][id] = limit === undefined ? n : Math.min(limit, n)
    }
  }
  return next
}

function main(argv) {
  const args = argv.slice(2)
  const rootIndex = args.indexOf('--root')
  const root = rootIndex >= 0
    ? path.resolve(args[rootIndex + 1])
    : path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
  const budgetPath = path.join(root, BUDGET_FILE)
  const budget = fs.existsSync(budgetPath) ? JSON.parse(fs.readFileSync(budgetPath, 'utf8')) : {}
  const counts = measure(root)

  if (args.includes('--json')) {
    console.log(JSON.stringify(counts, null, 2))
    return 0
  }

  if (args.includes('--update')) {
    const next = lowered(counts, budget)
    fs.mkdirSync(path.dirname(budgetPath), { recursive: true })
    fs.writeFileSync(budgetPath, `${JSON.stringify(next, null, 2)}\n`)
    const over = overBudget(counts, next)
    console.log(`Budgets written to ${BUDGET_FILE}.`)
    for (const o of over) {
      console.log(`  ${o.target}.${o.id}: ${o.count} is above its budget ${o.budget}. --update never raises one`)
    }
    return 0
  }

  const width = Math.max(...METRICS.map((m) => m.id.length))
  console.log(`${'metric'.padEnd(width)}   ${'iOS'.padStart(11)}   ${'Mac'.padStart(11)}`)
  const cell = (target, id) => {
    const n = counts[target][id]
    if (n === undefined) return '–'.padStart(11)
    const limit = budget?.[target]?.[id]
    return (limit === undefined ? `${n}` : `${n}/${limit}`).padStart(11)
  }
  for (const m of METRICS) console.log(`${m.id.padEnd(width)}   ${cell('ios', m.id)}   ${cell('mac', m.id)}`)
  console.log('(count/budget)')

  if (!args.includes('--check')) return 0

  const over = overBudget(counts, budget)
  if (over.length) {
    console.log('')
    for (const o of over) {
      const m = METRICS.find((metric) => metric.id === o.id)
      console.log(
        o.budget === undefined
          ? `✗ ${o.target}.${o.id} has no budget in ${BUDGET_FILE}: run with --update`
          : `✗ ${o.target}.${o.id} rose to ${o.count} (budget ${o.budget}): ${m.what}. Use ${m.instead}.`,
      )
    }
    console.log('Do not raise a budget to get a change through. Use the token or the string key.')
    return 1
  }
  const fell = Object.entries(counts).flatMap(([t, ms]) =>
    Object.entries(ms).filter(([id, n]) => n < budget[t][id]).map(([id]) => `${t}.${id}`))
  if (fell.length) {
    console.log(`\nFell below budget: ${fell.join(', ')}. Lock the gain in: npm run design:metrics -- --update`)
  }
  return 0
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv)
}
