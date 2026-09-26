#!/usr/bin/env node
//
// launchd shim for scripts/fixall-loop.sh.
//
// Two reasons, both load-bearing.
//
// 1. It self-locates. The repo is resolved from this file's own import.meta.url, which is
//    why scripts/launchd/cc.astrid.fixall.plist.template names exactly one path
//    (__REPO_ROOT__) and scripts/launchd/install.sh can fill it in for any checkout.
//
// 2. TCC, when the checkout sits somewhere protected. A /bin/zsh launched directly by
//    launchd has no access to ~/Documents, ~/Desktop or ~/Downloads, so git fails with
//    "Unable to read current working directory: Operation not permitted" before the run
//    starts. So launchd runs node, and node runs the real script.
//
// This comment used to add that "this node binary does hold that grant, and children
// inherit it". Do not rely on that: astrid-web's copy of this shim records the opposite
// result on 2026-09-19, where an ungranted /opt/homebrew/bin/node HUNG on readdirSync of
// the repo rather than failing, leaving the job in `state = running` forever. The grant
// belongs to whichever binary launchd executes and is not guaranteed to be there.
//
// The durable fix, taken 2026-09-25: keep the checkout out of TCC-protected directories.
// Outside them reason 2 does not apply and no Full Disk Access grant is needed. Reason 1
// still stands, so the shim stays.
//
// Do not "simplify" this away by pointing launchd straight at the shell script.
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const script = join(dirname(fileURLToPath(import.meta.url)), 'fixall-loop.sh')
const { status } = spawnSync('/bin/zsh', ['-l', script, ...process.argv.slice(2)], { stdio: 'inherit' })
process.exit(status ?? 1)
