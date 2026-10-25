// Self-tests for scripts/check-source-contracts.mjs (AITD-533), run by `npm run test:scripts`.
//
// A rule that has quietly stopped matching anything passes forever, which is worse than having
// no rule. So every rule gets a fixture tree that MUST trip it, alongside the real checkout,
// which must not.

import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { LANGUAGES, macHelperLiteralViolations, macLiteralViolations, rules, runRules } from './check-source-contracts.mjs'

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const STRINGS = 'Astrid App/Resources/Localizations'

const made = []
process.on('exit', () => { for (const dir of made) fs.rmSync(dir, { recursive: true, force: true }) })

/** A temporary tree holding exactly `files` (path → contents), removed when the run ends. */
function fixture(files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-contracts-'))
  made.push(root)
  for (const [rel, text] of Object.entries(files)) {
    fs.mkdirSync(path.join(root, path.dirname(rel)), { recursive: true })
    fs.writeFileSync(path.join(root, rel), text)
  }
  return root
}

const plist = (entries) => `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>${Object.entries(entries).map(([k, v]) => `<key>${k}</key>${v}`).join('')}</dict></plist>`

/** All twelve string files, each holding `entries` (key → value), with per-language overrides. */
function strings(entries, overrides = {}) {
  const out = {}
  for (const lang of LANGUAGES) {
    const merged = { ...entries, ...(overrides[lang] ?? {}) }
    out[`${STRINGS}/${lang}.lproj/Localizable.strings`] = Object.entries(merged)
      .filter(([, v]) => v !== null).map(([k, v]) => `"${k}" = "${v}";`).join('\n') + '\n'
  }
  return out
}

const violations = (root, id) => runRules(root, [id])[0].violations

// ─── The real tree ──────────────────────────────────────────────────────────────────────────────

test('every contract holds on this checkout', () => {
  const broken = runRules(repo).filter((r) => r.violations.length)
  assert.deepEqual(broken.map((r) => `${r.id}: ${r.violations.map((v) => `${v.file}:${v.line} ${v.message}`).join('; ')}`), [])
})

test('every rule has a fixture below', () => {
  const covered = new Set(Object.keys(trips))
  assert.deepEqual(rules.map((r) => r.id).filter((id) => !covered.has(id)), [])
})

// ─── One fixture per rule that must trip it ─────────────────────────────────────────────────────

const view = (body) => `struct V: View {\n    var body: some View {\n        ${body}\n    }\n}\n`

