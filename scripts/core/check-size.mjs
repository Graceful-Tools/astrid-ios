#!/usr/bin/env node
// Is the astrid-core framework still inside its size budget (AITD-625)?
//
//   node scripts/core/check-size.mjs            # predeploy: the released zip Xcode Cloud downloads,
//                                               # plus the local framework's slices if one is built
//   node scripts/core/check-size.mjs --built    # build-xcframework.sh: build/core's slices and zip
//
// Budgets live in scripts/core/size-budget.json. The staticlib used to be 96 MB for ios-arm64, of
// which 65 MB was embedded bitcode that the linker throws away — and nothing noticed, because
// nothing measured it. A rise past the budget fails here; a deliberate rise edits the budget in
// the same commit, with the reason.
//
// Offline, the released-zip half is a visible skip, like `check:version`.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
export const BUDGET_FILE = path.join(ROOT, 'scripts/core/size-budget.json')
const LIB = 'libastrid_apple.a'

// Where each slice sits in build/core (--built) and inside the XCFramework.
export const SLICES = {
  ios: { built: 'ios', framework: 'ios-arm64' },
  'ios-sim': { built: 'ios-sim', framework: 'ios-arm64_x86_64-simulator' },
  macos: { built: 'macos', framework: 'macos-arm64_x86_64' },
}

const mb = (bytes) => `${(bytes / 1e6).toFixed(1)} MB`

/** Every measured size above its budget, as messages. `sizes` maps a budget key to bytes. */
export function overBudget(budget, sizes) {
  const limits = { zip: budget.zipBytes, ...budget.sliceBytes }
  const over = []
  for (const [key, bytes] of Object.entries(sizes)) {
    const limit = limits[key]
    if (limit === undefined) throw new Error(`no budget for "${key}" in ${path.relative(ROOT, BUDGET_FILE)}`)
    if (bytes > limit) over.push(`${key}: ${mb(bytes)} is over its ${mb(limit)} budget`)
  }
  return over
}

function sliceSizes(dirFor) {
  const sizes = {}
  for (const [key, where] of Object.entries(SLICES)) {
    const file = path.join(dirFor(where), LIB)
    if (fs.existsSync(file)) sizes[key] = fs.statSync(file).size
  }
  return sizes
}

async function releasedZipSize() {
  const pkg = fs.readFileSync(path.join(ROOT, 'Packages/AstridCore/Package.swift'), 'utf8')
  const url = pkg.match(/^let releasedURL = "([^"]+)"/m)?.[1]
  if (!url) throw new Error('no releasedURL in Packages/AstridCore/Package.swift')
  try {
    const res = await fetch(url, { method: 'HEAD', redirect: 'follow', signal: AbortSignal.timeout(15000) })
    if (!res.ok) return { error: `HEAD ${url} answered ${res.status}` }
    const length = Number(res.headers.get('content-length'))
    return Number.isFinite(length) && length > 0 ? { bytes: length } : { skipped: 'no content-length' }
  } catch (e) {
    return { skipped: `offline (${e.cause?.code ?? e.name})` }
  }
}

async function main() {
  const budget = JSON.parse(fs.readFileSync(BUDGET_FILE, 'utf8'))
  const built = process.argv.includes('--built')
  let sizes
  const notes = []
  if (built) {
    const out = path.join(ROOT, 'build/core')
    sizes = sliceSizes((w) => path.join(out, w.built))
    const zip = path.join(out, 'AstridCoreFFI.xcframework.zip')
    if (fs.existsSync(zip)) sizes.zip = fs.statSync(zip).size
    if (Object.keys(sizes).length === 0) {
      console.error('RESULT: FAILED — nothing in build/core to measure; run scripts/core/build-xcframework.sh')
      process.exit(1)
    }
  } else {
    const local = path.join(ROOT, 'Packages/AstridCore/AstridCoreFFI.xcframework')
    sizes = fs.existsSync(local) ? sliceSizes((w) => path.join(local, w.framework)) : {}
    const zip = await releasedZipSize()
    if (zip.error) {
      console.error(`RESULT: FAILED — ${zip.error}`)
      process.exit(1)
    }
    if (zip.bytes) sizes.zip = zip.bytes
    else notes.push(`released zip SKIPPED — ${zip.skipped}`)
  }

  for (const [key, bytes] of Object.entries(sizes)) console.log(`  ${key.padEnd(8)} ${mb(bytes)}`)
  const over = overBudget(budget, sizes)
  if (over.length) {
    for (const line of over) console.error(`  ✗ ${line}`)
    console.error('RESULT: FAILED — astrid-core framework over its size budget (scripts/core/size-budget.json)')
    process.exit(1)
  }
  console.log(`RESULT: OK — astrid-core framework within budget${notes.length ? `; ${notes.join('; ')}` : ''}`)
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((e) => {
    console.error(`RESULT: FAILED — ${e.message}`)
    process.exit(1)
  })
}
