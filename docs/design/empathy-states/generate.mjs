#!/usr/bin/env node
// ADEV-127 — the Astrid octopus acting out each board state, in five metaphors.
//
//   node docs/design/empathy-states/generate.mjs
//
// Writes svg/<metaphor>-<state>.svg (512×512, transparent, no text, so any locale and any theme
// can use them) and contact-sheet.png (needs `sharp`; it is taken from the paired astrid-web
// checkout, ASTRID_WEB_DIR or ../astrid-web, since this repo has no node_modules of its own).
//
// Second pass, from Jon's reply on the task (2026-11-19): all five metaphors, but one per board so
// every column of a view speaks the same metaphor; only the character and a key object, no
// background; and the character drawn much closer to the icon's — its face, body and colour.
// The colours below are sampled from `astrid-web/public/images/astrid-character.png`.
//
// Exploration artwork for choosing a set. Nothing here is in the app bundle.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const W = 512

// ── palette: sampled from the icon character ─────────────────────────────────────────
const C = {
  // body, light to dark: the lit crown, the face, the shaded flank, the rim
  coralHi: '#FF8C76', coral: '#F66653', coralMid: '#F0594A', coralLow: '#DB3E34', coralRim: '#B92F2F',
  mouth: '#A8302A', teeth: '#FBEDE2', teethShade: '#D9B8A4',
  eye: '#2A1612', white: '#FFFFFF', blush: '#FF9A86',
  // the check
  lime: '#94BC29', limeHi: '#B9DA43', limeLow: '#6E9418',
  // props
  gold: '#F5C13D', goldDark: '#C9921A', wood: '#B97A4B', woodDark: '#8A5532',
  grey: '#AEB7C1', greyDark: '#5F6B78', steel: '#D3D9DF', blue: '#3E8EDE', blueDark: '#2F6FB0',
  water: '#7FD0F5', brick: '#C8553D', brickDark: '#99402E', soil: '#7A5236', leaf: '#5DBB4A',
  leafDark: '#3F8F34', paper: '#FFFDF6', pink: '#FF8FB1', orange: '#F28C28',
}

const STATES = {
  inbox: { label: 'Inbox' }, ready: { label: 'Ready' }, doing: { label: 'Doing' },
  waiting: { label: 'Waiting' }, done: { label: 'Done' },
}

// ── the octopus ──────────────────────────────────────────────────────────────────────
// Local coordinates: body centred on x=0, crown at y≈-150, tentacle tips at y≈+150.
// The icon's shape: a tall capsule with a round crown that flares a little toward the hem.
// Third pass (Jon, 2026-11-19: "the tentacle to look more like the original character"): the
// tentacles are no longer points cut into the hem but separate fat tubes with round ends, as in
// the icon — the inner ones fall down and slightly out, the outer pair sweep sideways and lift.
const BODY = `M -100 72 C -98 20 -92 -36 -90 -80 C -90 -140 -56 -160 0 -160
  C 56 -160 90 -140 90 -80 C 92 -36 98 20 100 72 Q 0 100 -100 72 Z`

// A tapered tube along a quadratic curve p0 → c → p1, w0 wide at p0 and w1 at p1, with a round end.
function tube([x0, y0], [cx, cy], [x1, y1], w0, w1) {
  const N = 18, left = [], right = []
  let dx = 0, dy = 0
  for (let i = 0; i <= N; i++) {
    const t = i / N, u = 1 - t
    const px = u * u * x0 + 2 * u * t * cx + t * t * x1
    const py = u * u * y0 + 2 * u * t * cy + t * t * y1
    dx = 2 * u * (cx - x0) + 2 * t * (x1 - cx)
    dy = 2 * u * (cy - y0) + 2 * t * (y1 - cy)
    const len = Math.hypot(dx, dy) || 1
    dx /= len; dy /= len
    const w = (w0 + (w1 - w0) * t) / 2
    left.push([px - dy * w, py + dx * w])
    right.push([px + dy * w, py - dx * w])
  }
  const f = (p) => `${p[0].toFixed(1)} ${p[1].toFixed(1)}`
  const k = (w1 / 2) * 1.33
  const L = left[N], R = right[N]
  return `M ${f(left[0])} ` + left.slice(1).map((p) => `L ${f(p)}`).join(' ') +
    ` C ${f([L[0] + dx * k, L[1] + dy * k])} ${f([R[0] + dx * k, R[1] + dy * k])} ${f(R)} ` +
    right.slice(0, N).reverse().map((p) => `L ${f(p)}`).join(' ') + ' Z'
}

// [start, control, end, base width, tip width], back to front.
const TENTACLES = [
  [[-20, 40], [-24, 112], [-34, 152], 64, 48],
  [[24, 40], [30, 112], [42, 150], 64, 48],
  [[-58, 36], [-76, 104], [-100, 138], 62, 46],
  [[62, 36], [82, 102], [106, 134], 62, 46],
  [[-84, 30], [-112, 104], [-170, 94], 58, 40],
  [[86, 30], [114, 100], [168, 88], 58, 40],
]
const TENTACLE_PATHS = TENTACLES.map(([a, c, b, w0, w1]) => tube(a, c, b, w0, w1))

const eye = (x, y, [lx, ly]) =>
  `<ellipse cx="${x + lx}" cy="${y + ly}" rx="13" ry="17" fill="${C.eye}"/>` +
  `<ellipse cx="${x + lx + 4}" cy="${y + ly - 6}" rx="4.6" ry="5.4" fill="${C.white}"/>`

// Shut in delight: the icon's eyes curved into arcs.
const happyEye = (x, y) =>
  `<path d="M ${x - 14} ${y + 5} Q ${x} ${y - 14} ${x + 14} ${y + 5}" fill="none" stroke="${C.eye}" stroke-width="6.5" stroke-linecap="round"/>`

// Resting, patient.
const restEye = (x, y) =>
  `<path d="M ${x - 14} ${y - 2} Q ${x} ${y + 11} ${x + 14} ${y - 2}" fill="none" stroke="${C.eye}" stroke-width="6.5" stroke-linecap="round"/>`

