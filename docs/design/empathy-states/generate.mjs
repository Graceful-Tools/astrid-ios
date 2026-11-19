#!/usr/bin/env node
// ADEV-127 — the Astrid octopus acting out each board state, in five metaphors.
//
//   node docs/design/empathy-states/generate.mjs
//
// Writes svg/<metaphor>-<state>.svg (512×512, no text, so any locale can use them) and
// contact-sheet.png (needs `sharp`; it is taken from the paired astrid-web checkout,
// ASTRID_WEB_DIR or ../astrid-web, since this repo has no node_modules of its own).
//
// Exploration artwork for choosing a set. Nothing here is in the app bundle.

import { mkdirSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const W = 512

// ── palette (taken from the app icon) ────────────────────────────────────────────────
const C = {
  red: '#E8483F', redLight: '#F67B6D', redDark: '#BF2F29',
  green: '#9ACD32', greenDark: '#5E9A1C', greenLight: '#C3E64B',
  ink: '#2A1714', cream: '#FBEBDD', creamLine: '#D9B8A4',
  white: '#FFFFFF', gold: '#F5C13D', goldDark: '#C9921A',
  wood: '#B97A4B', woodDark: '#8A5532', grey: '#9AA5B1', greyDark: '#5F6B78',
  blue: '#3E8EDE', sky: '#87DBF7', brick: '#C8553D', brickDark: '#99402E',
  soil: '#7A5236', leaf: '#5DBB4A', leafDark: '#3F8F34',
}

const STATES = {
  inbox: { label: 'Inbox', bg: '#E3EEF8', ground: '#C9DAEA' },
  ready: { label: 'Ready', bg: '#FFF2CF', ground: '#F3DDA0' },
  doing: { label: 'Doing', bg: '#D6EFFC', ground: '#AED8EE' },
  waiting: { label: 'Waiting', bg: '#ECE5FA', ground: '#D3C7EE' },
  done: { label: 'Done', bg: '#DDF4D1', ground: '#B8E3A3' },
}

// ── the octopus ──────────────────────────────────────────────────────────────────────
// Local coordinates: body centred on x=0, head top ≈ y-112, tentacle tips ≈ y+145.
const BODY = `M -95 30 C -95 -160 95 -160 95 30 L 95 62
  C 100 90 128 100 142 114 C 122 126 96 118 82 104
  C 82 122 76 136 60 146 C 46 136 44 118 44 106
  C 34 126 20 140 4 146 C -10 136 -10 118 -10 106
  C -22 126 -36 140 -52 146 C -66 134 -62 116 -56 102
  C -76 116 -106 126 -142 112 C -120 100 -100 88 -95 62 Z`

const eye = (x, y, [lx, ly]) =>
  `<circle cx="${x}" cy="${y}" r="15" fill="${C.ink}"/>` +
  `<circle cx="${x + 4 + lx}" cy="${y - 5 + ly}" r="4.5" fill="${C.white}"/>`

const closedEye = (x, y) =>
  `<path d="M ${x - 14} ${y + 4} Q ${x} ${y - 14} ${x + 14} ${y + 4}" fill="none" stroke="${C.ink}" stroke-width="6" stroke-linecap="round"/>`

const restingEye = (x, y) =>
  `<path d="M ${x - 14} ${y - 2} Q ${x} ${y + 12} ${x + 14} ${y - 2}" fill="none" stroke="${C.ink}" stroke-width="6" stroke-linecap="round"/>`

const teeth = (x0, x1, y, n) => {
  const step = (x1 - x0) / n
  let d = `M ${x0} ${y}`
  for (let i = 0; i < n; i++) d += ` L ${x0 + step * (i + 0.5)} ${y + (i % 2 ? -7 : 7)}`
  return `<path d="${d} L ${x1} ${y}" fill="none" stroke="${C.creamLine}" stroke-width="3" stroke-linejoin="round"/>`
}

const FACES = {
  // the icon's own face
  grin: (look) =>
    eye(-42, -28, look) + eye(42, -28, look) +
    `<path d="M -58 6 Q 0 0 58 6 Q 52 58 0 60 Q -52 58 -58 6 Z" fill="${C.redDark}"/>` +
    `<path d="M -50 11 Q 0 6 50 11 Q 44 50 0 52 Q -44 50 -50 11 Z" fill="${C.cream}"/>` +
    teeth(-40, 40, 28, 6),
  // concentrating: brows down, mouth set
  focus: (look) =>
    eye(-42, -26, look) + eye(42, -26, look) +
    `<path d="M -60 -52 L -26 -44 M 60 -52 L 26 -44" stroke="${C.redDark}" stroke-width="7" stroke-linecap="round"/>` +
    `<path d="M -34 14 Q 0 10 34 14 Q 30 36 0 38 Q -30 36 -34 14 Z" fill="${C.redDark}"/>` +
    `<path d="M -28 17 Q 0 14 28 17 Q 24 31 0 33 Q -24 31 -28 17 Z" fill="${C.cream}"/>` +
    teeth(-22, 22, 24, 4),
  // just arrived, a little curious
  curious: (look) =>
    eye(-42, -28, look) + eye(42, -28, look) +
    `<path d="M -60 -56 Q -44 -66 -28 -58 M 28 -62 Q 44 -70 60 -60" fill="none" stroke="${C.redDark}" stroke-width="6" stroke-linecap="round"/>` +
    `<ellipse cx="0" cy="22" rx="14" ry="16" fill="${C.redDark}"/>` +
    `<ellipse cx="0" cy="26" rx="8" ry="8" fill="#8E1F1A"/>`,
  // patient — eyes at rest, small smile
  calm: () =>
    restingEye(-42, -26) + restingEye(42, -26) +
    `<path d="M -26 16 Q 0 34 26 16" fill="none" stroke="${C.redDark}" stroke-width="7" stroke-linecap="round"/>` +
    `<ellipse cx="-66" cy="4" rx="13" ry="8" fill="${C.redLight}" opacity=".8"/>` +
    `<ellipse cx="66" cy="4" rx="13" ry="8" fill="${C.redLight}" opacity=".8"/>`,
  // delighted
  joy: () =>
    closedEye(-42, -26) + closedEye(42, -26) +
    `<path d="M -60 4 Q 0 -2 60 4 Q 54 70 0 72 Q -54 70 -60 4 Z" fill="${C.redDark}"/>` +
    `<path d="M -52 9 Q 0 4 52 9 Q 48 30 0 32 Q -48 30 -52 9 Z" fill="${C.cream}"/>` +
    teeth(-42, 42, 20, 6) +
    `<ellipse cx="0" cy="56" rx="24" ry="12" fill="#F49A8E"/>` +
    `<ellipse cx="-70" cy="8" rx="13" ry="8" fill="${C.redLight}"/>` +
    `<ellipse cx="70" cy="8" rx="13" ry="8" fill="${C.redLight}"/>`,
}

// An arm reaching from the body's side to a hand point (local coords).
function arm([tx, ty], side) {
  const ax = side === 'l' ? -78 : 78
  const ay = 52
  const bow = side === 'l' ? -30 : 30
  const cx = (ax + tx) / 2 + bow
  const cy = Math.max(ay, ty) + 18
  return `<path d="M ${ax} ${ay} Q ${cx} ${cy} ${tx} ${ty}" fill="none" stroke="url(#armGrad)" stroke-width="24" stroke-linecap="round"/>` +
    `<circle cx="${tx}" cy="${ty}" r="17" fill="url(#bodyGrad)"/>`
}

/**
 * The octopus, positioned in scene coordinates.
 *   face: grin | focus | curious | calm | joy      look: pupil offset [x, y]
 *   arms: [{ side: 'l'|'r', to: [x, y] }] in LOCAL coords
 *   behind / hat / front: extra SVG in local coords (drawn behind body, on head, in front)
 */
function octo({ x = 256, y = 286, s = 0.95, rot = 0, sy = 1, face = 'grin', look = [0, 0], arms = [], behind = '', hat = '', onBody = '', front = '', shadow = true }) {
  return (shadow ? `<ellipse cx="${x}" cy="${y + 150 * s * sy}" rx="${120 * s}" ry="${14 * s}" fill="#000" opacity=".10"/>` : '') +
    `<g transform="translate(${x} ${y}) rotate(${rot}) scale(${s} ${s * sy})">` +
    behind +
    `<path d="${BODY}" fill="url(#bodyGrad)"/>` +
    `<ellipse cx="-30" cy="-80" rx="34" ry="20" fill="#fff" opacity=".18" transform="rotate(-25 -30 -80)"/>` +
    onBody +
    FACES[face](look) +
    hat +
    arms.map((a) => arm(a.to, a.side)).join('') +
    front +
    `</g>`
}

// ── props (scene coords unless noted) ────────────────────────────────────────────────
const check = (x, y, s = 1, rot = 0) =>
  `<g transform="translate(${x} ${y}) rotate(${rot}) scale(${s})">` +
  `<path d="M -46 2 L -16 32 L 50 -38" fill="none" stroke="${C.greenDark}" stroke-width="30" stroke-linecap="round" stroke-linejoin="round" transform="translate(3 5)"/>` +
  `<path d="M -46 2 L -16 32 L 50 -38" fill="none" stroke="${C.green}" stroke-width="30" stroke-linecap="round" stroke-linejoin="round"/>` +
  `<path d="M -40 -2 L -16 22 L 44 -42" fill="none" stroke="${C.greenLight}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" opacity=".7"/></g>`

const sparkle = (x, y, r = 10, fill = C.gold) =>
  `<path d="M ${x} ${y - r} Q ${x + r * 0.2} ${y - r * 0.2} ${x + r} ${y} Q ${x + r * 0.2} ${y + r * 0.2} ${x} ${y + r} Q ${x - r * 0.2} ${y + r * 0.2} ${x - r} ${y} Q ${x - r * 0.2} ${y - r * 0.2} ${x} ${y - r} Z" fill="${fill}"/>`

const confetti = () => [
  [70, 80, C.gold, 20], [120, 140, C.blue, -30], [420, 70, C.green, 40], [450, 150, C.red, 10],
  [390, 40, C.blue, 60], [60, 190, C.red, -10], [470, 230, C.gold, 25], [150, 50, C.green, -45],
].map(([x, y, f, r]) => `<rect x="${x}" y="${y}" width="16" height="8" rx="3" fill="${f}" transform="rotate(${r} ${x} ${y})"/>`).join('') +
  sparkle(96, 110, 12) + sparkle(430, 110, 14) + sparkle(250, 40, 10, C.white)

const motion = (x, y) => [0, 26, 52].map((d, i) =>
  `<path d="M ${x - 70 + i * 14} ${y + d} L ${x - i * 10} ${y + d}" stroke="#fff" stroke-width="8" stroke-linecap="round" opacity=".85"/>`).join('')

const sweat = (x, y) => `<path d="M ${x} ${y} Q ${x - 9} ${y + 14} ${x} ${y + 18} Q ${x + 9} ${y + 14} ${x} ${y} Z" fill="#7FD0F5" stroke="#fff" stroke-width="2"/>`

const clock = (x, y, r = 26) =>
  `<circle cx="${x}" cy="${y}" r="${r}" fill="#fff" stroke="${C.greyDark}" stroke-width="5"/>` +
  `<path d="M ${x} ${y} L ${x} ${y - r * 0.62} M ${x} ${y} L ${x + r * 0.45} ${y + r * 0.2}" stroke="${C.ink}" stroke-width="4" stroke-linecap="round"/>`

const paper = (x, y, w, h, rot = 0, lines = 4, fill = '#fff') =>
  `<g transform="rotate(${rot} ${x + w / 2} ${y + h / 2})"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="5" fill="${fill}" stroke="${C.greyDark}" stroke-width="3"/>` +
  Array.from({ length: lines }, (_, i) => `<line x1="${x + 10}" y1="${y + 16 + i * ((h - 24) / lines)}" x2="${x + w - 10 - (i === lines - 1 ? w * 0.3 : 0)}" y2="${y + 16 + i * ((h - 24) / lines)}" stroke="${C.grey}" stroke-width="3" stroke-linecap="round"/>`).join('') + `</g>`

const bench = (x, y, w = 260) =>
  `<rect x="${x}" y="${y}" width="${w}" height="18" rx="6" fill="${C.wood}"/>` +
  `<rect x="${x + 20}" y="${y + 18}" width="14" height="44" fill="${C.woodDark}"/><rect x="${x + w - 34}" y="${y + 18}" width="14" height="44" fill="${C.woodDark}"/>`

// ── hats and wearables (local coords; head top ≈ y-112) ──────────────────────────────
const headband = `<path d="M -94 -66 Q 0 -96 94 -66 L 94 -46 Q 0 -76 -94 -46 Z" fill="#fff"/><path d="M -94 -60 Q 0 -90 94 -60" stroke="${C.blue}" stroke-width="5" fill="none"/>`
const hardHat = `<path d="M -84 -78 Q -80 -150 0 -152 Q 80 -150 84 -78 Z" fill="${C.gold}"/><rect x="-108" y="-86" width="216" height="18" rx="9" fill="${C.goldDark}"/><path d="M -10 -150 L -10 -84 M 10 -150 L 10 -84" stroke="${C.goldDark}" stroke-width="6"/>`
const toque = `<rect x="-62" y="-130" width="124" height="38" rx="6" fill="#fff" stroke="#E2E2E2" stroke-width="3"/><circle cx="-46" cy="-152" r="34" fill="#fff"/><circle cx="0" cy="-170" r="40" fill="#fff"/><circle cx="46" cy="-152" r="34" fill="#fff"/><path d="M -40 -122 L -40 -100 M 0 -122 L 0 -100 M 40 -122 L 40 -100" stroke="#E2E2E2" stroke-width="3"/>`
const strawHat = `<ellipse cx="0" cy="-90" rx="138" ry="26" fill="#E9C46A"/><path d="M -70 -92 Q -66 -160 0 -162 Q 66 -160 70 -92 Z" fill="#F2D27E"/><path d="M -70 -104 Q 0 -118 70 -104 L 70 -92 Q 0 -106 -70 -92 Z" fill="${C.red}" opacity=".9"/><path d="M -70 -104 Q 0 -118 70 -104 L 70 -92 Q 0 -106 -70 -92 Z" fill="${C.leafDark}"/>`
const apron = `<path d="M -62 50 L 62 50 L 72 118 Q 0 128 -72 118 Z" fill="#fff"/><path d="M -62 50 L -86 30 M 62 50 L 86 30" stroke="#fff" stroke-width="6"/><rect x="-20" y="72" width="40" height="22" rx="4" fill="none" stroke="#E2E2E2" stroke-width="3"/>`
const backpack = `<path d="M -84 -10 Q -50 30 -70 80 M 84 -10 Q 50 30 70 80" stroke="${C.blue}" stroke-width="12" fill="none" stroke-linecap="round"/>`
const backpackBehind = `<rect x="70" y="-40" width="70" height="110" rx="22" fill="${C.blue}"/><rect x="82" y="10" width="46" height="34" rx="8" fill="#2F6FB0"/>`
const medal = `<path d="M -26 30 L 0 76 L 26 30" fill="none" stroke="${C.blue}" stroke-width="12"/><circle cx="0" cy="88" r="20" fill="${C.gold}" stroke="${C.goldDark}" stroke-width="4"/>` + sparkle(0, 88, 9, '#fff')

// ── backgrounds ──────────────────────────────────────────────────────────────────────
const groundStrip = (st) => `<rect x="0" y="418" width="${W}" height="${W - 418}" fill="${STATES[st].ground}"/>`
const track = `<rect x="0" y="410" width="${W}" height="${W - 410}" fill="#D9714E"/><path d="M 0 440 L 512 440 M 0 478 L 512 478" stroke="#fff" stroke-width="4" opacity=".7"/>`
const road = `<path d="M 0 512 L 200 400 L 312 400 L 512 512 Z" fill="#6E7782"/><path d="M 256 404 L 256 420 M 256 436 L 256 458 M 256 476 L 256 506" stroke="#fff" stroke-width="7"/>`

// ── the scenes ───────────────────────────────────────────────────────────────────────
const L = (x, y) => ({ side: 'l', to: [x, y] })
const R = (x, y) => ({ side: 'r', to: [x, y] })

const SCENES = {
  race: {
    title: 'Race',
    inbox: { caption: 'Reading the race flyer', draw: () => groundStrip('inbox') +
      `<rect x="40" y="356" width="110" height="68" rx="16" fill="${C.blue}"/><path d="M 70 360 Q 95 320 120 360" stroke="#2F6FB0" stroke-width="10" fill="none"/>` +
      octo({ x: 270, face: 'curious', look: [5, 4], arms: [R(118, 20), L(-108, 80)], front: paper(78, -40, 70, 86, 10, 3) + `<circle cx="113" cy="10" r="13" fill="none" stroke="${C.red}" stroke-width="4" transform="rotate(10 113 3)"/>` }) },
    ready: { caption: 'On your marks', draw: () => track +
      `<rect x="330" y="408" width="14" height="104" fill="#fff"/>` +
      octo({ x: 236, y: 300, sy: 0.86, face: 'focus', look: [6, 0], hat: headband, arms: [R(110, 132), L(-60, 134)] }) },
    doing: { caption: 'Mid-sprint', draw: () => track + motion(150, 220) +
      octo({ x: 270, y: 274, rot: 12, face: 'focus', look: [6, 0], hat: headband, arms: [R(128, -10), L(-128, 92)] }) + sweat(150, 160) },
    waiting: { caption: 'Water break between heats', draw: () => groundStrip('waiting') + bench(120, 360) +
      octo({ x: 256, y: 250, face: 'calm', hat: `<rect x="-60" y="-118" width="120" height="30" rx="12" fill="#fff" transform="rotate(-6)"/>`, arms: [R(96, -6), L(-104, 96)],
        front: `<rect x="82" y="-58" width="30" height="62" rx="9" fill="#7FD0F5" stroke="${C.blue}" stroke-width="4"/><rect x="88" y="-70" width="18" height="14" rx="4" fill="${C.blue}"/>` }) +
      clock(430, 120, 30) },
    done: { caption: 'On the podium', draw: () => groundStrip('done') + confetti() +
      `<rect x="166" y="370" width="180" height="142" rx="10" fill="${C.gold}"/><rect x="40" y="420" width="126" height="92" rx="10" fill="#D7DDE3"/><rect x="346" y="440" width="126" height="72" rx="10" fill="#E3A86B"/>` +
      `<path d="M 256 404 L 256 474 M 244 416 L 256 404" stroke="${C.goldDark}" stroke-width="12" stroke-linecap="round" fill="none"/>` +
      octo({ x: 256, y: 238, s: 0.88, face: 'joy', onBody: medal, arms: [R(140, -96), L(-124, -60)], front: check(170, -150, 0.85, -8), shadow: false }) },
  },
  wall: {
    title: 'Building a wall',
    inbox: { caption: 'Unrolling the blueprint', draw: () => groundStrip('inbox') +
      bricks(36, 380, 3, 2, true) +
      octo({ x: 286, face: 'curious', look: [0, 6], arms: [L(-70, 30), R(70, 30)], front:
        `<rect x="-86" y="2" width="172" height="104" rx="6" fill="${C.blue}" stroke="#2F6FB0" stroke-width="4"/>` +
        `<path d="M -70 20 L 70 20 M -70 40 L 70 40 M -70 60 L 70 60 M -70 80 L 70 80 M -50 10 L -50 98 M -10 10 L -10 98 M 30 10 L 30 98" stroke="#9CC8F2" stroke-width="2"/>` +
        `<rect x="-56" y="30" width="96" height="44" fill="none" stroke="#fff" stroke-width="4"/>` +
        `<circle cx="-86" cy="54" r="12" fill="#2F6FB0"/><circle cx="86" cy="54" r="12" fill="#2F6FB0"/>` }) },
    ready: { caption: 'Hard hat on, trowel up', draw: () => groundStrip('ready') + bricks(40, 360, 4, 3, true) +
      octo({ x: 300, face: 'grin', look: [-4, 0], hat: hardHat, arms: [R(130, -40), L(-110, 90)], front: trowel(130, -40) }) },
    doing: { caption: 'Half built', draw: () => groundStrip('doing') +
      wallRows(30, 418, [6, 5, 4, 3, 2]) +
      octo({ x: 360, y: 290, s: 0.85, face: 'focus', look: [-8, 2], hat: hardHat, arms: [L(-150, -10), R(110, 90)],
        front: `<rect x="-196" y="-34" width="70" height="34" rx="4" fill="${C.brick}" stroke="${C.brickDark}" stroke-width="4"/>` }) + sweat(420, 150) },
    waiting: { caption: 'Letting the mortar set', draw: () => groundStrip('waiting') +
      wallRows(20, 418, [7, 7, 7, 7], '#B9AFC4', '#978DA3') + cone(440, 418) +
      octo({ x: 262, y: 236, s: 0.8, face: 'calm', hat: hardHat, arms: [L(-110, 60), R(104, -6)], shadow: false,
        front: `<rect x="86" y="-30" width="40" height="44" rx="8" fill="#fff" stroke="${C.greyDark}" stroke-width="4"/><path d="M 126 -18 Q 146 -10 126 4" stroke="${C.greyDark}" stroke-width="4" fill="none"/><path d="M 96 -44 Q 90 -56 98 -66 M 112 -44 Q 106 -56 114 -66" stroke="#fff" stroke-width="4" fill="none" stroke-linecap="round"/>` }) + clock(70, 90, 30) },
    done: { caption: 'Wall finished', draw: () => groundStrip('done') + confetti() +
      wallRows(16, 418, [7, 7, 7, 7, 7]) + check(150, 330, 0.95) +
      octo({ x: 380, y: 270, s: 0.78, face: 'joy', hat: hardHat, arms: [L(-120, -110), R(124, -110)] }) },
  },
  chef: {
    title: 'Chef',
    inbox: { caption: 'Groceries and a recipe', draw: () => groundStrip('inbox') + counter() +
      groceryBag(70, 300) +
      octo({ x: 300, y: 262, s: 0.9, face: 'curious', look: [-4, 4], arms: [L(-80, 10), R(110, 80)], front: paper(-130, -50, 74, 92, -8, 4, '#FFF8E1') }) },
    ready: { caption: 'Apron on, mise en place', draw: () => groundStrip('ready') + counter() +
      octo({ x: 256, y: 240, s: 0.86, face: 'grin', hat: toque, onBody: apron, arms: [L(-120, 70), R(120, 70)], shadow: false }) +
      `<rect x="140" y="378" width="232" height="26" rx="8" fill="${C.wood}"/>` +
      `<circle cx="184" cy="372" r="18" fill="#E44D3A"/><path d="M 184 354 l -6 -8 m 6 8 l 6 -8" stroke="${C.leafDark}" stroke-width="4"/>` +
      `<path d="M 232 382 L 300 370 L 300 384 Z" fill="#F28C28"/><path d="M 300 370 l 14 -6 m -14 14 l 14 4" stroke="${C.leafDark}" stroke-width="4"/>` +
      `<circle cx="340" cy="374" r="14" fill="${C.leaf}"/>` },
    doing: { caption: 'Stirring the pot', draw: () => groundStrip('doing') + counter() +
      `<path d="M 178 298 L 128 330" stroke="${C.wood}" stroke-width="10" stroke-linecap="round"/>` +
      octo({ x: 300, y: 236, s: 0.84, face: 'focus', look: [-8, 6], hat: toque, onBody: apron, arms: [L(-150, 70), R(110, 90)], shadow: false }) +
      `<rect x="70" y="320" width="150" height="80" rx="14" fill="${C.greyDark}"/><rect x="60" y="312" width="170" height="16" rx="8" fill="#4A545F"/>` +
      steam(145, 290) },
    waiting: { caption: 'Watching the oven timer', draw: () => groundStrip('waiting') +
      `<rect x="40" y="214" width="190" height="204" rx="16" fill="#D7DDE3" stroke="${C.greyDark}" stroke-width="5"/><rect x="62" y="270" width="146" height="110" rx="10" fill="#FFB347" opacity=".85"/><rect x="62" y="270" width="146" height="110" rx="10" fill="none" stroke="${C.greyDark}" stroke-width="5"/><circle cx="90" cy="240" r="9" fill="${C.greyDark}"/><circle cx="125" cy="240" r="9" fill="${C.greyDark}"/>` +
      `<path d="M 96 340 Q 135 310 174 340 Z" fill="#C98B4B"/>` +
      octo({ x: 350, y: 280, s: 0.82, face: 'calm', hat: toque, onBody: apron, arms: [L(-106, -10), R(110, 90)], front: clockLocal(-110, -40) }) },
    done: { caption: 'Plated and served', draw: () => groundStrip('done') + confetti() +
      octo({ x: 236, y: 280, s: 0.86, face: 'joy', hat: toque, onBody: apron, arms: [R(140, 10), L(-110, 80)],
        front: `<ellipse cx="160" cy="6" rx="86" ry="20" fill="#fff" stroke="#D5D5D5" stroke-width="4"/>` +
          `<ellipse cx="160" cy="-4" rx="46" ry="16" fill="#E9A23B"/><circle cx="140" cy="-14" r="10" fill="#E44D3A"/><circle cx="170" cy="-18" r="9" fill="${C.leaf}"/><circle cx="186" cy="-8" r="7" fill="#E44D3A"/>` +
          `<path d="M 150 -40 Q 160 -56 150 -70 M 172 -40 Q 182 -56 172 -70" stroke="#fff" stroke-width="5" fill="none" stroke-linecap="round"/>` }) +
      check(110, 120, 0.55, -10) },
  },
  garden: {
    title: 'Garden',
    inbox: { caption: 'A packet of seeds', draw: () => groundStrip('inbox') + pot(90, 350, '') +
      octo({ x: 300, face: 'curious', look: [-6, 6], arms: [L(-100, 20), R(110, 80)], front: seedPacket(-150, -50, -8) }) },
    ready: { caption: 'Soil dug, can filled', draw: () => groundStrip('ready') +
      `<ellipse cx="130" cy="420" rx="100" ry="26" fill="${C.soil}"/>` + wateringCan(330, 330, 0) +
      octo({ x: 236, y: 270, s: 0.86, face: 'grin', hat: strawHat, arms: [L(-120, 20), R(80, 110)],
        front: `<circle cx="-120" cy="10" r="5" fill="#8A6A3A"/><circle cx="-108" cy="2" r="5" fill="#8A6A3A"/><circle cx="-128" cy="-2" r="5" fill="#8A6A3A"/>` }) },
    doing: { caption: 'Planting and watering', draw: () => groundStrip('doing') +
      `<ellipse cx="140" cy="420" rx="110" ry="26" fill="${C.soil}"/><path d="M 120 410 Q 120 390 128 384 M 128 384 q 10 -4 14 4 M 128 384 q -10 -6 -14 2" stroke="${C.leafDark}" stroke-width="5" fill="none" stroke-linecap="round"/>` +
      `<g fill="#7FD0F5">${[[120, 330], [138, 352], [110, 362], [150, 320], [130, 300]].map(([x, y]) => `<ellipse cx="${x}" cy="${y}" rx="5" ry="8"/>`).join('')}</g>` +
      octo({ x: 330, y: 270, s: 0.86, face: 'focus', look: [-8, 6], hat: strawHat, arms: [L(-140, -10), R(100, 90)], front: wateringCan(-180, -40, -25, true) }) },
    waiting: { caption: 'Waiting for the sprout', draw: () => groundStrip('waiting') +
      `<circle cx="430" cy="80" r="40" fill="${C.gold}"/>` + pot(150, 340, sprout(190, 340)) +
      octo({ x: 330, y: 290, s: 0.82, face: 'calm', hat: strawHat, arms: [L(-60, 40), R(60, 40)] }) },
    done: { caption: 'In full bloom', draw: () => groundStrip('done') + confetti() +
      pot(110, 340, bloom(150, 340)) +
      octo({ x: 330, y: 280, s: 0.86, face: 'joy', hat: strawHat, arms: [L(-120, -10), R(130, -90)], front: check(150, -150, 0.6, 6) }) },
  },
  journey: {
    title: 'Journey',
    inbox: { caption: 'A letter arrives', draw: () => groundStrip('inbox') +
      `<path d="M 40 360 L 170 360 L 160 418 L 50 418 Z" fill="${C.wood}"/><path d="M 40 360 L 170 360" stroke="${C.woodDark}" stroke-width="6"/>` +
      octo({ x: 310, face: 'curious', look: [-6, 2], arms: [L(-110, 0), R(100, 90)], front: envelope(-170, -40, -10) }) },
    ready: { caption: 'Pack on, map out', draw: () => groundStrip('ready') + signpost(420, 418) +
      octo({ x: 236, face: 'grin', behind: backpackBehind, onBody: backpack, arms: [L(-86, 30), R(86, 30)],
        front: `<path d="M -96 0 L -32 12 L 32 0 L 96 12 L 96 92 L 32 80 L -32 92 L -96 80 Z" fill="#FFF8E1" stroke="${C.wood}" stroke-width="4"/><path d="M -32 12 L -32 92 M 32 0 L 32 80" stroke="${C.wood}" stroke-width="3"/><path d="M -76 64 Q -40 20 0 50 T 74 30" stroke="${C.red}" stroke-width="4" fill="none" stroke-dasharray="8 6"/><path d="M 66 22 l 14 14 m 0 -14 l -14 14" stroke="${C.red}" stroke-width="4"/>` }) },
    doing: { caption: 'On the road', draw: () => `<rect x="0" y="400" width="${W}" height="112" fill="${STATES.doing.ground}"/>` + road + motion(160, 230) +
      octo({ x: 270, y: 270, s: 0.86, rot: 8, face: 'focus', behind: backpackBehind, onBody: backpack, arms: [L(-120, 80), R(120, 0)] }) },
    waiting: { caption: 'At the bus stop', draw: () => groundStrip('waiting') + bench(70, 360, 280) +
      `<rect x="410" y="150" width="12" height="270" fill="${C.greyDark}"/><circle cx="416" cy="140" r="38" fill="${C.blue}" stroke="#fff" stroke-width="6"/><rect x="398" y="124" width="36" height="28" rx="6" fill="#fff"/><circle cx="406" cy="156" r="5" fill="#fff"/><circle cx="426" cy="156" r="5" fill="#fff"/>` +
      octo({ x: 210, y: 250, s: 0.86, face: 'calm', behind: backpackBehind, onBody: backpack, arms: [L(-100, 100), R(110, -30)], front: clockLocal(110, -40, 22) }) },
    done: { caption: 'Flag on the summit', draw: () => `<path d="M 0 512 L 0 440 Q 256 330 512 440 L 512 512 Z" fill="${STATES.done.ground}"/>` + confetti() +
      `<rect x="370" y="180" width="10" height="230" fill="${C.woodDark}"/><path d="M 380 186 L 480 214 L 380 244 Z" fill="${C.green}"/>` + check(420, 214, 0.32) +
      octo({ x: 236, y: 262, s: 0.86, face: 'joy', behind: backpackBehind, onBody: backpack, arms: [R(156, 0), L(-124, -100)] }) },
  },
}

// ── helpers used by scenes (declared after for readability; hoisted functions) ───────
function bricks(x, y, cols, rows, loose) {
  let s = ''
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols - r; c++) {
    const bx = x + c * 36 + r * 18, by = y + 8 - (r + 1) * 22
    s += `<rect x="${bx}" y="${by + (loose ? 30 : 0)}" width="34" height="20" rx="3" fill="${C.brick}" stroke="${C.brickDark}" stroke-width="3"/>`
  }
  return s
}
function wallRows(x, base, counts, fill = C.brick, edge = C.brickDark) {
  let s = ''
  counts.forEach((n, r) => {
    for (let c = 0; c < n; c++) {
      const bx = x + c * 46 + (r % 2 ? 23 : 0), by = base - (r + 1) * 28
      s += `<rect x="${bx}" y="${by}" width="44" height="26" rx="3" fill="${fill}" stroke="${edge}" stroke-width="3"/>`
    }
  })
  return s
}
function trowel(x, y) {
  return `<path d="M ${x} ${y} L ${x + 4} ${y - 30}" stroke="${C.woodDark}" stroke-width="10" stroke-linecap="round"/>` +
    `<path d="M ${x - 22} ${y - 30} L ${x + 30} ${y - 30} L ${x + 4} ${y - 92} Z" fill="#C9D1D9" stroke="${C.greyDark}" stroke-width="4" stroke-linejoin="round"/>`
}
function cone(x, base) {
  return `<path d="M ${x - 26} ${base} L ${x} ${base - 80} L ${x + 26} ${base} Z" fill="#F28C28"/><path d="M ${x - 15} ${base - 30} L ${x + 15} ${base - 30} L ${x + 10} ${base - 46} L ${x - 10} ${base - 46} Z" fill="#fff"/><rect x="${x - 36}" y="${base - 6}" width="72" height="10" rx="4" fill="#D9731A"/>`
}
function counter() {
  return `<rect x="0" y="404" width="${W}" height="${W - 404}" fill="#C9A27E"/><rect x="0" y="398" width="${W}" height="14" fill="#E3C49F"/>`
}
function groceryBag(x, y) {
  return `<path d="M ${x + 8} ${y} Q ${x + 30} ${y - 60} ${x + 40} ${y} M ${x + 60} ${y} Q ${x + 72} ${y - 70} ${x + 82} ${y}" stroke="${C.leafDark}" stroke-width="10" fill="none" stroke-linecap="round"/>` +
    `<circle cx="${x + 54}" cy="${y - 10}" r="18" fill="#E44D3A"/>` +
    `<path d="M ${x} ${y} L ${x + 100} ${y} L ${x + 92} ${y + 100} L ${x + 8} ${y + 100} Z" fill="#D6A971"/><path d="M ${x} ${y} L ${x + 100} ${y}" stroke="#B8894F" stroke-width="6"/>`
}
function steam(x, y) {
  return [-26, 0, 26].map((d) => `<path d="M ${x + d} ${y} Q ${x + d - 12} ${y - 22} ${x + d} ${y - 42} Q ${x + d + 12} ${y - 60} ${x + d} ${y - 80}" stroke="#fff" stroke-width="7" fill="none" stroke-linecap="round" opacity=".9"/>`).join('')
}
function clockLocal(x, y, r = 26) {
  return clock(x, y - r - 4, r)
}
function pot(x, y, plant) {
  return plant + `<path d="M ${x} ${y} L ${x + 80} ${y} L ${x + 70} ${y + 78} L ${x + 10} ${y + 78} Z" fill="#D9714E"/><rect x="${x - 8}" y="${y - 6}" width="96" height="20" rx="6" fill="#C25E3D"/>`
}
function sprout(x, y) {
  return `<path d="M ${x} ${y} L ${x} ${y - 40}" stroke="${C.leafDark}" stroke-width="6"/><path d="M ${x} ${y - 36} Q ${x - 30} ${y - 60} ${x - 34} ${y - 34} Q ${x - 14} ${y - 26} ${x} ${y - 36} Z" fill="${C.leaf}"/><path d="M ${x} ${y - 40} Q ${x + 30} ${y - 66} ${x + 36} ${y - 40} Q ${x + 16} ${y - 30} ${x} ${y - 40} Z" fill="${C.leaf}"/>`
}
function bloom(x, y) {
  const fy = y - 130
  return `<path d="M ${x} ${y} Q ${x - 8} ${y - 60} ${x} ${fy}" stroke="${C.leafDark}" stroke-width="8" fill="none"/>` +
    `<path d="M ${x - 2} ${y - 50} Q ${x - 50} ${y - 80} ${x - 56} ${y - 46} Q ${x - 26} ${y - 34} ${x - 2} ${y - 50} Z" fill="${C.leaf}"/>` +
    [0, 60, 120, 180, 240, 300].map((a) => `<ellipse cx="${x}" cy="${fy - 32}" rx="18" ry="32" fill="#FF8FB1" transform="rotate(${a} ${x} ${fy})"/>`).join('') +
    `<circle cx="${x}" cy="${fy}" r="20" fill="${C.gold}"/>`
}
function seedPacket(x, y, rot) {
  return `<g transform="rotate(${rot} ${x + 40} ${y + 50})"><rect x="${x}" y="${y}" width="80" height="100" rx="6" fill="#FFF8E1" stroke="${C.wood}" stroke-width="4"/>` +
    `<rect x="${x}" y="${y}" width="80" height="16" fill="#E9C46A"/>` +
    `<path d="M ${x + 40} ${y + 92} L ${x + 40} ${y + 56}" stroke="${C.leafDark}" stroke-width="4"/>` +
    [0, 72, 144, 216, 288].map((a) => `<ellipse cx="${x + 40}" cy="${y + 38}" rx="7" ry="12" fill="#FF8FB1" transform="rotate(${a} ${x + 40} ${y + 50})"/>`).join('') +
    `<circle cx="${x + 40}" cy="${y + 50}" r="7" fill="${C.gold}"/></g>`
}
function wateringCan(x, y, rot, pouring) {
  return `<g transform="rotate(${rot} ${x + 40} ${y + 40})">` +
    `<path d="M ${x} ${y + 20} L ${x - 50} ${y - 10}" stroke="#4FA3E0" stroke-width="12" stroke-linecap="round"/><rect x="${x - 62}" y="${y - 22}" width="20" height="18" rx="4" fill="#4FA3E0" transform="rotate(-30 ${x - 52} ${y - 13})"/>` +
    `<rect x="${x}" y="${y}" width="84" height="70" rx="14" fill="#5DB0EE"/><path d="M ${x + 20} ${y} Q ${x + 42} ${y - 34} ${x + 64} ${y}" stroke="#4FA3E0" stroke-width="10" fill="none"/>` +
    (pouring ? '' : '') + `</g>`
}
function envelope(x, y, rot) {
  return `<g transform="rotate(${rot} ${x + 50} ${y + 34})"><rect x="${x}" y="${y}" width="100" height="68" rx="6" fill="#fff" stroke="${C.greyDark}" stroke-width="4"/><path d="M ${x} ${y} L ${x + 50} ${y + 40} L ${x + 100} ${y}" fill="none" stroke="${C.greyDark}" stroke-width="4"/><rect x="${x + 70}" y="${y + 8}" width="20" height="22" fill="${C.red}"/></g>` +
    sparkle(x - 10, y - 16, 10)
}
function signpost(x, base) {
  return `<rect x="${x - 6}" y="${base - 170}" width="12" height="170" fill="${C.woodDark}"/><path d="M ${x - 60} ${base - 160} L ${x + 50} ${base - 160} L ${x + 70} ${base - 140} L ${x + 50} ${base - 120} L ${x - 60} ${base - 120} Z" fill="${C.wood}"/><path d="M ${x + 60} ${base - 100} L ${x - 50} ${base - 100} L ${x - 70} ${base - 80} L ${x - 50} ${base - 60} L ${x + 60} ${base - 60} Z" fill="${C.wood}"/>`
}

