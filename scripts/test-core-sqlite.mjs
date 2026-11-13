// Self-tests for scripts/core/check-sqlite.mjs (AITD-644), run by `npm run test:scripts`.

import assert from 'node:assert/strict'
import fs from 'node:fs'
import { test } from 'node:test'
import { definedSqliteSymbols } from './core/check-sqlite.mjs'

test('a bundled SQLite is seen through the symbols it defines', () => {
  const nm = [
    'libsqlite3-sys-1234.o:',
    '0000000000001a40 T _sqlite3_open_v2',
    '0000000000001b00 T _sqlite3_libversion',
    '0000000000002000 D _sqlite3_version',
  ].join('\n')
  assert.deepEqual(definedSqliteSymbols(nm), ['sqlite3_libversion', 'sqlite3_open_v2', 'sqlite3_version'])
})

test('references alone are the system SQLite, resolved by -lsqlite3', () => {
  const nm = ['rusqlite-1.o:', '                 U _sqlite3_open_v2', '                 U _sqlite3_close', '0000000000000010 T _uniffi_astrid_uniffi_fn_func_core_version'].join('\n')
  assert.deepEqual(definedSqliteSymbols(nm), [])
})

test('AITD-644: the apps take astrid-uniffi without its bundled-sqlite default', () => {
  const manifest = fs.readFileSync(new URL('../core/Cargo.toml', import.meta.url), 'utf8')
  const line = manifest.split('\n').find((l) => l.startsWith('astrid-uniffi = {'))
  assert.ok(line, 'no astrid-uniffi line in core/Cargo.toml')
  assert.match(line, /default-features = false/)
  assert.doesNotMatch(line, /bundled-sqlite/)
})

test('AITD-644: the bindings link the system libsqlite3 the staticlib now references', () => {
  const pkg = fs.readFileSync(new URL('../Packages/AstridCore/Package.swift', import.meta.url), 'utf8')
  assert.match(pkg, /\.linkedLibrary\("sqlite3"\)/)
})