const trips = {
  'shared-url-session': () => fixture({
    'Astrid App/Core/Networking/AstridHTTP.swift': 'let s = URLSession.shared // the one place allowed\n',
    'Astrid App/Core/Services/Thing.swift': 'let data = try await URLSession.shared.data(from: url)\n',
    'Astrid App/Views/V.swift': '// URLSession.shared is wrong, says this comment\n',
    'Astrid App/Utilities/U.swift': '', 'Astrid App/ViewModels/M.swift': '', 'Astrid Mac/M.swift': '',
  }),
  'ui-calls-a-service': () => fixture({
    'Astrid App/Views/V.swift': 'let x = AstridAPIClient.shared\n', 'Astrid App/ViewModels/M.swift': '',
    'Astrid App/Utilities/U.swift': '', 'Astrid Mac/App/A.swift': '', 'Astrid Mac/Views/W.swift': '',
  }),
  'silent-writes': () => fixture({
    'Astrid App/Views/Members.swift': '_ = try? await service.removeMember(id)\n',
    'Astrid Mac/Row.swift': '_ = try? await TaskService.shared.updateTask(taskId: id)\n',
  }),
  'legacy-member-arrays': () => fixture({
    'Astrid App/Views/Tasks/CommentSectionViewEnhanced.swift': 'let a = list.admins ?? []\n',
    'Astrid App/Views/Lists/ListMembershipTab.swift': 'let x = "list.members" // a string is fine\n',
    'Astrid App/Views/Lists/ListSettingsModal.swift': 'let ok = list.listMembers\n',
    'Astrid Mac/Views/MacListMembershipTab.swift': '',
  }),
  'view-fields-stay-per-user': () => fixture({
    'Astrid App/Editor.swift': 'var body: [String: Any] = [:]\nbody["name"] = name\nbody["sortBy"] = sortBy\n',
  }),
  'platform-header': () => fixture({
    'Astrid App/Core/X.swift': 'request.setValue("ios-app", forHTTPHeaderField: "x-platform")\n',
    'Astrid App/Core/Networking/PasskeyManager.swift': 'AnalyticsPlatformHeader',
    'Astrid App/Core/Services/AttachmentService.swift': 'AnalyticsPlatformHeader',
    'Astrid App/Core/Authentication/OAuthManager.swift': 'AnalyticsPlatformHeader',
    'Astrid App/Core/Networking/AstridAPIClient.swift': 'AnalyticsPlatformHeader',
  }),
  'private-network-address': () => fixture({ 'Astrid App/Dev.swift': 'let url = "http://192.168.50.254:3000"\n' }),
  'due-day-names': () => fixture({
    'Astrid App/Views/Row.swift': `${view('Text("Today")')}\n#Preview { Text("Tomorrow") }\n`,
    'Astrid App/Views/Tasks/TaskRowView.swift': 'if Calendar.current.isDateInToday(due) {}\n',
  }),
  'attachment-path-names': () => fixture({
    'Astrid App/Core/Services/AttachmentService.swift': 'let url = tmp.appendingPathComponent(fileName)\n',
    'Astrid App/Views/Components/AttachmentThumbnail.swift': '', 'Astrid Mac/Views/MacTaskDetailView.swift': '',
    'Astrid Mac/Views/MacCommentThread.swift': '',
  }),
  'release-logging': () => fixture({
    'Astrid App/A.swift': 'print("hi")\nAppLog.debug("user \\(user.email)")\nAppLog.debug("user \\(AppLog.redact(email: user.email))")\n',
  }),
  'sensitive-logging': () => fixture({
    'Astrid App/Core/Networking/AstridAPIClient.swift': 'print("Request body: \\(body)")\n',
    'Astrid App/Core/Networking/AstridAPIClient+Auth.swift': '', 'Astrid App/Core/Networking/AstridAPIClient+Account.swift': '',
    'Astrid App/Core/Services/AttachmentService.swift': '', 'Astrid App/Core/Authentication/AuthManager.swift': '',
    'Astrid App/Core/Authentication/PasskeyManager.swift': '',
  }),
  'source-file-size': () => fixture({
    'scripts/source-size-ceilings.json': JSON.stringify({ roots: ['Astrid App'], threshold: 3, slack: 1, ceilings: { 'Astrid App/Gone.swift': { lines: 9, why: '' } } }),
    'Astrid App/Big.swift': 'a\nb\nc\nd\ne\n',
  }),
  'mac-hardcoded-strings': () => fixture({ 'Astrid Mac/V.swift': view('Text("Save changes")') }),
  'mac-role-labels': () => fixture({ 'Astrid Mac/Views/Members.swift': 'Text(isOwner ? "Owner" : member.role.capitalized)\n' }),
  'api-v1-is-complete': () => fixture({ 'Astrid App/Old.swift': 'let x = 1 // not here: TODO add to API v1 when it exists\nlet y = 2 /* TODO: API v1 lacks this */\n' }),
  'search-total': () => fixture({ 'Astrid App/Search.swift': 'let p = "/api/v1/search"\nstruct R: Decodable { let total: Int }\n' }),
  'credential-storage': () => fixture({
    'Astrid App/Core/Authentication/GoogleSignInManager.swift': 'UserDefaults.standard.set(codeVerifier, forKey: "x")\n',
  }),
  'legacy-clients-retired': () => fixture({ 'Astrid App/Old.swift': 'let c = APIClient.shared\nlet u = "/api/secure-files/\\(id)"\n' }),
  'membership-goes-through-the-rules': () => fixture({
    'Astrid App/Views/Lists/ListMembershipTab.swift': 'try await memberService.addMember(email)\n',
    'Astrid App/Views/Lists/ListSettingsModal.swift': 'let canEdit = role == .owner || role == .admin\n',
  }),
  'muse-agent-mark': () => fixture({
    'Astrid App/Assets.xcassets/ai-muse.imageset/muse.svg': '<svg viewBox="0 0 24 24"><path d="M6.2 5.5c-2.6"/></svg>',
    'Astrid App/Assets.xcassets/ai-copilot.imageset/copilot.svg': '<svg viewBox="-3 -3 30 30"/>',
  }),
  'debug-only-local-network': () => fixture({
    'Info.plist': plist({ NSAppTransportSecurity: '<dict/>' }),
    'Info-Debug.plist': plist({}),
    'Astrid App.xcodeproj/project.pbxproj': '',
  }),
  'mac-entitlements': () => fixture({
    'Astrid Mac/Astrid Mac.entitlements': plist({ 'com.apple.security.personal-information.reminders': '<true/>' }),
    'Astrid Mac/Astrid Mac Direct.entitlements': plist({ 'com.apple.security.personal-information.calendars': '<true/>' }),
    'ci_scripts/AstridMacCI.entitlements': plist({}),
  }),
  'mac-text-size': () => fixture({ 'Astrid Mac/V.swift': 'Text("x").font(.headline)\n' }),
  'localized-keys': () => fixture({
    ...strings({ 'present.key': 'Here', 'mac.quick_add_placeholder': 'Add a task…', 'update.available_title': 'A new %@ is ready' },
      { de: { 'present.key': null, 'mac.quick_add_placeholder': 'Aufgabe (z.B. #arbeit)' }, fr: { 'update.available_title': 'Un nouvel Astrid' } }),
    'Astrid App/V.swift': 'Text(NSLocalizedString("present.key", comment: ""))\nText(NSLocalizedString("missing.key", comment: ""))\n',
  }),
  // A PNG header whose IHDR colour type (byte 25) is 3, indexed — enough for the rule to read.
  'no-palette-pngs': () => fixture({
    'Astrid App/Assets.xcassets/ai-x.imageset/x.png': Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
      0, 0, 0, 4, 0, 0, 0, 4, 8, 3, 0, 0, 0]),
  }),
  'keyboard-shortcuts-match-web': () => {
    const root = fixture({ 'ios/Astrid Mac/Keyboard/KeyboardShortcuts.swift':
      'KeyBinding(keys: ["n"], action: .newTask, requiresSelection: false, webAction: "onNewTask", title: "")\n'
      + 'KeyBinding(keys: ["]"], action: .indent, requiresSelection: true, webAction: "onOutdentTask", title: "")\n',
    'astrid-web/hooks/useKeyboardShortcuts.ts':
      'export const KEYBOARD_SHORTCUTS = [\n  { key: "n", description: "", action: "onNewTask" },\n'
      + '  { key: "]", description: "", action: "onIndentTask" },\n  { key: "x", description: "", action: "onCompleteTask" },\n] as const\n' })
    return path.join(root, 'ios')
  },
}

