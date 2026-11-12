// Self-tests for scripts/core/check-size.mjs (AITD-625), run by `npm run test:scripts`.

import assert from 'node:assert/strict'
import fs from 'node:fs'
import { test } from 'node:test'
import { BUDGET_FILE, SLICES, overBudget } from './core/check-size.mjs'

const budget = { zipBytes: 100, sliceBytes: { ios: 50, 'ios-sim': 60, macos: 70 } }

test('sizes at or under budget pass', () => {
  assert.deepEqual(overBudget(budget, { zip: 100, ios: 49, 'ios-sim': 60, macos: 1 }), [])
})

test('a size over budget is reported, naming the slice', () => {
  const over = overBudget(budget, { zip: 10, ios: 51 })
  assert.equal(over.length, 1)
  assert.match(over[0], /^ios: /)
})

test('a measured size with no budget is an error, not a silent pass', () => {
  assert.throws(() => overBudget(budget, { watchos: 1 }), /no budget for "watchos"/)
})

test('the committed budget covers the zip and every slice', () => {
  const committed = JSON.parse(fs.readFileSync(BUDGET_FILE, 'utf8'))
  assert.ok(committed.zipBytes > 0)
  for (const key of Object.keys(SLICES)) assert.ok(committed.sliceBytes[key] > 0, key)
})