// The icon's grin: a wide mouth full of cream teeth that meet in a zigzag.
function grin(w, top, bottom, n) {
  const x0 = -w, x1 = w
  const mid = (top + bottom) / 2 + 2
  const shape = `M ${x0} ${top} Q 0 ${top + 6} ${x1} ${top} Q ${x1 - 6} ${bottom} 0 ${bottom + 2} Q ${x0 + 6} ${bottom} ${x0} ${top} Z`
  let zig = `M ${x0 + 4} ${mid}`
  const step = (x1 - x0 - 8) / n
  for (let i = 1; i <= n; i++) zig += ` L ${x0 + 4 + step * (i - 0.5)} ${mid + (i % 2 ? -6 : 6)} L ${x0 + 4 + step * i} ${mid}`
  return `<path d="${shape}" fill="${C.mouth}"/>` +
    `<path d="M ${x0 + 3} ${top + 2} Q 0 ${top + 7} ${x1 - 3} ${top + 2} Q ${x1 - 8} ${bottom - 3} 0 ${bottom - 1} Q ${x0 + 8} ${bottom - 3} ${x0 + 3} ${top + 2} Z" fill="${C.teeth}"/>` +
    `<path d="${zig}" fill="none" stroke="${C.teethShade}" stroke-width="3.4" stroke-linejoin="round"/>`
}

const EYE_Y = -58, EYE_X = 40
const FACES = {
  // the icon's own face
  grin: (look) => eye(-EYE_X, EYE_Y, look) + eye(EYE_X, EYE_Y, look) + grin(56, -26, 22, 7),
  // concentrating: the same grin, set narrower
  focus: (look) => eye(-EYE_X, EYE_Y + 2, look) + eye(EYE_X, EYE_Y + 2, look) + grin(40, -22, 10, 5),
  // just arrived, a little curious: a small "oh"
  curious: (look) => eye(-EYE_X, EYE_Y - 2, look) + eye(EYE_X, EYE_Y - 2, look) +
    `<ellipse cx="0" cy="-8" rx="13" ry="15" fill="${C.mouth}"/><ellipse cx="0" cy="-3" rx="8" ry="6" fill="#C2453C"/>`,
  // patient: eyes at rest, a closed smile, a little blush
  calm: () => restEye(-EYE_X, EYE_Y) + restEye(EYE_X, EYE_Y) +
    `<path d="M -26 -16 Q 0 4 26 -16" fill="none" stroke="${C.mouth}" stroke-width="6.5" stroke-linecap="round"/>` +
    `<ellipse cx="-64" cy="-14" rx="12" ry="7" fill="${C.blush}" opacity=".7"/><ellipse cx="64" cy="-14" rx="12" ry="7" fill="${C.blush}" opacity=".7"/>`,
  // delighted: eyes shut, the grin at its widest
  joy: () => happyEye(-EYE_X, EYE_Y) + happyEye(EYE_X, EYE_Y) + grin(60, -28, 28, 8) +
    `<ellipse cx="-68" cy="-14" rx="12" ry="7" fill="${C.blush}" opacity=".8"/><ellipse cx="68" cy="-14" rx="12" ry="7" fill="${C.blush}" opacity=".8"/>`,
}

// A tentacle arm from the body's side to a hand point (local coords), thick at the shoulder and
// tapering — the arm holding the icon's check.
function arm([tx, ty], side) {
  const ax = side === 'l' ? -78 : 78
  const ay = 34
  const bow = side === 'l' ? -34 : 34
  const cx = (ax + tx) / 2 + bow
  const cy = Math.max(ay, ty) + 20
  // the body's own gradient and a round shoulder, so the arm grows out of the body with no cut
  return `<path d="${tube([ax, ay], [cx, cy], [tx, ty], 40, 30)}" fill="url(#octoGrad)" stroke="${C.coralRim}" stroke-width="2.5" stroke-opacity=".4"/>` +
    `<circle cx="${ax}" cy="${ay}" r="18.5" fill="url(#octoGrad)"/>` +
    `<circle cx="${tx}" cy="${ty}" r="19" fill="url(#octoGrad)" stroke="${C.coralRim}" stroke-width="2.5" stroke-opacity=".4"/>`
}

/**
 * The octopus, positioned in scene coordinates.
 *   face: grin | focus | curious | calm | joy      look: pupil offset [x, y]
 *   arms: [{ side: 'l'|'r', to: [x, y] }] in LOCAL coords
 *   behind / feet / hat / onBody / front: extra SVG in local coords (feet sit over the tentacle tips)
 */
function octo({ x = 256, y = 268, s = 0.92, rot = 0, sy = 1, face = 'grin', look = [0, 0], arms = [], behind = '', feet = '', hat = '', onBody = '', front = '' }) {
  return `<g transform="translate(${x} ${y}) rotate(${rot}) scale(${s} ${s * sy})">` +
    behind +
    // body and tentacles share one gradient, so the body flows into them with no seam; a thin
    // darker edge on each tentacle separates the ones that overlap
    TENTACLE_PATHS.map((d) => `<path d="${d}" fill="url(#octoGrad)" stroke="${C.coralRim}" stroke-width="2.5" stroke-opacity=".45"/>`).join('') +
    feet +
    `<path d="${BODY}" fill="url(#octoGrad)"/>` +
    `<path d="${BODY}" fill="url(#sideShade)"/>` +
    // the soft sheen on the crown, as the icon is lit from the upper left
    `<ellipse cx="-30" cy="-118" rx="40" ry="20" fill="#fff" opacity=".10" transform="rotate(-20 -30 -118)"/>` +
    onBody +
    FACES[face](look) +
    hat +
    arms.map((a) => arm(a.to, a.side)).join('') +
    front +
    `</g>`
}

// ── props (scene coords unless noted) ────────────────────────────────────────────────
// The icon's check: lime, chunky, lit from above.
const check = (x, y, s = 1, rot = 0) =>
  `<g transform="translate(${x} ${y}) rotate(${rot}) scale(${s})">` +
  `<path d="M -46 2 L -14 34 L 52 -38" fill="none" stroke="${C.limeLow}" stroke-width="32" stroke-linecap="round" stroke-linejoin="round" transform="translate(2 6)"/>` +
  `<path d="M -46 2 L -14 34 L 52 -38" fill="none" stroke="${C.lime}" stroke-width="32" stroke-linecap="round" stroke-linejoin="round"/>` +
  `<path d="M -42 -4 L -14 22 L 46 -42" fill="none" stroke="${C.limeHi}" stroke-width="8" stroke-linecap="round" stroke-linejoin="round" opacity=".8"/></g>`