for (const [id, build] of Object.entries(trips)) {
  test(`${id} trips on its fixture`, () => {
    const found = violations(build(), id)
    assert.ok(found.length > 0, `${id} found nothing in a tree built to break it`)
  })
}

// ─── What each rule must NOT flag, where the line between them is the point ─────────────────────

test('shared-url-session ignores comments and the networking layer itself', () => {
  const found = violations(trips['shared-url-session'](), 'shared-url-session')
  assert.deepEqual(found.map((v) => v.file), ['Astrid App/Core/Services/Thing.swift'])
})

test('private-network-address leaves TEST-NET-1, public hosts and localhost alone', () => {
  const root = fixture({ 'Astrid App/Dev.swift': 'let a = "http://192.0.2.10:3000"\nlet b = "https://astrid.cc"\nlet c = "http://localhost:3000"\nlet d = "8.8.8.8"\n' })
  assert.deepEqual(violations(root, 'private-network-address'), [])
  for (const address of ['192.168.50.254', '10.1.2.3', '172.20.0.5']) {
    const tripped = fixture({ 'Astrid App/Dev.swift': `let a = "${address}"\n` })
    assert.equal(violations(tripped, 'private-network-address').length, 1, address)
  }
})

test('due-day-names skips previews and NSLocalizedString comments', () => {
  const root = fixture({ 'Astrid App/Views/Row.swift': 'Text(NSLocalizedString("picker.today", comment: "Today"))\n#Preview { Text("Today") }\n' })
  assert.deepEqual(violations(root, 'due-day-names').filter((v) => v.line > 0), [])
})