// ── render ───────────────────────────────────────────────────────────────────────────
const DEFS = `<defs>
  <radialGradient id="bodyGrad" cx="0.4" cy="0.3" r="0.8"><stop offset="0" stop-color="${C.redLight}"/><stop offset="0.55" stop-color="${C.red}"/><stop offset="1" stop-color="${C.redDark}"/></radialGradient>
  <linearGradient id="armGrad" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.red}"/><stop offset="1" stop-color="${C.redDark}"/></linearGradient>
</defs>`

function svgFor(metaphor, state) {
  const scene = SCENES[metaphor][state]
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${W}" width="${W}" height="${W}">` +
    `<title>Astrid — ${SCENES[metaphor].title}: ${STATES[state].label} (${scene.caption})</title>` + DEFS +
    `<rect width="${W}" height="${W}" fill="${STATES[state].bg}"/>` + scene.draw() + `</svg>\n`
}

const outDir = join(HERE, 'svg')
mkdirSync(outDir, { recursive: true })
const metaphors = Object.keys(SCENES)
const states = Object.keys(STATES)
for (const m of metaphors) for (const s of states) writeFileSync(join(outDir, `${m}-${s}.svg`), svgFor(m, s))
console.log(`wrote ${metaphors.length * states.length} SVGs to ${outDir}`)

