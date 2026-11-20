#!/usr/bin/env node
// Render the high-fidelity empathy-state frames (ADEV-127, fifth pass).
//
// Each frame is an image-model render of the vector pose in ../svg/<metaphor>-<state>.svg, in the
// look of the app icon (Assets.xcassets/AppIcon.appiconset/icon-1024x1024.png). Both go to the
// model as references: the icon fixes the character, the vector fixes the pose, props and marker.
//
//   node docs/design/empathy-states/hifi/render.mjs [race-ready ...] [--quality high|medium]
//
// Needs OPENAI_API_KEY (read from the paired astrid-web/.env.local when not in the environment)
// and `sharp` from that checkout. Writes hifi/png/<metaphor>-<state>.png (1024², transparent,
// gitignored) and the committed hifi/webp/<metaphor>-<state>.webp. Then run contact.mjs.
// Re-running skips frames already on disk; name a frame to redo it.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../../../..')
const webDir = process.env.ASTRID_WEB_DIR || resolve(ROOT, '../astrid-web')
const sharp = createRequire(join(webDir, 'package.json'))('sharp')

function apiKey() {
  if (process.env.OPENAI_API_KEY) return process.env.OPENAI_API_KEY
  const env = readFileSync(join(webDir, '.env.local'), 'utf8')
  const m = env.match(/^OPENAI_API_KEY=["']?([^"'\n]+)/m)
  if (!m) throw new Error('OPENAI_API_KEY not set and not in astrid-web/.env.local')
  return m[1].trim()
}

const MARKERS = {
  inbox: 'a small glowing yellow light bulb',
  ready: 'a small traffic light with only the green lamp lit',
  doing: 'a small rounded progress bar about two-thirds filled with green',
  waiting: 'a small round wall clock',
  done: 'a small rounded white checkbox with a bold lime-green tick, the same green check as the icon',
}

const SCENES = {
  race: {
    inbox: 'reading a race flyer held in its arms, curious',
    ready: 'wearing running shoes on its front tentacles, crouched in a sprinter start on a short stretch of red running track with a white start line',
    doing: 'wearing running shoes, mid-sprint, leaning forward with determination, a few speed lines',
    waiting: 'wearing running shoes, sitting and calmly sipping from a water bottle, taking a break',
    done: 'wearing running shoes, standing on a gold podium block with a star on it, wearing a gold medal, joyful',
  },
  wall: {
    inbox: 'holding and studying a rolled-out blue blueprint, curious',
    ready: 'wearing a yellow hard hat, holding a trowel up, a small stack of bricks beside it',
    doing: 'wearing a yellow hard hat, laying a brick on a half-built low brick wall with a trowel, focused',
    waiting: 'wearing a yellow hard hat, leaning on the brick wall holding a coffee mug while the mortar sets, calm',
    done: 'wearing a yellow hard hat, proudly beside a finished small brick wall, joyful',
  },
  chef: {
    inbox: 'holding a recipe card, curious, thinking',
    ready: 'wearing a white chef hat and apron, beside a neat mise en place of chopped vegetables in small bowls',
    doing: 'wearing a white chef hat and apron, stirring a steaming pot with a wooden spoon, focused',
    waiting: 'wearing a white chef hat and apron, calmly watching a kitchen egg timer',
    done: 'wearing a white chef hat and apron, presenting a beautifully plated dish, joyful',
  },
  garden: {
    inbox: 'holding a seed packet, curious',
    ready: 'wearing a straw sun hat, holding a full watering can beside a small mound of dug soil',
    doing: 'wearing a straw sun hat, watering a patch of soil with a watering can, focused',
    waiting: 'wearing a straw sun hat, sitting calmly beside a pot where a tiny green sprout is coming up',
    done: 'wearing a straw sun hat, holding up a pot with a big bright flower in bloom, joyful',
  },
  hike: {
    inbox: 'holding a postcard showing a mountain, curious, dreaming',
    ready: 'wearing hiking boots and a small backpack, holding a trekking pole, beside a wooden trailhead signpost (no text)',
    doing: 'wearing hiking boots and a backpack, climbing an uphill rocky trail with a trekking pole, focused',
    waiting: 'wearing hiking boots, resting calmly on a rock, holding a thermos cup',
    done: 'wearing hiking boots and backpack, standing on a small mountain summit with a flag planted, joyful',
  },
}

const prompt = (m, s) => `A high-fidelity 3D render of the exact same character as the first reference image (the Astrid app icon mascot): a soft, glossy coral-red octopus with a rounded capsule body, big wide-set black eyes with white catchlights, a wide cream zigzag-tooth grin, no eyebrows, no outline, and fat round-ended tentacles that curl outward at the base. Match its face, body shape, proportions, color and soft clay-like 3D lighting precisely.

Pose and props follow the second reference image (a flat sketch of the scene): the octopus is ${SCENES[m][s]}. In the top-right corner, as a separate small icon, ${MARKERS[s]}.

No extra accessories beyond those named. Only the character, its costume and the props — no background, no ground plane, no scenery, no shadow box. Transparent background. Centered, the whole character visible with margin. No text, letters or numbers anywhere. Cute, friendly, polished app-illustration quality.`

const args = process.argv.slice(2)
// gpt-image-1.5: the newest model here that still renders a transparent background (2026-11-19)
const qi = args.indexOf('--quality')
const quality = qi >= 0 ? args.splice(qi, 2)[1] : 'high'
const only = new Set(args)
const outDir = join(HERE, 'png')
mkdirSync(outDir, { recursive: true })
mkdirSync(join(HERE, 'webp'), { recursive: true })

const icon = await sharp(join(ROOT, 'Astrid App/Assets.xcassets/AppIcon.appiconset/icon-1024x1024.png')).png().toBuffer()
const key = apiKey()

async function render(m, s) {
  const name = `${m}-${s}`
  const out = join(outDir, `${name}.png`)
  if (only.size ? !only.has(name) : existsSync(out)) return
  const sketch = await sharp(join(HERE, '../svg', `${name}.svg`)).resize(1024, 1024).flatten({ background: '#ffffff' }).png().toBuffer()
  const form = new FormData()
  form.append('model', process.env.IMAGE_MODEL || 'gpt-image-1.5')
  form.append('image[]', new Blob([icon], { type: 'image/png' }), 'icon.png')
  form.append('image[]', new Blob([sketch], { type: 'image/png' }), 'sketch.png')
  form.append('prompt', prompt(m, s))
  form.append('size', '1024x1024')
  form.append('quality', quality)
  form.append('background', 'transparent')
  for (let attempt = 1; ; attempt++) {
    const res = await fetch('https://api.openai.com/v1/images/edits', { method: 'POST', headers: { Authorization: `Bearer ${key}` }, body: form })
    const body = await res.json()
    if (res.ok) {
      const png = Buffer.from(body.data[0].b64_json, 'base64')
      writeFileSync(out, png)
      // the committed and served copy: ~100 KB instead of ~1.4 MB
      await sharp(png).webp({ quality: 88, alphaQuality: 100, effort: 6 }).toFile(join(HERE, 'webp', `${name}.webp`))
      console.log(`ok ${name}`, body.usage ? JSON.stringify(body.usage) : '')
      return
    }
    if (attempt >= 3 || res.status < 500 && res.status !== 429) throw new Error(`${name}: ${res.status} ${JSON.stringify(body.error ?? body)}`)
    await new Promise(r => setTimeout(r, 5000 * attempt))
  }
}

const jobs = Object.keys(SCENES).flatMap(m => Object.keys(MARKERS).map(s => [m, s]))
// four at a time: fast enough, and well under the rate limit
for (let i = 0; i < jobs.length; i += 4) await Promise.all(jobs.slice(i, i + 4).map(([m, s]) => render(m, s)))
