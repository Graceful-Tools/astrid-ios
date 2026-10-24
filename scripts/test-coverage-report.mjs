// Self-tests for scripts/coverage-report.mjs (AITD-541), run by `npm run test:scripts`.

import assert from 'node:assert/strict'
import { test } from 'node:test'
import { belowFloor, formatTable, summarize } from './coverage-report.mjs'

const root = '/repo'
const report = {
  targets: [
    { name: 'Astrid App.app', coveredLines: 30, executableLines: 100, files: [
      { path: '/repo/Astrid App/Core/Services/TaskService.swift', coveredLines: 20, executableLines: 40 },
      { path: '/repo/Astrid App/Core/Sync/Sync.swift', coveredLines: 0, executableLines: 10 },
      { path: '/repo/Astrid App/Views/Settings/Settings.swift', coveredLines: 0, executableLines: 50 },
      { path: '/repo/Astrid App/Core/ServicesHelper.swift', coveredLines: 10, executableLines: 10 },
    ] },
    { name: 'Astrid AppTests.xctest', coveredLines: 999, executableLines: 999, files: [
      { path: '/repo/Astrid AppTests/X.swift', coveredLines: 999, executableLines: 999 },
    ] },
  ],
}

test('groups files by directory and counts the app target only', () => {
  const rows = summarize(report, 'ios', root)
  const by = Object.fromEntries(rows.map((r) => [r.name, r]))
  assert.equal(by['target:Astrid App.app'].percent, 30)
  assert.equal(by['Astrid App/Core/Services'].percent, 50)
  assert.equal(by['Astrid App/Core/Sync'].percent, 0)
  assert.equal(by['Astrid App/Core'].executable, 60, 'a file counts toward every group it is under')
  assert.equal(by['Astrid App/Views/Settings'].percent, 0)
  assert.equal(rows.some((r) => r.name.includes('AppTests')), false, 'test bundles are not counted')
})

test('a sibling that only shares a prefix is not in the group', () => {
  const by = Object.fromEntries(summarize(report, 'ios', root).map((r) => [r.name, r]))
  assert.equal(by['Astrid App/Core/Services'].executable, 40, 'ServicesHelper.swift is not under Core/Services')
})

test('a directory below its floor fails, and a floor with no data fails', () => {
  const rows = summarize(report, 'ios', root)
  assert.deepEqual(belowFloor(rows, { 'Astrid App/Core/Services': 50 }), [])
  assert.equal(belowFloor(rows, { 'Astrid App/Core/Services': 50.1 }).length, 1)
  assert.match(belowFloor(rows, { 'Astrid App/Nowhere': 1 })[0], /no coverage data/)
})

test('the table names every row', () => {
  const table = formatTable('ios', summarize(report, 'ios', root))
  assert.match(table, /Astrid App\/Core\/Services\s+50\.0%/)
})