const motion = (x, y) => [0, 24, 48].map((d, i) =>
  `<path d="M ${x - 64 + i * 14} ${y + d} L ${x - i * 10} ${y + d}" stroke="${C.grey}" stroke-width="7" stroke-linecap="round" opacity=".7"/>`).join('')

const clockFace = (x, y, r = 26) =>
  `<circle cx="${x}" cy="${y}" r="${r}" fill="#fff" stroke="${C.greyDark}" stroke-width="5"/>` +
  `<path d="M ${x} ${y} L ${x} ${y - r * 0.62} M ${x} ${y} L ${x + r * 0.45} ${y + r * 0.2}" stroke="${C.eye}" stroke-width="4" stroke-linecap="round"/>`

const paper = (x, y, w, h, rot = 0, lines = 4, fill = C.paper) =>
  `<g transform="rotate(${rot} ${x + w / 2} ${y + h / 2})"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="5" fill="${fill}" stroke="${C.greyDark}" stroke-width="3"/>` +
  Array.from({ length: lines }, (_, i) => `<line x1="${x + 10}" y1="${y + 16 + i * ((h - 24) / lines)}" x2="${x + w - 10 - (i === lines - 1 ? w * 0.3 : 0)}" y2="${y + 16 + i * ((h - 24) / lines)}" stroke="${C.grey}" stroke-width="3" stroke-linecap="round"/>`).join('') + `</g>`

// ── wearables (local coords; crown at y≈-150) ────────────────────────────────────────
const headband = `<path d="M -92 -98 Q 0 -128 92 -98 L 94 -78 Q 0 -108 -94 -78 Z" fill="#fff"/><path d="M -93 -90 Q 0 -120 93 -90" stroke="${C.blue}" stroke-width="5" fill="none"/>`
const hardHat = `<path d="M -80 -112 Q -76 -184 0 -186 Q 76 -184 80 -112 Z" fill="${C.gold}"/><rect x="-104" y="-120" width="208" height="18" rx="9" fill="${C.goldDark}"/><path d="M -10 -184 L -10 -118 M 10 -184 L 10 -118" stroke="${C.goldDark}" stroke-width="6"/>`
const toque = `<rect x="-58" y="-158" width="116" height="36" rx="6" fill="#fff" stroke="#E2E2E2" stroke-width="3"/><circle cx="-42" cy="-180" r="32" fill="#fff"/><circle cx="0" cy="-196" r="38" fill="#fff"/><circle cx="42" cy="-180" r="32" fill="#fff"/><path d="M -36 -150 L -36 -128 M 0 -150 L 0 -128 M 36 -150 L 36 -128" stroke="#E2E2E2" stroke-width="3"/>`
const strawHat = `<ellipse cx="0" cy="-122" rx="132" ry="24" fill="#E9C46A"/><path d="M -66 -124 Q -62 -190 0 -192 Q 62 -190 66 -124 Z" fill="#F2D27E"/><path d="M -66 -136 Q 0 -150 66 -136 L 66 -124 Q 0 -138 -66 -124 Z" fill="${C.leafDark}"/>`
const apron = `<path d="M -60 30 L 60 30 L 72 110 Q 0 120 -72 110 Z" fill="#fff"/><path d="M -60 30 L -82 6 M 60 30 L 82 6" stroke="#fff" stroke-width="6"/><rect x="-18" y="56" width="36" height="20" rx="4" fill="none" stroke="#E2E2E2" stroke-width="3"/>`
const backpackStraps = `<path d="M -84 -40 Q -52 0 -70 60 M 84 -40 Q 52 0 70 60" stroke="${C.blue}" stroke-width="12" fill="none" stroke-linecap="round"/>`
const backpack = `<rect x="68" y="-70" width="70" height="110" rx="22" fill="${C.blue}"/><rect x="80" y="-20" width="46" height="34" rx="8" fill="${C.blueDark}"/>`
const medal = `<path d="M -24 18 L 0 62 L 24 18" fill="none" stroke="${C.blue}" stroke-width="12"/><circle cx="0" cy="74" r="20" fill="${C.gold}" stroke="${C.goldDark}" stroke-width="4"/>`

