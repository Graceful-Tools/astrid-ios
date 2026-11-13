#!/usr/bin/env node
// Does the astrid-core framework link the system SQLite rather than carrying its own (AITD-644)?
//
//   node scripts/core/check-sqlite.mjs            # predeploy: the local framework's slices, if built
//   node scripts/core/check-sqlite.mjs --built    # build-xcframework.sh: build/core's slices
//
// iOS and macOS ship libsqlite3, so the apps take astrid-uniffi with `default-features = false`
// (core/Cargo.toml), which drops astrid-core's `bundled-sqlite` and with it `rusqlite/bundled`.
// Bundled, the staticlib DEFINES the SQLite API (`T _sqlite3_open_v2`) — a second engine, about a
// megabyte a slice, and the way RUSTSEC-2026-0459 reached every native client at once. Linked to the
// system, the same symbols are only REFERENCED (`U`) and the app's `-lsqlite3` resolves them. A
// default feature quietly coming back would be invisible otherwise: everything still builds.

import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { SLICES } from './check-size.mjs'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const LIB = 'libastrid_uniffi.a'

/** The SQLite API symbols an `nm` listing DEFINES (anything but `U`), deduplicated. */
export function definedSqliteSymbols(nmText) {
  const defined = new Set()
  for (const line of nmText.split('\n')) {
    const m = line.trim().match(/^(?:[0-9a-fA-F]+\s+)?([A-Za-z])\s+_?(sqlite3_\w+)$/)
    if (m && m[1] !== 'U' && m[1] !== 'u') defined.add(m[2])
  }
  return [...defined].sort()
}

function main() {
  const built = process.argv.includes('--built')
  const dirFor = built
    ? (w) => path.join(ROOT, 'build/core', w.built)
    : (w) => path.join(ROOT, 'Packages/AstridCore/AstridCoreFFI.xcframework', w.framework)
  const checked = []
  const bundled = []
  for (const [key, where] of Object.entries(SLICES)) {
    const file = path.join(dirFor(where), LIB)
    if (!fs.existsSync(file)) continue
    // Exit 1 is normal here: rustc's `compiler_builtins` members carry LLVM bitcode newer than Apple's
    // nm reads, and it says so per member — while still listing every other member's symbols.
    const run = spawnSync('nm', ['-g', file], { encoding: 'utf8', maxBuffer: 512 * 1024 * 1024 })
    const nm = run.stdout ?? ''
    if (run.error || !nm.trim()) {
      console.error(`RESULT: FAILED — nm could not read ${path.relative(ROOT, file)}: ${run.error?.message ?? run.stderr?.split('\n')[0]}`)
      process.exit(1)
    }
    const defined = definedSqliteSymbols(nm)
    checked.push(key)
    if (defined.length) bundled.push(`${key}: defines ${defined.length} SQLite symbols (${defined.slice(0, 3).join(', ')}…)`)
  }
  if (checked.length === 0) {
    if (built) {
      console.error('RESULT: FAILED — nothing in build/core to check; run scripts/core/build-xcframework.sh')
      process.exit(1)
    }
    console.log('RESULT: SKIPPED — no local framework; the release is checked when it is built')
    return
  }
  if (bundled.length) {
    for (const line of bundled) console.error(`  ✗ ${line}`)
    console.error('RESULT: FAILED — the astrid-core framework bundles its own SQLite; take astrid-uniffi with default-features = false (core/Cargo.toml)')
    process.exit(1)
  }
  console.log(`RESULT: OK — ${checked.join(', ')} link the system SQLite`)
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) main()
