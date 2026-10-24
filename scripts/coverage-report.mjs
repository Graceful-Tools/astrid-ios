#!/usr/bin/env node
// coverage-report.mjs — line coverage by directory, and a floor it may not drop below (AITD-541).
//
// Until 2026-10-22 nobody had measured coverage on this repo: no script asked for it. The iOS
// unit suite turned out to cover 19.7% of the app and the Mac suite 9.9% of the Mac app, with
// whole directories (Views/Settings, 14,888 lines) at zero. This makes the number visible on every
// run and turns a drop into a failure.
//
//   node scripts/coverage-report.mjs ios <result.xcresult> [--floor scripts/coverage-floor.json]
//   node scripts/coverage-report.mjs mac <result.xcresult> [--floor …]
//   node scripts/coverage-report.mjs ios --report-json report.json   # xccov's JSON, already read
//
// It prints a table, writes build/coverage/<platform>.json (gitignored), and with --floor exits 1
// when a directory is below its minimum. Raising a floor is a deliberate edit to
// scripts/coverage-floor.json; lowering one needs a reason in the same file.
//
// The run must have been made with -enableCodeCoverage YES. On the Mac it must also be
// UNSANDBOXED — a sandboxed app writes no profile data and xccov answers "Failed to load coverage
// archive"; scripts/run-mac-tests.sh passes the build settings for that.

import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

/** The app target each platform's suite covers — its test bundles are not counted. */
export const APP_TARGETS = { ios: ['Astrid App.app', 'Astrid.appex'], mac: ['Astrid.app'] }

/** The directories the table reports, in order. A file counts toward every group it is under. */
export const GROUPS = [
  'Astrid App/Core/Services', 'Astrid App/Core/Sync', 'Astrid App/Core/Authentication',
  'Astrid App/Core/Networking', 'Astrid App/Core/Outbox', 'Astrid App/Core/Persistence',
  'Astrid App/Core/Layout', 'Astrid App/Core/Tasks', 'Astrid App/Core/Board', 'Astrid App/Core/Filters',
  'Astrid App/Core', 'Astrid App/Models', 'Astrid App/Views/Settings', 'Astrid App/Views',
  'Shared', 'Astrid', 'Astrid Mac/App', 'Astrid Mac/Commands', 'Astrid Mac/Views', 'Astrid Mac',
]

/** Group the files of an xccov report into the directories above, plus the whole target. */
export function summarize(report, platform, repoRoot) {
  const targets = (report.targets ?? []).filter((t) => APP_TARGETS[platform].includes(t.name))
  const totals = new Map()
  const add = (key, covered, executable) => {
    const entry = totals.get(key) ?? { covered: 0, executable: 0 }
    entry.covered += covered
    entry.executable += executable
    totals.set(key, entry)
  }
  for (const target of targets) {
    add(`target:${target.name}`, target.coveredLines ?? 0, target.executableLines ?? 0)
    for (const file of target.files ?? []) {
      const rel = path.relative(repoRoot, file.path)
      for (const group of GROUPS) {
        if (rel === group || rel.startsWith(`${group}/`)) add(group, file.coveredLines ?? 0, file.executableLines ?? 0)
      }
    }
  }
  const rows = []
  for (const [name, { covered, executable }] of totals) {
    if (executable === 0) continue
    rows.push({ name, covered, executable, percent: Math.round((covered / executable) * 1000) / 10 })
  }
  const order = (name) => (name.startsWith('target:') ? -1 : GROUPS.indexOf(name))
  return rows.sort((a, b) => order(a.name) - order(b.name))
}

/** Directories below their floor, as messages. A floor naming a directory with no data fails too. */
export function belowFloor(rows, floors) {
  const byName = new Map(rows.map((r) => [r.name, r]))
  const failures = []
  for (const [name, minimum] of Object.entries(floors ?? {})) {
    const row = byName.get(name)
    if (!row) failures.push(`${name}: no coverage data — was the run made with coverage, and is the path right?`)
    else if (row.percent < minimum) failures.push(`${name}: ${row.percent}% is below its floor of ${minimum}%`)
  }
  return failures
}

export function formatTable(platform, rows) {
  const width = Math.max(...rows.map((r) => r.name.length), 10)
  const lines = [`Coverage (${platform}):`]
  for (const r of rows) {
    lines.push(`  ${r.name.padEnd(width)}  ${String(r.percent.toFixed(1)).padStart(5)}%  ${String(r.covered).padStart(6)} / ${r.executable}`)
  }
  return lines.join('\n')
}

function main() {
  const args = process.argv.slice(2)
  const platform = args[0]
  if (!APP_TARGETS[platform]) { console.error('usage: coverage-report.mjs ios|mac <xcresult> [--floor file]'); return 2 }
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
  let floorFile = null
  let reportJson = null
  let xcresult = null
  for (let i = 1; i < args.length; i += 1) {
    if (args[i] === '--floor') floorFile = args[++i]
    else if (args[i] === '--report-json') reportJson = args[++i]
    else xcresult = args[i]
  }
  let report
  try {
    report = JSON.parse(reportJson
      ? fs.readFileSync(reportJson, 'utf8')
      : execFileSync('xcrun', ['xccov', 'view', '--report', '--json', xcresult], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 }))
  } catch (error) {
    console.error(`✗ No coverage in ${xcresult ?? reportJson}: ${String(error.message).split('\n')[0]}`)
    return 1
  }
  const rows = summarize(report, platform, repoRoot)
  console.log(formatTable(platform, rows))
  const outDir = path.join(repoRoot, 'build', 'coverage')
  fs.mkdirSync(outDir, { recursive: true })
  fs.writeFileSync(path.join(outDir, `${platform}.json`), JSON.stringify({ platform, measuredAt: new Date().toISOString(), rows }, null, 2))
  if (!floorFile) return 0
  const floors = JSON.parse(fs.readFileSync(floorFile, 'utf8'))[platform]
  const failures = belowFloor(rows, floors)
  if (failures.length) {
    console.log(`✗ Coverage dropped below its floor (${floorFile}):`)
    for (const f of failures) console.log(`    ${f}`)
    return 1
  }
  console.log(`✓ Coverage holds its floor (${Object.keys(floors ?? {}).length} directories)`)
  return 0
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  process.exit(main())
}