// ── key objects ──────────────────────────────────────────────────────────────────────
function bottle(x, y) {
  return `<rect x="${x}" y="${y}" width="30" height="62" rx="9" fill="${C.water}" stroke="${C.blue}" stroke-width="4"/><rect x="${x + 6}" y="${y - 12}" width="18" height="14" rx="4" fill="${C.blue}"/>`
}
function blueprint(x, y) {
  return `<rect x="${x}" y="${y}" width="172" height="104" rx="6" fill="${C.blue}" stroke="${C.blueDark}" stroke-width="4"/>` +
    `<path d="M ${x + 16} ${y + 18} H ${x + 156} M ${x + 16} ${y + 38} H ${x + 156} M ${x + 16} ${y + 58} H ${x + 156} M ${x + 16} ${y + 78} H ${x + 156} M ${x + 36} ${y + 8} V ${y + 96} M ${x + 76} ${y + 8} V ${y + 96} M ${x + 116} ${y + 8} V ${y + 96}" stroke="#9CC8F2" stroke-width="2"/>` +
    `<rect x="${x + 30}" y="${y + 28}" width="96" height="44" fill="none" stroke="#fff" stroke-width="4"/>`
}
function trowel(x, y) {
  return `<path d="M ${x} ${y} L ${x + 4} ${y - 30}" stroke="${C.woodDark}" stroke-width="10" stroke-linecap="round"/>` +
    `<path d="M ${x - 22} ${y - 30} L ${x + 30} ${y - 30} L ${x + 4} ${y - 92} Z" fill="${C.steel}" stroke="${C.greyDark}" stroke-width="4" stroke-linejoin="round"/>`
}
function brick(x, y, rot = 0) {
  return `<rect x="${x}" y="${y}" width="66" height="34" rx="4" fill="${C.brick}" stroke="${C.brickDark}" stroke-width="4" transform="rotate(${rot} ${x + 33} ${y + 17})"/>`
}
function wall(x, base, counts) {
  let s = ''
  counts.forEach((n, r) => {
    for (let c = 0; c < n; c++) {
      const bx = x + c * 46 + (r % 2 ? 23 : 0), by = base - (r + 1) * 28
      s += `<rect x="${bx}" y="${by}" width="44" height="26" rx="3" fill="${C.brick}" stroke="${C.brickDark}" stroke-width="3"/>`
    }
  })
  return s
}
function mug(x, y) {
  return `<rect x="${x}" y="${y}" width="40" height="44" rx="8" fill="#fff" stroke="${C.greyDark}" stroke-width="4"/><path d="M ${x + 40} ${y + 12} Q ${x + 60} ${y + 20} ${x + 40} ${y + 34}" stroke="${C.greyDark}" stroke-width="4" fill="none"/>` +
    `<path d="M ${x + 10} ${y - 14} Q ${x + 4} ${y - 26} ${x + 12} ${y - 36} M ${x + 26} ${y - 14} Q ${x + 20} ${y - 26} ${x + 28} ${y - 36}" stroke="${C.grey}" stroke-width="4" fill="none" stroke-linecap="round"/>`
}
function recipe(x, y, rot) { return paper(x, y, 74, 92, rot, 4, '#FFF8E1') }
function board(x, y) {
  return `<rect x="${x}" y="${y}" width="200" height="26" rx="8" fill="${C.wood}"/>` +
    `<circle cx="${x + 44}" cy="${y - 6}" r="18" fill="#E44D3A"/><path d="M ${x + 44} ${y - 24} l -6 -8 m 6 8 l 6 -8" stroke="${C.leafDark}" stroke-width="4"/>` +
    `<path d="M ${x + 90} ${y + 6} L ${x + 150} ${y - 6} L ${x + 150} ${y + 8} Z" fill="${C.orange}"/>` +
    `<circle cx="${x + 176}" cy="${y - 2}" r="13" fill="${C.leaf}"/>`
}
function pot(x, y) {
  return `<path d="M ${x} ${y} L ${x + 150} ${y} L ${x + 138} ${y + 76} L ${x + 12} ${y + 76} Z" fill="${C.greyDark}"/><rect x="${x - 10}" y="${y - 8}" width="170" height="16" rx="8" fill="#4A545F"/>` +
    [-26, 0, 26].map((d) => `<path d="M ${x + 75 + d} ${y - 18} Q ${x + 63 + d} ${y - 38} ${x + 75 + d} ${y - 58} Q ${x + 87 + d} ${y - 76} ${x + 75 + d} ${y - 94}" stroke="${C.grey}" stroke-width="6" fill="none" stroke-linecap="round" opacity=".8"/>`).join('')
}
function kitchenTimer(x, y) {
  return `<ellipse cx="${x}" cy="${y + 22}" rx="34" ry="10" fill="#D9731A"/><path d="M ${x - 34} ${y + 22} Q ${x - 36} ${y - 26} ${x} ${y - 30} Q ${x + 36} ${y - 26} ${x + 34} ${y + 22} Z" fill="${C.orange}"/>` +
    `<rect x="${x - 6}" y="${y - 42}" width="12" height="14" rx="3" fill="#D9731A"/><path d="M ${x} ${y - 12} L ${x} ${y + 6}" stroke="#fff" stroke-width="5" stroke-linecap="round"/>`
}
function plate(x, y) {
  return `<ellipse cx="${x}" cy="${y}" rx="86" ry="20" fill="#fff" stroke="#D5D5D5" stroke-width="4"/>` +
    `<ellipse cx="${x}" cy="${y - 10}" rx="46" ry="16" fill="#E9A23B"/><circle cx="${x - 20}" cy="${y - 20}" r="10" fill="#E44D3A"/><circle cx="${x + 10}" cy="${y - 24}" r="9" fill="${C.leaf}"/><circle cx="${x + 26}" cy="${y - 14}" r="7" fill="#E44D3A"/>`
}
function seedPacket(x, y, rot) {
  return `<g transform="rotate(${rot} ${x + 40} ${y + 50})"><rect x="${x}" y="${y}" width="80" height="100" rx="6" fill="${C.paper}" stroke="${C.wood}" stroke-width="4"/>` +
    `<rect x="${x}" y="${y}" width="80" height="16" fill="#E9C46A"/>` +
    `<path d="M ${x + 40} ${y + 92} L ${x + 40} ${y + 56}" stroke="${C.leafDark}" stroke-width="4"/>` +
    [0, 72, 144, 216, 288].map((a) => `<ellipse cx="${x + 40}" cy="${y + 38}" rx="7" ry="12" fill="${C.pink}" transform="rotate(${a} ${x + 40} ${y + 50})"/>`).join('') +
    `<circle cx="${x + 40}" cy="${y + 50}" r="7" fill="${C.gold}"/></g>`
}
function wateringCan(x, y, rot, drops) {
  return `<g transform="rotate(${rot} ${x + 40} ${y + 40})">` +
    `<path d="M ${x} ${y + 20} L ${x - 50} ${y - 10}" stroke="#4FA3E0" stroke-width="12" stroke-linecap="round"/><rect x="${x - 62}" y="${y - 22}" width="20" height="18" rx="4" fill="#4FA3E0" transform="rotate(-30 ${x - 52} ${y - 13})"/>` +
    `<rect x="${x}" y="${y}" width="84" height="70" rx="14" fill="#5DB0EE"/><path d="M ${x + 20} ${y} Q ${x + 42} ${y - 34} ${x + 64} ${y}" stroke="#4FA3E0" stroke-width="10" fill="none"/></g>` +
    (drops ? `<g fill="${C.water}">${drops.map(([dx, dy]) => `<ellipse cx="${dx}" cy="${dy}" rx="5" ry="8"/>`).join('')}</g>` : '')
}
function plantPot(x, y, plant) {
  return plant + `<path d="M ${x} ${y} L ${x + 80} ${y} L ${x + 70} ${y + 78} L ${x + 10} ${y + 78} Z" fill="#D9714E"/><rect x="${x - 8}" y="${y - 6}" width="96" height="20" rx="6" fill="#C25E3D"/>`
}
function sprout(x, y) {
  return `<path d="M ${x} ${y} L ${x} ${y - 40}" stroke="${C.leafDark}" stroke-width="6"/><path d="M ${x} ${y - 36} Q ${x - 30} ${y - 60} ${x - 34} ${y - 34} Q ${x - 14} ${y - 26} ${x} ${y - 36} Z" fill="${C.leaf}"/><path d="M ${x} ${y - 40} Q ${x + 30} ${y - 66} ${x + 36} ${y - 40} Q ${x + 16} ${y - 30} ${x} ${y - 40} Z" fill="${C.leaf}"/>`
}
function bloom(x, y) {
  const fy = y - 130
  return `<path d="M ${x} ${y} Q ${x - 8} ${y - 60} ${x} ${fy}" stroke="${C.leafDark}" stroke-width="8" fill="none"/>` +
    `<path d="M ${x - 2} ${y - 50} Q ${x - 50} ${y - 80} ${x - 56} ${y - 46} Q ${x - 26} ${y - 34} ${x - 2} ${y - 50} Z" fill="${C.leaf}"/>` +
    [0, 60, 120, 180, 240, 300].map((a) => `<ellipse cx="${x}" cy="${fy - 32}" rx="18" ry="32" fill="${C.pink}" transform="rotate(${a} ${x} ${fy})"/>`).join('') +
    `<circle cx="${x}" cy="${fy}" r="20" fill="${C.gold}"/>`
}
function flag(x, base) {
  return `<rect x="${x}" y="${base - 230}" width="10" height="230" rx="4" fill="${C.woodDark}"/><path d="M ${x + 10} ${base - 224} L ${x + 110} ${base - 196} L ${x + 10} ${base - 166} Z" fill="${C.lime}"/>`
}

