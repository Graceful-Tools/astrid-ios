#!/usr/bin/env node
// Contact sheet for the high-fidelity frames: one row per metaphor, Inbox → Done, alternating
// light and dark rows so both themes are checked. Writes hifi/contact-sheet.jpg.
import { existsSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const webDir = process.env.ASTRID_WEB_DIR || resolve(HERE, '../../../../../astrid-web')
const sharp = createRequire(join(webDir, 'package.json'))('sharp')

const METAPHORS = ['race', 'wall', 'chef', 'garden', 'hike']
const STATES = ['inbox', 'ready', 'doing', 'waiting', 'done']
const T = 200, PAD = 10
const W = STATES.length * (T + PAD) + PAD, H = METAPHORS.length * (T + PAD) + PAD

const bands = METAPHORS.map((_, r) =>
  `<rect x="0" y="${r * (T + PAD)}" width="${W}" height="${T + 2 * PAD}" fill="${r % 2 ? '#1C1C1E' : '#F4F1EC'}"/>`).join('')
const base = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">${bands}</svg>`)

const tiles = []
for (const [r, m] of METAPHORS.entries()) for (const [c, s] of STATES.entries()) {
  const f = join(HERE, 'webp', `${m}-${s}.webp`)
  if (!existsSync(f)) continue
  tiles.push({ input: await sharp(f).resize(T, T).png().toBuffer(), left: PAD + c * (T + PAD), top: PAD + r * (T + PAD) })
}
await sharp(base).composite(tiles).jpeg({ quality: 85 }).toFile(join(HERE, 'contact-sheet.jpg'))
console.log(`contact-sheet.jpg: ${tiles.length} frames`)
