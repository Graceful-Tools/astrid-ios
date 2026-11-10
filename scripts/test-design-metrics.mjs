// Self-tests for scripts/report-design-metrics.mjs (AITD-608), run by `npm run test:scripts`.
//
// A metric that has quietly stopped matching anything reads as progress, which is worse than
// having no metric. So every metric gets a fixture that MUST trip it, and the ratchet gets a
// fixture tree that rises above its budget and must fail.

import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { BUDGET_FILE, METRICS, count, isCopy, lowered, measure, overBudget, withoutComments } from './report-design-metrics.mjs'

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const script = path.join(repo, 'scripts/report-design-metrics.mjs')
const metric = (id) => METRICS.find((m) => m.id === id)
const source = (text, rel = 'Astrid App/Views/Example.swift') => [{ path: rel, source: text }]
const n = (id, text, rel) => count(metric(id), source(text, rel))

const made = []
process.on('exit', () => { for (const dir of made) fs.rmSync(dir, { recursive: true, force: true }) })
function fixture(files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'design-metrics-'))
  made.push(root)
  for (const [rel, text] of Object.entries(files)) {
    fs.mkdirSync(path.join(root, path.dirname(rel)), { recursive: true })
    fs.writeFileSync(path.join(root, rel), text)
  }
  return root
}

test('every metric has a fixture that trips it', () => {
  const tripped = {
    colourLiterals: 'let a = Color(red: 0.1, green: 0.2, blue: 0.3); let b = Color(hex: "#fff"); let c = NSColor(red: 1, green: 0, blue: 0, alpha: 1)',
    namedSystemColours: '.foregroundColor(Color.blue); let x = UIColor.systemRed; let y = NSColor.white',
    fontSizes: '.font(.system(size: 14, weight: .bold))',
    cornerRadii: 'RoundedRectangle(cornerRadius: 8); view.cornerRadius(12)',
    paddingLiterals: '.padding(8).padding(.horizontal, 12).padding([.top, .leading], 4)',
    shadowLiterals: '.shadow(color: .black.opacity(0.1), radius: 4, y: 2)',
    durationLiterals: 'withAnimation(.easeInOut(duration: 0.2)) {}; .spring(response: 0.3)',
    darkSchemeTernaries: 'let c = colorScheme == .dark ? Color.white : Color.black',
    hardcodedCopy: 'Text("Add a comment..."); Button("Cancel") {}; .navigationTitle("Settings")',
    uniqueHardcodedStrings: 'Text("Add a comment"); Text("Add a comment")',
  }
  for (const m of METRICS) {
    assert.ok(tripped[m.id], `${m.id} needs a fixture here`)
    assert.ok(n(m.id, tripped[m.id]) > 0, `${m.id} did not fire on its fixture`)
  }
  assert.equal(n('colourLiterals', tripped.colourLiterals), 3)
  assert.equal(n('namedSystemColours', tripped.namedSystemColours), 3)
  assert.equal(n('cornerRadii', tripped.cornerRadii), 2)
  assert.equal(n('paddingLiterals', tripped.paddingLiterals), 3)
  assert.equal(n('durationLiterals', tripped.durationLiterals), 2)
  assert.equal(n('hardcodedCopy', tripped.hardcodedCopy), 3)
  assert.equal(n('uniqueHardcodedStrings', tripped.uniqueHardcodedStrings), 1)
})

test('the token is not a literal', () => {
  assert.equal(n('paddingLiterals', '.padding(Theme.spacing.md).padding(.horizontal, Theme.spacing.s4).padding()'), 0)
  assert.equal(n('cornerRadii', 'RoundedRectangle(cornerRadius: Theme.radius.md)'), 0)
  assert.equal(n('fontSizes', '.font(.system(size: MacTypography.body)).font(.body)'), 0)
  assert.equal(n('durationLiterals', 'withAnimation(.easeOut(duration: DetailPanelChrome.panelDuration))'), 0)
  assert.equal(n('namedSystemColours', 'Theme.accent; Color.primary; Color.clear; Color.accentColor'), 0)
})