// ── footwear (local coords): worn on the two front tentacle tips ────────────────────
// Fourth pass (Jon, 2026-11-19: "shoes for the Ready"): running shoes for the Race, hiking boots
// for the Hike, so the costume says which metaphor before the props do.
function shoe(x, y, dir, upper, sole, accent, extra = '') {
  return `<g transform="translate(${x} ${y}) scale(${dir * 1.35} 1.35)">` +
    `<path d="M -30 -20 Q -34 4 -30 12 L 36 12 Q 46 4 38 -4 Q 18 -8 6 -22 Q -12 -28 -30 -20 Z" fill="${upper}" stroke="rgba(0,0,0,.25)" stroke-width="2.5"/>` +
    `<rect x="-34" y="8" width="82" height="11" rx="5.5" fill="${sole}"/>` +
    `<path d="M -4 -16 l 10 6 M 4 -20 l 10 6 M 12 -14 l 8 5" stroke="${accent}" stroke-width="4" stroke-linecap="round"/>` +
    extra + `</g>`
}
const FRONT_TIPS = [[-42, 170, -1], [50, 168, 1]]
const runningShoes = FRONT_TIPS.map(([x, y, d]) => shoe(x, y, d, C.blue, '#fff', '#fff',
  `<path d="M -22 -2 q 18 -8 34 0" stroke="${C.lime}" stroke-width="5" fill="none" stroke-linecap="round"/>`)).join('')
const hikingBoots = FRONT_TIPS.map(([x, y, d]) => shoe(x, y, d, '#8A5A36', '#3A2A20', C.gold,
  `<rect x="-32" y="-30" width="44" height="12" rx="6" fill="#6E4527"/>`)).join('')

// ── race props ──────────────────────────────────────────────────────────────────────
// A short stretch of track: the lane, its edge lines and the white start line across it.
function startLine(base) {
  return `<path d="M 70 ${base - 46} L 442 ${base - 46} L 478 ${base + 10} L 34 ${base + 10} Z" fill="#D2603F"/>` +
    `<path d="M 152 ${base - 46} L 124 ${base + 10} M 360 ${base - 46} L 388 ${base + 10}" stroke="#fff" stroke-width="5" opacity=".85"/>` +
    `<path d="M 54 ${base - 8} L 458 ${base - 8}" stroke="#fff" stroke-width="12"/>`
}
// The winner's step, with a star where a number would be (no text).
function podium(x, base) {
  return `<rect x="${x}" y="${base - 70}" width="220" height="70" rx="8" fill="${C.gold}" stroke="${C.goldDark}" stroke-width="4"/>` +
    `<path d="M ${x + 110} ${base - 54} l 9 18 l 20 3 l -14 14 l 3 20 l -18 -9 l -18 9 l 3 -20 l -14 -14 l 20 -3 Z" fill="#fff" opacity=".9"/>`
}

// ── hike props ──────────────────────────────────────────────────────────────────────
const peak = (x, y, w, h, snow = true) =>
  `<path d="M ${x - w / 2} ${y} L ${x} ${y - h} L ${x + w / 2} ${y} Z" fill="#7C8A99"/>` +
  `<path d="M ${x} ${y - h} L ${x + w / 2} ${y} L ${x + w * 0.1} ${y} Z" fill="#62707F"/>` +
  (snow ? `<path d="M ${x - w * 0.14} ${y - h * 0.72} L ${x} ${y - h} L ${x + w * 0.14} ${y - h * 0.72} L ${x + w * 0.06} ${y - h * 0.78} L ${x} ${y - h * 0.7} L ${x - w * 0.06} ${y - h * 0.78} Z" fill="#fff"/>` : '')
// The idea: a postcard of the mountain.
function postcard(x, y, rot) {
  return `<g transform="rotate(${rot} ${x + 56} ${y + 40})"><rect x="${x}" y="${y}" width="112" height="80" rx="6" fill="#CFEAFB" stroke="${C.greyDark}" stroke-width="4"/>` +
    `<circle cx="${x + 86}" cy="${y + 22}" r="10" fill="${C.gold}"/>` +
    peak(x + 50, y + 76, 84, 56) + `<path d="M ${x + 2} ${y + 76} L ${x + 110} ${y + 76}" stroke="${C.leaf}" stroke-width="6"/></g>`
}
// The trailhead: a wooden post with an arrow plank that points up the trail, a mountain on it.
function trailSign(x, base) {
  const py = base - 200
  return `<rect x="${x - 7}" y="${py - 10}" width="14" height="${base - py + 10}" rx="4" fill="${C.woodDark}"/>` +
    `<path d="M ${x - 56} ${py - 30} L ${x + 40} ${py - 30} L ${x + 66} ${py} L ${x + 40} ${py + 30} L ${x - 56} ${py + 30} Z" fill="${C.wood}" stroke="${C.woodDark}" stroke-width="4" stroke-linejoin="round"/>` +
    `<path d="M ${x - 36} ${py + 18} L ${x - 10} ${py - 16} L ${x + 4} ${py + 2} L ${x + 14} ${py - 8} L ${x + 34} ${py + 18} Z" fill="#fff" opacity=".9"/>`
}
// A walking pole, from the hand down to the ground (scene coords).
const pole = (x1, y1, x2, y2) =>
  `<path d="M ${x1} ${y1} L ${x2} ${y2}" stroke="${C.greyDark}" stroke-width="8" stroke-linecap="round"/>` +
  `<path d="M ${x1 + (x1 - x2) * 0.04} ${y1 + (y1 - y2) * 0.04} L ${x1} ${y1}" stroke="#2E2E2E" stroke-width="14" stroke-linecap="round"/>`