test('view-fields-stay-per-user accepts a delta-guarded field', () => {
  const root = fixture({ 'Astrid App/Editor.swift': 'body["name"] = name\nif edited.sortBy != original.sortBy {\n    body["sortBy"] = edited.sortBy\n}\n' })
  assert.deepEqual(violations(root, 'view-fields-stay-per-user'), [])
})

test('release-logging allows a redacted email', () => {
  const found = violations(trips['release-logging'](), 'release-logging')
  assert.deepEqual(found.map((v) => v.line), [1, 2])
})

test('mac strings: a key, a verbatim string and a symbol pass; a returned literal that is shown does not', () => {
  const clean = { 'V.swift': view('Text(NSLocalizedString("mac.save", comment: "Save"))\n        Text(verbatim: ".pdf")\n        Image(systemName: "gearshape")') }
  assert.deepEqual(macLiteralViolations(clean), [])
  const helper = { 'Fixture.swift': 'enum F {\n    static func statusText(hasKey: Bool) -> String {\n        guard hasKey else { return "Not set" }\n'
    + '        return NSLocalizedString("mac.key_set", comment: "")\n    }\n    static func symbol() -> String { "gearshape" }\n}\n'
    + view('Text(F.statusText(hasKey: false))\n        Image(systemName: F.symbol())') }
  assert.deepEqual(macHelperLiteralViolations(helper).map((v) => v.message.split(' ')[0] + ' ' + v.message.split('"')[1]), ['statusText Not set'])
})

test('localized-keys names the language a key is missing from', () => {
  const messages = violations(trips['localized-keys'](), 'localized-keys').map((v) => v.message)
  assert.ok(messages.some((m) => m.includes('"present.key" is missing in de')))
  assert.ok(messages.some((m) => m.includes('"missing.key" is missing in every language')))
  assert.ok(messages.some((m) => m.includes('syntax tip')))
  assert.ok(messages.some((m) => m.includes('update.available_title')))
})

test('keyboard parity reports a remapped key and a missing one', () => {
  const messages = violations(trips['keyboard-shortcuts-match-web'](), 'keyboard-shortcuts-match-web').map((v) => v.message)
  assert.ok(messages.some((m) => m.includes('key "]" is onOutdentTask on Mac but onIndentTask on web')))
  assert.ok(messages.some((m) => m.includes('web key "x"')))
})

test('keyboard parity skips visibly when astrid-web is not checked out', () => {
  const root = fixture({ 'Astrid Mac/Keyboard/KeyboardShortcuts.swift': '' })
  const [result] = runRules(root, ['keyboard-shortcuts-match-web'])
  if (fs.existsSync(path.resolve(root, '..', 'astrid-web'))) return   // a tmp dir with a sibling astrid-web: nothing to assert
  assert.deepEqual(result.violations, [])
  assert.equal(result.notes.length, 1)
})

test('source-file-size reports growth and a stale ceiling', () => {
  const messages = violations(trips['source-file-size'](), 'source-file-size').map((v) => `${v.file}: ${v.message}`)
  assert.ok(messages.some((m) => m.startsWith('Astrid App/Big.swift: 5 lines, ceiling 3')))
  assert.ok(messages.some((m) => m.startsWith('Astrid App/Gone.swift: has a ceiling but is gone')))
})