test('a string key is not copy; a sentence or a capitalised word is', () => {
  assert.equal(isCopy('settings.account.no_name'), false)
  assert.equal(isCopy('•'), false)
  assert.equal(isCopy('\\(count)'), false)
  assert.equal(isCopy('Done'), true)
  assert.equal(isCopy('minutes left'), true)
  assert.equal(isCopy("\\(Brand.appName)'s AI Model"), true)
  assert.equal(n('hardcodedCopy', 'Text("settings.title"); Text(verbatim: "Raw"); Text(NSLocalizedString("a.b", comment: ""))'), 0)
})

test('a comment about a literal is not a literal; a URL in a string is not a comment', () => {
  const text = '// was Color.blue\n/* .padding(8) /* nested */ Color.red */\nlet url = "https://x.test/Color.blue"\n.padding(4)'
  assert.equal(n('namedSystemColours', text), 1, 'only the one inside the string literal')
  assert.equal(n('paddingLiterals', text), 1)
  assert.equal(withoutComments('a // b\nc').split('\n').length, 2, 'line structure kept')
  assert.equal(n('hardcodedCopy', '"""\nText("Not code")\n"""\nText("Real Copy")'), 2, 'multi-line strings stay strings')
})

test('the shared homes are exempt', () => {
  const text = 'static let surface = Color(red: 0.1, green: 0.1, blue: 0.1); .padding(4)'
  assert.equal(n('colourLiterals', text, 'Astrid App/Utilities/Theme.swift'), 0)
  assert.equal(n('colourLiterals', text, 'Astrid App/Core/Brand/Brand.swift'), 0)
  assert.equal(n('colourLiterals', text, 'Astrid App/Utilities/ThemeHelpers.swift'), 1)
})

test('the ratchet: a rise fails, a fall never raises, a missing budget fails', () => {
  const budget = { ios: { fontSizes: 2 }, mac: { fontSizes: 0 } }
  assert.deepEqual(overBudget({ ios: { fontSizes: 2 }, mac: { fontSizes: 0 } }, budget), [])
  assert.deepEqual(overBudget({ ios: { fontSizes: 3 }, mac: { fontSizes: 0 } }, budget),
    [{ target: 'ios', id: 'fontSizes', count: 3, budget: 2 }])
  assert.equal(overBudget({ ios: { cornerRadii: 0 } }, budget).length, 1, 'a new metric needs a budget')
  assert.deepEqual(lowered({ ios: { fontSizes: 1 }, mac: { fontSizes: 5 } }, budget),
    { ios: { fontSizes: 1 }, mac: { fontSizes: 0 } }, '--update lowers, never raises')
})

test('--check fails on a tree that rose above its budget, and passes at it', () => {
  const root = fixture({
    'Astrid App/Views/A.swift': 'Text("Hello there").font(.system(size: 12))',
    'Astrid Mac/Views/B.swift': '.padding(4)',
  })
  const run = (...args) => spawnSync(process.execPath, [script, '--root', root, ...args], { encoding: 'utf8' })
  assert.equal(run('--update').status, 0)
  assert.equal(JSON.parse(fs.readFileSync(path.join(root, BUDGET_FILE), 'utf8')).ios.fontSizes, 1)
  assert.equal(run('--check').status, 0)
  fs.appendFileSync(path.join(root, 'Astrid Mac/Views/B.swift'), '\n.padding(8)')
  const failed = run('--check')
  assert.equal(failed.status, 1)
  assert.match(failed.stdout, /mac\.paddingLiterals rose to 2 \(budget 1\)/)
  assert.equal(run('--update').status, 0)
  assert.equal(JSON.parse(fs.readFileSync(path.join(root, BUDGET_FILE), 'utf8')).mac.paddingLiterals, 1, 'not raised')
})

test('this checkout is within its committed budget', () => {
  const budget = JSON.parse(fs.readFileSync(path.join(repo, BUDGET_FILE), 'utf8'))
  assert.deepEqual(overBudget(measure(repo), budget), [])
})