// The trail going uphill under the hiker.
function trail() {
  return `<path d="M 20 500 L 20 470 Q 200 440 492 330 L 492 500 Z" fill="${C.leaf}" opacity=".9"/>` +
    `<path d="M 20 470 Q 200 440 492 330" stroke="${C.leafDark}" stroke-width="6" fill="none"/>` +
    `<path d="M 60 480 Q 230 448 470 360" stroke="#C9A46A" stroke-width="12" fill="none" stroke-dasharray="26 18" stroke-linecap="round"/>`
}
// A rest stop: a boulder to sit on and a thermos.
function boulder(x, base) {
  return `<path d="M ${x - 120} ${base} Q ${x - 124} ${base - 62} ${x - 60} ${base - 74} Q ${x} ${base - 92} ${x + 70} ${base - 70} Q ${x + 126} ${base - 54} ${x + 120} ${base} Z" fill="#9AA5B1"/>` +
    `<path d="M ${x - 70} ${base - 60} Q ${x - 20} ${base - 78} ${x + 40} ${base - 64}" stroke="#C3CBD3" stroke-width="8" fill="none" stroke-linecap="round"/>`
}
function thermos(x, y) {
  return `<rect x="${x}" y="${y}" width="32" height="70" rx="10" fill="${C.leafDark}"/><rect x="${x + 2}" y="${y - 14}" width="28" height="16" rx="4" fill="${C.greyDark}"/>` +
    `<rect x="${x + 4}" y="${y + 24}" width="24" height="10" rx="3" fill="#fff" opacity=".6"/>` +
    `<path d="M ${x + 10} ${y - 22} Q ${x + 4} ${y - 34} ${x + 12} ${y - 44} M ${x + 22} ${y - 22} Q ${x + 16} ${y - 34} ${x + 24} ${y - 44}" stroke="${C.grey}" stroke-width="4" fill="none" stroke-linecap="round"/>`
}

// ── the scenes: the character, its costume, and one key object ──────────────────────
const L = (x, y) => ({ side: 'l', to: [x, y] })
const R = (x, y) => ({ side: 'r', to: [x, y] })