// Contact sheet: rows = metaphors, columns = states.
const webDir = resolve(process.env.ASTRID_WEB_DIR || join(HERE, '../../../../astrid-web'))
let sharp
try { sharp = createRequire(join(webDir, 'package.json'))('sharp') } catch { console.log(`no sharp under ${webDir}; skipped contact-sheet.png`); process.exit(0) }

const T = 256, PAD = 16, HEAD = 56, SIDE = 200
const sheetW = SIDE + states.length * (T + PAD) + PAD
const sheetH = HEAD + metaphors.length * (T + PAD + 30) + PAD
const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;')
const labels = `<svg xmlns="http://www.w3.org/2000/svg" width="${sheetW}" height="${sheetH}"><rect width="100%" height="100%" fill="#fff"/>` +
  `<g font-family="Helvetica, Arial, sans-serif">` +
  states.map((s, i) => `<text x="${SIDE + i * (T + PAD) + T / 2}" y="38" font-size="24" font-weight="700" text-anchor="middle" fill="#333">${STATES[s].label}</text>`).join('') +
  metaphors.map((m, r) => {
    const y = HEAD + r * (T + PAD + 30)
    return `<text x="${SIDE - 16}" y="${y + T / 2}" font-size="22" font-weight="700" text-anchor="end" fill="#333">${esc(SCENES[m].title)}</text>` +
      states.map((s, i) => `<text x="${SIDE + i * (T + PAD) + T / 2}" y="${y + T + 22}" font-size="15" text-anchor="middle" fill="#666">${esc(SCENES[m][s].caption)}</text>`).join('')
  }).join('') + `</g></svg>`

const tiles = await Promise.all(metaphors.flatMap((m, r) => states.map(async (s, i) => ({
  input: await sharp(Buffer.from(svgFor(m, s))).resize(T, T).png().toBuffer(),
  left: SIDE + i * (T + PAD), top: HEAD + r * (T + PAD + 30),
}))))
await sharp(Buffer.from(labels)).composite(tiles).png().toFile(join(HERE, 'contact-sheet.png'))
console.log(`wrote ${join(HERE, 'contact-sheet.png')}`)