const SCENES = {
  race: {
    title: 'Race',
    inbox: { caption: 'Reading the race flyer', draw: () =>
      octo({ x: 236, face: 'curious', look: [6, 4], arms: [R(118, 0), L(-108, 80)], front: paper(78, -60, 70, 86, 10, 3) }) },
    ready: { caption: 'Shoes on, at the start line', draw: () => startLine(470) +
      octo({ x: 256, y: 290, s: 0.86, sy: 0.86, face: 'focus', look: [0, 4], hat: headband, feet: runningShoes, arms: [R(104, 146), L(-104, 146)] }) },
    doing: { caption: 'Mid-sprint', draw: () => motion(140, 220) +
      octo({ x: 286, y: 262, rot: 12, face: 'focus', look: [8, 0], hat: headband, feet: runningShoes, arms: [R(128, -20), L(-128, 92)] }) },
    waiting: { caption: 'Water break between heats', draw: () =>
      octo({ x: 236, face: 'calm', hat: headband, feet: runningShoes, arms: [R(100, -20), L(-104, 96)], front: bottle(86, -76) }) },
    done: { caption: 'On the podium, medal on', draw: () => podium(146, 490) +
      octo({ x: 256, y: 252, s: 0.8, face: 'joy', hat: headband, feet: runningShoes, onBody: medal, arms: [R(140, -110), L(-140, -110)] }) },
  },
  wall: {
    title: 'Building a wall',
    inbox: { caption: 'Reading the blueprint', draw: () =>
      octo({ x: 256, face: 'curious', look: [0, 6], arms: [L(-82, 40), R(82, 40)], front: blueprint(-86, -10) }) },
    ready: { caption: 'Hard hat on, trowel up', draw: () =>
      octo({ x: 236, y: 290, s: 0.88, face: 'grin', look: [-4, 0], hat: hardHat, arms: [R(130, -50), L(-110, 90)], front: trowel(130, -50) }) },
    doing: { caption: 'Laying a brick', draw: () =>
      wall(28, 470, [4, 3, 2]) +
      octo({ x: 330, y: 290, s: 0.84, face: 'focus', look: [-8, 4], hat: hardHat, arms: [L(-150, -10), R(110, 90)], front: brick(-200, -36) }) },
    waiting: { caption: 'Letting the mortar set', draw: () =>
      octo({ x: 236, y: 290, s: 0.88, face: 'calm', hat: hardHat, arms: [L(-110, 60), R(104, -20)], front: mug(86, -44) }) },
    done: { caption: 'Wall finished', draw: () =>
      wall(18, 476, [5, 5, 5]) +
      octo({ x: 370, y: 270, s: 0.74, face: 'joy', hat: hardHat, arms: [L(-120, -120), R(124, -120)] }) },
  },
  chef: {
    title: 'Chef',
    inbox: { caption: 'Reading the recipe', draw: () =>
      octo({ x: 286, face: 'curious', look: [-6, 4], arms: [L(-86, 0), R(110, 80)], front: recipe(-150, -60, -8) }) },
    ready: { caption: 'Apron on, mise en place', draw: () =>
      octo({ x: 256, y: 250, s: 0.84, face: 'grin', hat: toque, onBody: apron, arms: [L(-120, 90), R(120, 90)] }) +
      board(156, 410) },
    doing: { caption: 'Stirring the pot', draw: () =>
      `<path d="M 186 300 L 136 340" stroke="${C.wood}" stroke-width="10" stroke-linecap="round"/>` +
      octo({ x: 330, y: 250, s: 0.82, face: 'focus', look: [-8, 6], hat: toque, onBody: apron, arms: [L(-150, 70), R(110, 90)] }) +
      pot(70, 340) },
    waiting: { caption: 'Watching the timer', draw: () =>
      octo({ x: 236, y: 280, s: 0.84, face: 'calm', hat: toque, onBody: apron, arms: [L(-106, 80), R(122, 0)] }) +
      kitchenTimer(372, 258) },
    done: { caption: 'Plated and served', draw: () =>
      octo({ x: 220, y: 290, s: 0.84, face: 'joy', hat: toque, onBody: apron, arms: [R(150, 10), L(-110, 80)], front: plate(170, 0) }) },
  },
  garden: {
    title: 'Garden',
    inbox: { caption: 'A packet of seeds', draw: () =>
      octo({ x: 286, face: 'curious', look: [-6, 6], arms: [L(-100, 0), R(110, 80)], front: seedPacket(-160, -70, -8) }) },
    ready: { caption: 'Hat on, can filled', draw: () =>
      octo({ x: 230, y: 280, s: 0.86, face: 'grin', hat: strawHat, arms: [L(-110, 90), R(100, 100)] }) +
      wateringCan(340, 360, 0) },
    doing: { caption: 'Watering', draw: () =>
      octo({ x: 330, y: 276, s: 0.86, face: 'focus', look: [-8, 6], hat: strawHat, arms: [L(-140, -10), R(100, 90)] }) +
      wateringCan(160, 220, -25, [[110, 330], [128, 352], [100, 362], [140, 320], [120, 300]]) },
    waiting: { caption: 'Waiting for the sprout', draw: () =>
      plantPot(110, 370, sprout(150, 370)) +
      octo({ x: 330, y: 280, s: 0.82, face: 'calm', hat: strawHat, arms: [L(-60, 60), R(60, 60)] }) },
    done: { caption: 'In full bloom', draw: () =>
      plantPot(90, 360, bloom(130, 360)) +
      octo({ x: 330, y: 280, s: 0.84, face: 'joy', hat: strawHat, arms: [L(-120, -10), R(130, -100)] }) },
  },
  hike: {
    title: 'Hike',
    inbox: { caption: 'A postcard of the mountain', draw: () =>
      octo({ x: 300, face: 'curious', look: [-6, 2], arms: [L(-110, -10), R(100, 90)], front: postcard(-196, -60, -8) }) },
    ready: { caption: 'Boots on, at the trailhead', draw: () =>
      trailSign(110, 470) +
      octo({ x: 300, y: 276, s: 0.86, face: 'grin', look: [-6, 0], behind: backpack, onBody: backpackStraps, feet: hikingBoots, arms: [L(-110, 80), R(110, 40)] }) +
      pole(396, 310, 420, 470) },
    doing: { caption: 'Climbing the trail', draw: () => trail() +
      octo({ x: 236, y: 250, s: 0.8, rot: 14, face: 'focus', look: [6, -2], behind: backpack, onBody: backpackStraps, feet: hikingBoots, arms: [L(-110, 60), R(130, 10)] }) +
      pole(352, 252, 382, 410) },
    waiting: { caption: 'Resting on a rock', draw: () =>
      boulder(236, 480) +
      octo({ x: 226, y: 262, s: 0.82, sy: 0.94, face: 'calm', behind: backpack, onBody: backpackStraps, feet: hikingBoots, arms: [L(-100, 100), R(150, 40)] }) +
      thermos(380, 330) },
    done: { caption: 'At the summit, flag planted', draw: () =>
      peak(256, 510, 500, 250) + flag(350, 354) +
      octo({ x: 236, y: 196, s: 0.6, face: 'joy', behind: backpack, onBody: backpackStraps, feet: hikingBoots, arms: [L(-130, -110), R(130, -110)] }) },
  },
}

// ── render ───────────────────────────────────────────────────────────────────────────
const DEFS = `<defs>
  <linearGradient id="octoGrad" gradientUnits="userSpaceOnUse" x1="0" y1="-160" x2="0" y2="168"><stop offset="0" stop-color="${C.coralHi}"/><stop offset="0.25" stop-color="${C.coral}"/><stop offset="0.6" stop-color="${C.coralMid}"/><stop offset="0.85" stop-color="${C.coralLow}"/><stop offset="1" stop-color="${C.coralRim}"/></linearGradient>
  <linearGradient id="sideShade" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="${C.coralRim}" stop-opacity=".45"/><stop offset="0.22" stop-color="${C.coralRim}" stop-opacity="0"/><stop offset="0.7" stop-color="${C.coralRim}" stop-opacity="0"/><stop offset="1" stop-color="${C.coralRim}" stop-opacity=".5"/></linearGradient>
</defs>`

// ── the state markers ────────────────────────────────────────────────────────────────
// Third pass (Jon, 2026-11-19): one object per state, the same in every metaphor and always in
// the same corner, so the state reads before the metaphor does. No text, so every locale works.
const MX = 436, MY = 78, MS = 1.2
const MARKERS = {
  // an idea: a lit bulb
  inbox: () => `<g transform="translate(${MX} ${MY}) scale(${MS})">` +
    [-90, -45, 0, 45, 90, 135, 225].map((a) => `<path d="M 0 -40 L 0 -52" stroke="${C.gold}" stroke-width="6" stroke-linecap="round" transform="rotate(${a} 0 -6)"/>`).join('') +
    `<path d="M -16 18 C -16 4 -28 -2 -28 -18 A 28 28 0 1 1 28 -18 C 28 -2 16 4 16 18 Z" fill="#FFE27A" stroke="${C.goldDark}" stroke-width="4" stroke-linejoin="round"/>` +
    `<path d="M -8 -18 Q -12 -30 0 -32" stroke="#fff" stroke-width="5" fill="none" stroke-linecap="round" opacity=".9"/>` +
    `<rect x="-16" y="18" width="32" height="10" rx="3" fill="${C.grey}" stroke="${C.greyDark}" stroke-width="3"/>` +
    `<rect x="-13" y="28" width="26" height="9" rx="3" fill="${C.grey}" stroke="${C.greyDark}" stroke-width="3"/>` +
    `<rect x="-6" y="37" width="12" height="6" rx="3" fill="${C.greyDark}"/></g>`,
  // go: a traffic light on green
  ready: () => `<g transform="translate(${MX} ${MY}) scale(${MS})">` +
    `<rect x="-24" y="-50" width="48" height="100" rx="14" fill="#3A4250" stroke="${C.grey}" stroke-width="3"/>` +
    `<circle cx="0" cy="-29" r="11" fill="#6B3A3A"/><circle cx="0" cy="0" r="11" fill="#6B5A2E"/>` +
    `<circle cx="0" cy="29" r="19" fill="${C.limeHi}" opacity=".35"/><circle cx="0" cy="29" r="12" fill="#5BE35B"/><circle cx="-3" cy="25" r="4" fill="#fff" opacity=".8"/></g>`,
  // underway: a progress bar about two-thirds full
  doing: () => `<g transform="translate(${MX} ${MY}) scale(${MS})">` +
    `<rect x="-52" y="-16" width="104" height="32" rx="16" fill="#fff" stroke="${C.greyDark}" stroke-width="4"/>` +
    `<rect x="-46" y="-10" width="62" height="20" rx="10" fill="${C.blue}"/>` +
    `<path d="M -30 -10 l -10 20 M -14 -10 l -10 20 M 2 -10 l -10 20" stroke="#fff" stroke-width="5" opacity=".35"/></g>`,
  // patient: a clock
  waiting: () => `<g transform="translate(${MX} ${MY}) scale(${MS})">` +
    `<circle cx="0" cy="0" r="38" fill="#fff" stroke="${C.greyDark}" stroke-width="5"/>` +
    [0, 90, 180, 270].map((a) => `<path d="M 0 -30 L 0 -24" stroke="${C.greyDark}" stroke-width="4" stroke-linecap="round" transform="rotate(${a})"/>`).join('') +
    `<path d="M 0 0 L 0 -22 M 0 0 L 16 8" stroke="${C.eye}" stroke-width="5" stroke-linecap="round"/><circle r="4" fill="${C.eye}"/></g>`,
  // finished: a ticked checkbox, ticked with the icon's check
  done: () => `<g transform="translate(${MX} ${MY}) scale(${MS})">` +
    `<rect x="-34" y="-30" width="64" height="64" rx="12" fill="#fff" stroke="${C.greyDark}" stroke-width="5"/>` +
    check(4, -4, 0.62) + `</g>`,
}

function svgFor(metaphor, state) {
  const scene = SCENES[metaphor][state]
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${W}" width="${W}" height="${W}">` +
    `<title>Astrid — ${SCENES[metaphor].title}: ${STATES[state].label} (${scene.caption})</title>` + DEFS +
    scene.draw() + MARKERS[state]() + `</svg>\n`
}

const outDir = join(HERE, 'svg')
mkdirSync(outDir, { recursive: true })
const metaphors = Object.keys(SCENES)
const states = Object.keys(STATES)
for (const m of metaphors) for (const s of states) writeFileSync(join(outDir, `${m}-${s}.svg`), svgFor(m, s))
console.log(`wrote ${metaphors.length * states.length} SVGs to ${outDir}`)

// Contact sheet: rows = metaphors (one per board), columns = states; the icon character beside the
// title so the likeness can be judged at a glance. Tiles sit on a light and a dark card, since the
// frames are transparent and will be seen in both themes.
const webDir = resolve(process.env.ASTRID_WEB_DIR || join(HERE, '../../../../astrid-web'))
let sharp
try { sharp = createRequire(join(webDir, 'package.json'))('sharp') } catch { console.log(`no sharp under ${webDir}; skipped contact-sheet.png`); process.exit(0) }

const T = 220, PAD = 14, HEAD = 150, SIDE = 190
const sheetW = SIDE + states.length * (T + PAD) + PAD
const sheetH = HEAD + metaphors.length * (T + PAD + 28) + PAD
const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;')
const cardFill = (r) => (r % 2 ? '#1E2430' : '#F2F4F7')
const labels = `<svg xmlns="http://www.w3.org/2000/svg" width="${sheetW}" height="${sheetH}"><rect width="100%" height="100%" fill="#fff"/>` +
  `<g font-family="Helvetica, Arial, sans-serif">` +
  `<text x="150" y="58" font-size="26" font-weight="700" fill="#222">Astrid at work — one metaphor per board</text>` +
  `<text x="150" y="88" font-size="16" fill="#666">Character + key object + the state marker (top right: bulb, green light, progress, clock, checkbox). Transparent; rows alternate light / dark.</text>` +
  states.map((s, i) => `<text x="${SIDE + i * (T + PAD) + T / 2}" y="${HEAD - 14}" font-size="22" font-weight="700" text-anchor="middle" fill="#333">${STATES[s].label}</text>`).join('') +
  metaphors.map((m, r) => {
    const y = HEAD + r * (T + PAD + 28)
    return `<text x="${SIDE - 16}" y="${y + T / 2}" font-size="20" font-weight="700" text-anchor="end" fill="#333">${esc(SCENES[m].title)}</text>` +
      states.map((s, i) => `<rect x="${SIDE + i * (T + PAD)}" y="${y}" width="${T}" height="${T}" rx="18" fill="${cardFill(r)}"/>` +
        `<text x="${SIDE + i * (T + PAD) + T / 2}" y="${y + T + 20}" font-size="14" text-anchor="middle" fill="#666">${esc(SCENES[m][s].caption)}</text>`).join('')
  }).join('') + `</g></svg>`

const icon = join(webDir, 'public/images/astrid-character.png')
const tiles = await Promise.all(metaphors.flatMap((m, r) => states.map(async (s, i) => ({
  input: await sharp(Buffer.from(svgFor(m, s))).resize(T, T).png().toBuffer(),
  left: SIDE + i * (T + PAD), top: HEAD + r * (T + PAD + 28),
}))))
try { tiles.push({ input: await sharp(readFileSync(icon)).resize(110, 110).png().toBuffer(), left: 20, top: 14 }) } catch { /* the reference is optional */ }
await sharp(Buffer.from(labels)).composite(tiles).png().toFile(join(HERE, 'contact-sheet.png'))
console.log(`wrote ${join(HERE, 'contact-sheet.png')}`)
