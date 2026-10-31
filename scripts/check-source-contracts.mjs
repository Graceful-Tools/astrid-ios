#!/usr/bin/env node
// check-source-contracts.mjs — the source-tree contracts the compiler cannot check (AITD-533).
//
// Ninety unit-test files used to read the repository and assert on source text, inside a
// simulator boot, once per platform. The good ones encode a rule nothing else can: a tree-wide
// `URLSession.shared` ban, no backend client in a view, a localized key in every language, the
// Mac's App Sandbox allowlist. Those live here now, run once from `predeploy.sh`, and print the
// file:line they matched. The brittle ones — "this file still names that helper" — were deleted.
//
//   node scripts/check-source-contracts.mjs            # every rule, against this checkout
//   node scripts/check-source-contracts.mjs --only id  # one rule (repeatable)
//   node scripts/check-source-contracts.mjs --list     # the rules and why each exists
//
// Self-tests: scripts/test-check-source-contracts.mjs, in `npm run test:scripts`. Each rule has a
// fixture that must trip it, so a rule that has quietly stopped matching anything fails there.
//
// A rule returns { violations: [{ file, line, message }], notes: [string] }. A note is a visible
// skip (astrid-web not checked out next to this repo), never a silent one.

import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const LANGUAGES = ['en', 'es', 'fr', 'de', 'it', 'ja', 'ko', 'nl', 'pt', 'ru', 'zh-Hans', 'zh-Hant']
const STRINGS_DIR = 'Astrid App/Resources/Localizations'

// ─── Reading the tree ───────────────────────────────────────────────────────────────────────────

export function makeContext(root, { webDir } = {}) {
  const cache = new Map()
  const ctx = {
    root,
    webDir,
    abs: (rel) => path.join(root, rel),
    exists: (rel) => fs.existsSync(path.join(root, rel)),
    isDir: (rel) => {
      try { return fs.statSync(path.join(root, rel)).isDirectory() } catch { return false }
    },
    read(rel) {
      if (!cache.has(rel)) cache.set(rel, fs.readFileSync(path.join(root, rel), 'utf8'))
      return cache.get(rel)
    },
    tryRead(rel) {
      try { return ctx.read(rel) } catch { return null }
    },
    /** Every file under `dirs` with one of `extensions`, repo-relative, sorted. */
    files(dirs, extensions = ['.swift']) {
      const out = []
      const walk = (rel) => {
        let entries
        try { entries = fs.readdirSync(path.join(root, rel), { withFileTypes: true }) } catch { return }
        for (const entry of entries) {
          const child = rel ? `${rel}/${entry.name}` : entry.name
          if (entry.isDirectory()) {
            if (entry.name === 'build' || entry.name.startsWith('.')) continue
            walk(child)
          } else if (extensions.some((ext) => entry.name.endsWith(ext))) {
            out.push(child)
          }
        }
      }
      for (const dir of dirs) walk(dir)
      return out.sort()
    },
    /** Swift files directly in the repository root (`AstridApp.swift` lives there). */
    rootSwiftFiles() {
      return fs.readdirSync(root).filter((name) => name.endsWith('.swift')).sort()
    },
    lines: (rel) => ctx.read(rel).split('\n'),
    /** A property list as JSON, through plutil — the same parser Xcode uses. */
    plist(rel) {
      const json = execFileSync('plutil', ['-convert', 'json', '-o', '-', path.join(root, rel)], { encoding: 'utf8' })
      return JSON.parse(json)
    },
    /** One language's Localizable.strings as key → value. */
    strings(language) {
      const key = `strings:${language}`
      if (!cache.has(key)) cache.set(key, parseStrings(ctx.tryRead(`${STRINGS_DIR}/${language}.lproj/Localizable.strings`) ?? ''))
      return cache.get(key)
    },
  }
  return ctx
}

export function parseStrings(text) {
  const map = new Map()
  for (const match of text.matchAll(/^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;/gm)) {
    map.set(match[1], match[2])
  }
  return map
}

const isComment = (line) => {
  const t = line.trim()
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')
}

/** A rule over every line of every file in `files`, skipping comment lines. */
function eachCodeLine(ctx, files, visit) {
  const violations = []
  for (const file of files) {
    ctx.lines(file).forEach((line, index) => {
      if (isComment(line)) return
      const message = visit(line, file, index)
      if (message) violations.push({ file, line: index + 1, message })
    })
  }
  return violations
}

/** Every directory a rule walks must exist, or the rule is walking nothing. */
function missingDirs(ctx, dirs) {
  return dirs.filter((dir) => !ctx.isDir(dir))
    .map((dir) => ({ file: dir, line: 0, message: 'is not there — this rule is walking nothing' }))
}

function missingFile(ctx, file) {
  return ctx.exists(file) ? [] : [{ file, line: 0, message: 'is not there — rename the rule along with it' }]
}

const lineOf = (text, index) => text.slice(0, index).split('\n').length

// ─── The rules ──────────────────────────────────────────────────────────────────────────────────

export const rules = [
  {
    id: 'shared-url-session',
    why: '`URLSession.shared` skips the timeout, the path-safety backstop and the UI-test cookie isolation `AstridHTTP` applies (AITD-338, AITD-353).',
    run(ctx) {
      const dirs = ['Astrid App/Core', 'Astrid App/Views', 'Astrid App/Utilities', 'Astrid App/ViewModels', 'Astrid Mac']
      const files = ctx.files(dirs).filter((f) => !f.startsWith('Astrid App/Core/Networking/'))
      return [...missingDirs(ctx, [...dirs, 'Astrid App/Core/Networking']),
        ...eachCodeLine(ctx, files, (line) => line.includes('URLSession.shared')
          && 'sends through URLSession.shared — use AstridHTTP.session, or a service method in a view')]
    },
  },
  {
    id: 'ui-calls-a-service',
    why: 'ASTRID.md §0 rule 1: UI and utility code reach the backend through the service layer, on both targets (AITD-319). Widened from six audited views to every view.',
    run(ctx) {
      const dirs = ['Astrid App/Views', 'Astrid App/ViewModels', 'Astrid App/Utilities', 'Astrid Mac/App', 'Astrid Mac/Views']
      return [...missingDirs(ctx, dirs),
        ...eachCodeLine(ctx, ctx.files(dirs), (line) => /\b(Astrid)?APIClient\.shared\b/.test(line)
          && 'calls a network client directly — add the method to a service and call that')]
    },
  },
  {
    id: 'silent-writes',
    why: 'A write that throws and is swallowed with `try?` loses the edit with nothing said (AITD-406 on iOS, f1f0cb13 on Mac). iOS checks the direct-API writes the Outbox does not back; the Mac checks every write.',
    run(ctx) {
      const scopes = [
        { files: ctx.files(['Astrid App/Views']), methods: ['addMember', 'removeMember', 'updateMemberRole'] },
        {
          files: ctx.files(['Astrid Mac']),
          methods: ['createTask', 'updateTask', 'deleteTask', 'completeTask', 'createList', 'updateList',
            'updateListAdvanced', 'deleteList', 'addMember', 'removeMember', 'updateMemberRole',
            'createComment', 'deleteComment', 'sendMessage', 'reorderTasks', 'moveTask', 'makeSubtask'],
        },
      ]
      return [...missingDirs(ctx, ['Astrid App/Views', 'Astrid Mac']), ...scopes.flatMap(({ files, methods }) =>
        eachCodeLine(ctx, files, (line) => {
          if (!line.includes('try? await')) return null
          const method = methods.find((m) => line.includes(`${m}(`))
          return method && `try? await …${method}( swallows a failed write — report it through AppActions/AppErrorCenter`
        }))]
    },
  },
  {
    id: 'legacy-member-arrays',
    why: '`listMembers` is the source of truth for roles; the legacy `admins`/`members` arrays are ignored by web and must be by every membership surface (ASTRID.md §8 row 3).',
    run(ctx) {
      const files = ['Astrid App/Views/Tasks/CommentSectionViewEnhanced.swift', 'Astrid App/Views/Lists/ListMembershipTab.swift',
        'Astrid App/Views/Lists/ListSettingsModal.swift', 'Astrid Mac/Views/MacListMembershipTab.swift']
      return [...files.flatMap((f) => missingFile(ctx, f)), ...eachCodeLine(ctx, files.filter(ctx.exists), (line) => {
        const code = line.split('//')[0].replace(/"(?:\\.|[^"\\])*"/g, '""')
        const hit = /\.(admins|members)(?![A-Za-z0-9_])/.exec(code)
        return hit && `reads the legacy .${hit[1]} array — ask listMembers`
      })]
    },
  },
  {
    id: 'view-fields-stay-per-user',
    why: 'Sort and filter fields are per-user on the server (AITD-394): an editor that sends them with an unrelated list edit silently reverts that user\'s own view.',
    run(ctx) {
      const viewFields = ['sortBy', 'filterPriority', 'filterAssignee', 'filterDueDate', 'filterCompletion',
        'filterRepeating', 'filterAssignedBy', 'filterInLists']
      const identity = ['name', 'description', 'color', 'imageUrl', 'privacy', 'defaultPriority', 'defaultDueDate', 'defaultAssigneeId']
      const writesKey = (key, line) => {
        if (line.includes(`"${key}":`)) return true
        const at = line.indexOf(`["${key}"]`)
        if (at < 0) return false
        const rest = line.slice(at + key.length + 4).trimStart()
        return rest.startsWith('=') && !rest.startsWith('==')
      }
      const violations = []
      let scanned = 0
      for (const file of ctx.files(['Astrid App', 'Astrid Mac'])) {
        const code = ctx.lines(file).map((l) => l.trim())
        if (!code.some((l) => !l.startsWith('//') && identity.some((k) => writesKey(k, l)))) continue
        scanned += 1
        code.forEach((line, index) => {
          if (line.startsWith('//')) return
          for (const field of viewFields.filter((f) => writesKey(f, line))) {
            let cursor = index - 1
            while (cursor >= 0 && (code[cursor] === '' || code[cursor].startsWith('//'))) cursor -= 1
            const guarded = cursor >= 0 && code[cursor].startsWith('if ') && code[cursor].includes('!=')
            if (!guarded) violations.push({ file, line: index + 1, message: `sends "${field}" with a list edit — send only what changed, or guard it with if edited.x != original.x` })
          }
        })
      }
      if (scanned === 0) violations.push({ file: 'Astrid App', line: 0, message: 'found no list editors to scan — the heuristic has rotted' })
      return violations
    },
  },
  {
    id: 'platform-header',
    why: 'Analytics tell iOS and Mac apart by `x-platform` (AITD-301): one definition, `AnalyticsPlatformHeader`, and every Astrid-bound request stamps it; third parties never get it.',
    run(ctx) {
      const files = ctx.files(['Astrid App', 'Astrid Mac'])
      const violations = eachCodeLine(ctx, files.filter((f) => !f.endsWith('/AnalyticsPlatformHeader.swift')), (line) => {
        const literal = ['"ios-app"', '"mac-app"', '"x-platform"'].find((l) => line.includes(l))
        return literal && `spells ${literal} — use AnalyticsPlatformHeader`
      })
      const thirdPartyOnly = new Set(['GoogleSignInManager.swift'])
      for (const file of files) {
        const text = ctx.read(file)
        const name = path.basename(file)
        if (!text.includes('URLRequest(url:')) continue
        if (thirdPartyOnly.has(name)) {
          if (text.includes('AnalyticsPlatformHeader')) violations.push({ file, line: 0, message: 'talks to a third party and must not send our platform header' })
          continue
        }
        const astridBound = text.includes('Constants.API.baseURL') || text.includes('baseURL.appendingPathComponent') || text.includes('baseURL:')
        if (astridBound && !text.includes('AnalyticsPlatformHeader')) {
          violations.push({ file, line: 0, message: 'builds requests to the Astrid backend without identifying the platform' })
        }
      }
      for (const name of ['PasskeyManager.swift', 'AttachmentService.swift', 'OAuthManager.swift', 'AstridAPIClient.swift']) {
        const file = files.find((f) => path.basename(f) === name)
        if (!file) violations.push({ file: name, line: 0, message: 'not found — if it was renamed, keep it covered' })
        else if (!ctx.read(file).includes('AnalyticsPlatformHeader')) violations.push({ file, line: 0, message: 'must identify the platform on its requests' })
      }
      const client = 'Astrid App/Core/Networking/AstridAPIClient.swift'
      if (ctx.exists(client)) {
        const text = ctx.read(client)
        const accept = text.split('forHTTPHeaderField: "Accept"').length - 1
        const platform = text.split('AnalyticsPlatformHeader.headerName').length - 1
        if (accept === 0 || platform < accept) {
          violations.push({ file: client, line: 0, message: `sets Accept in ${accept} builders but the platform header in ${platform}` })
        }
      }
      return violations
    },
  },
  {
    id: 'private-network-address',
    why: 'A private-network address in tracked source is one machine on one network (AITD-351). Use ASTRID_DEV_SERVER_URL, or 192.0.2.x (TEST-NET-1) in a fixture.',
    pattern: /\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b/,
    run(ctx) {
      const files = [...['Info.plist', 'Info-Debug.plist'].filter(ctx.exists),
        ...ctx.files(['Astrid App', 'Astrid Mac', 'Astrid', 'Astrid AppTests'], ['.swift', '.plist'])]
      return eachCodeLine(ctx, files, (line) => {
        const hit = this.pattern.exec(line)
        return hit && `hardcodes the private address ${hit[0]}`
      })
    },
  },
  {
    id: 'due-day-names',
    why: 'Today / Tomorrow / Yesterday come from DueDateLabel, which is localized and right for all-day dates west of UTC (AITD-317). Widened to every view.',
    run(ctx) {
      const files = ctx.files(['Astrid App/Views', 'Astrid Mac'])
      const violations = []
      for (const file of files) {
        const lines = ctx.lines(file)
        const preview = lines.findIndex((l) => l.startsWith('#Preview') || /PreviewProvider/.test(l))
        lines.forEach((line, index) => {
          if (isComment(line) || (preview >= 0 && index >= preview)) return
          const code = line.replace(/comment:\s*"(?:\\.|[^"\\])*"/g, '')
          const literal = ['"Today"', '"Tomorrow"', '"Yesterday"'].find((l) => code.includes(l))
          if (literal) violations.push({ file, line: index + 1, message: `writes ${literal} as an English literal — route it through DueDateLabel` })
        })
      }
      // The day comparison itself is only banned where due dates are drawn: elsewhere a timed
      // instant (a comment's timestamp) is exactly what isDateInToday is for.
      const dueSurfaces = ['Astrid App/Views/Components/CompactTaskRow.swift', 'Astrid App/Views/Tasks/TaskRowView.swift',
        'Astrid App/Views/Chat/ChatMessageListView.swift', 'Astrid App/Views/Chat/ChatMessageBubble.swift',
        'Astrid Mac/Views/MacTaskRow.swift', 'Astrid Mac/App/MacQuickAddPreview.swift']
      violations.push(...dueSurfaces.flatMap((f) => missingFile(ctx, f)),
        ...eachCodeLine(ctx, dueSurfaces.filter(ctx.exists), (line) => /isDateIn(Today|Yesterday)/.test(line)
          && 're-implements the day comparison — it is wrong for all-day dates west of UTC'))
      return violations
    },
  },
  {
    id: 'attachment-path-names',
    why: 'An attachment name off the wire joined onto a temp directory can escape it; route it through AttachmentFileName.temporaryURL(in:for:).',
    run(ctx) {
      const files = ['Astrid App/Core/Services/AttachmentService.swift', 'Astrid App/Views/Components/AttachmentThumbnail.swift',
        'Astrid Mac/Views/MacTaskDetailView.swift', 'Astrid Mac/Views/MacCommentThread.swift']
      const joins = ['appendingPathComponent(fileName)', 'appendingPathComponent(file.name)', 'appendingPathComponent(name)',
        'appendingPathComponent(a.name)', '+ fileName)']
      return [...files.flatMap((f) => missingFile(ctx, f)), ...eachCodeLine(ctx, files.filter(ctx.exists), (line) =>
        line.includes('appendingPathComponent(') && joins.some((j) => line.includes(j))
        && 'joins an unsanitised attachment name onto a path')]
    },
  },
  {
    id: 'release-logging',
    why: '`print` is not compiled out of Release and evaluates its interpolation in the shipping binary (c6a0f9ba); an email in a log is an account identifier.',
    run(ctx) {
      const files = [...ctx.rootSwiftFiles(), ...ctx.files(['Astrid App', 'Astrid Mac', 'Shared', 'Astrid'])]
      const interpolatesEmail = (line) => {
        for (const match of line.matchAll(/\\\(/g)) {
          let depth = 1
          let i = match.index + 2
          const start = i
          while (i < line.length && depth > 0) {
            if (line[i] === '(') depth += 1
            if (line[i] === ')') depth -= 1
            if (depth > 0) i += 1
          }
          if (depth !== 0) break
          const expression = line.slice(start, i)
          if (expression.toLowerCase().includes('email') && !expression.includes('AppLog.redact')) return true
        }
        return false
      }
      const violations = []
      for (const file of files) {
        ctx.lines(file).forEach((line, index) => {
          const t = line.trim()
          if (t.startsWith('print(')) violations.push({ file, line: index + 1, message: 'bare print(…) ships in Release — use AppLog.debug(…)' })
          const isLog = ['print(', 'Swift.print(', 'AppLog.', 'logger.', 'PrivacyLogger.'].some((p) => t.startsWith(p))
          if (isLog && interpolatesEmail(line)) violations.push({ file, line: index + 1, message: 'logs an email address — wrap it in AppLog.redact(email:)' })
        })
      }
      return violations
    },
  },
  {
    id: 'sensitive-logging',
    why: 'Networking and auth paths must never log secrets, raw payloads, full URLs, headers or account identifiers (12d5372d).',
    run(ctx) {
      const files = ['Astrid App/Core/Networking/AstridAPIClient.swift', 'Astrid App/Core/Networking/AstridAPIClient+Auth.swift',
        'Astrid App/Core/Networking/AstridAPIClient+Account.swift', 'Astrid App/Core/Services/AttachmentService.swift',
        'Astrid App/Core/Authentication/AuthManager.swift', 'Astrid App/Core/Authentication/PasskeyManager.swift']
      const forbidden = ['sessionCookie.prefix', 'savedCookie.prefix', 'allHTTPHeaderFields', 'Request body:', 'Request body (with nulls):',
        'Response body:', 'Response body preview:', 'Error response: \\(responseString)', 'Response: \\(responseString)',
        'url.absoluteString', 'response.user.email', 'user.email']
      return [...files.flatMap((f) => missingFile(ctx, f)), ...eachCodeLine(ctx, files.filter(ctx.exists), (line) => {
        if (!line.includes('print(')) return null
        const fragment = forbidden.find((f) => line.includes(f))
        return fragment && `prints ${fragment}`
      })]
    },
  },
  {
    id: 'source-file-size',
    why: 'A ratchet (AITD-346): no production file crosses 1,000 lines except those recorded in scripts/source-size-ceilings.json, and those may not grow. Raising a ceiling is a decision, with a reason, in that file.',
    run(ctx) {
      const config = JSON.parse(ctx.read('scripts/source-size-ceilings.json'))
      const roots = config.roots
      const counts = new Map()
      for (const file of ctx.files(roots)) counts.set(file, (ctx.read(file).match(/\n/g) ?? []).length)
      const violations = []
      for (const [file, lines] of counts) {
        const ceiling = config.ceilings[file]?.lines ?? config.threshold
        if (lines > ceiling) violations.push({ file, line: 0, message: `${lines} lines, ceiling ${ceiling} — extract something, or raise the ceiling deliberately and say why` })
      }
      for (const [file, entry] of Object.entries(config.ceilings)) {
        if (!counts.has(file)) violations.push({ file, line: 0, message: 'has a ceiling but is gone — delete or rename the entry' })
        else if (counts.get(file) < entry.lines - config.slack) violations.push({ file, line: 0, message: `now ${counts.get(file)} lines but its ceiling is still ${entry.lines} — lower it` })
      }
      if (counts.size < 200) violations.push({ file: roots.join(', '), line: 0, message: `only ${counts.size} Swift files found — the roots are wrong` })
      for (const root of roots) {
        if (![...counts.keys()].some((f) => f.startsWith(`${root}/`))) violations.push({ file: root, line: 0, message: 'contributed no files' })
      }
      return violations
    },
  },
  {
    id: 'mac-hardcoded-strings',
    why: 'Mac UI strings come from Localizable.strings: a literal in Text/Button/Label/… is English in all twelve languages. A string that is deliberately not prose goes through Text(verbatim:). A String helper whose result is shown must not return a literal either (AITD-537).',
    run(ctx) {
      const sources = Object.fromEntries(ctx.files(['Astrid Mac']).map((f) => [f, ctx.read(f)]))
      if (Object.keys(sources).length === 0) return missingDirs(ctx, ['Astrid Mac'])
      return [...macLiteralViolations(sources), ...macHelperLiteralViolations(sources)]
    },
  },
  {
    id: 'mac-role-labels',
    why: 'A role renders through MacMemberRoleLabel.title(for:), which is localized; an English role word or a capitalized wire value is not (AITD-323).',
    run(ctx) {
      const files = ctx.files(['Astrid Mac/Views'])
      return [...missingDirs(ctx, ['Astrid Mac/Views']), ...eachCodeLine(ctx, files, (line) => {
        const word = ['Owner', 'Admin', 'Administrator', 'Member', 'Viewer'].find((w) => line.includes(`"${w}"`))
        if (word) return `spells the role "${word}" — use MacMemberRoleLabel.title(for:)`
        return /role\??\.capitalized/i.test(line) && 'capitalizes a role wire value — use MacMemberRoleLabel.title(for:)'
      })]
    },
  },
  {
    id: 'api-v1-is-complete',
    why: 'API v1 has every endpoint the apps call (AITD-349); a comment claiming otherwise is either wrong or a task nobody filed.',
    run(ctx) {
      // Comments included: a comment is exactly where such a claim lives.
      const violations = []
      for (const file of ctx.files(['Astrid App', 'Astrid Mac'])) {
        ctx.lines(file).forEach((line, index) => {
          if (/(not yet|TODO).{0,60}API v1/i.test(line)) violations.push({ file, line: index + 1, message: 'claims API v1 is missing an endpoint — file a task instead' })
        })
      }
      return violations
    },
  },
  {
    id: 'search-total',
    why: '`total` from GET /api/v1/search is null on every page but the last unless the caller passes includeTotal=true (AITD-321).',
    knownCallers: [],
    run(ctx) {
      const files = ctx.files(['Astrid App', 'Astrid Mac', 'Astrid', 'Shared'])
      const violations = []
      for (const file of files) {
        const text = ctx.read(file)
        if (!text.includes('/api/v1/search')) continue
        if (!this.knownCallers.includes(file)) violations.push({ file, line: lineOf(text, text.indexOf('/api/v1/search')), message: 'is a new caller of /api/v1/search — handle an absent total, then name it in knownCallers' })
        if (/let\s+total\s*:\s*Int(?!\?)/.test(text) && !text.includes('includeTotal')) violations.push({ file, line: 0, message: 'decodes a required `total` without passing includeTotal=true' })
      }
      for (const endpoint of ['/api/v1/users/search', '/api/v1/contacts/search']) {
        if (!files.some((f) => ctx.read(f).includes(endpoint))) violations.push({ file: endpoint, line: 0, message: 'is no longer called — re-check which search endpoints the apps use' })
      }
      return violations
    },
  },
  {
    id: 'credential-storage',
    why: 'The OAuth access token lives in the Keychain and sign-out clears the old UserDefaults copy (562f3d02); the Google PKCE verifier is never persisted (968463ad).',
    run(ctx) {
      const checks = [
        ['Astrid App/Core/Authentication/KeychainService.swift', 'saveOAuthAccessToken', true],
        ['Astrid App/Core/Authentication/KeychainService.swift', 'deleteOAuthAccessToken', true],
        ['Astrid App/Core/Authentication/OAuthManager.swift', 'saveOAuthAccessToken', true],
        ['Astrid App/Core/Authentication/OAuthManager.swift', 'UserDefaults.standard.set(data, forKey: "oauth_token_cache")', false],
        ['Astrid App/Core/Authentication/OAuthManager.swift', 'removeObject(forKey: CacheKey.legacyToken)', true],
        ['Astrid App/Core/Authentication/AuthManager.swift', 'deleteOAuthAccessToken', true],
        ['Astrid App/Core/Authentication/AuthManager.swift', 'removeObject(forKey: "oauth_token_cache")', true],
        ['Astrid App/Core/Authentication/GoogleSignInManager.swift', 'UserDefaults.standard.set(codeVerifier', false],
        ['Astrid App/Core/Authentication/GoogleSignInManager.swift', 'UserDefaults.standard.removeObject(forKey: "GoogleOAuthCodeVerifier")', true],
        ['Astrid App/Core/Authentication/GoogleSignInManager.swift', 'codeVerifier: codeVerifier', true],
      ]
      return checks.flatMap(([file, text, wanted]) => {
        const source = ctx.tryRead(file)
        if (source === null) return missingFile(ctx, file)
        if (source.includes(text) === wanted) return []
        const at = source.indexOf(text)
        return [{ file, line: at >= 0 ? lineOf(source, at) : 0, message: wanted ? `no longer has ${text}` : `writes ${text} again` }]
      })
    },
  },
  {
    id: 'legacy-clients-retired',
    why: 'AstridAPIClient is the one HTTP client (AITD-504), and new writes use the v1 secure-files path so they do not persist rows in the old form.',
    run(ctx) {
      const patterns = [/\benum APIEndpoint\b/, /\bclass APIClient\b/, /\bAPIClientProtocol\b/, /(?<![A-Za-z])APIClient\.shared\b/, /\bas\?? APIError\b/]
      return [
        ...eachCodeLine(ctx, ctx.files(['Astrid App', 'Astrid Mac']), (line) => {
          const hit = patterns.find((p) => p.test(line))
          return hit && `references the retired legacy client (${hit.source})`
        }),
        ...eachCodeLine(ctx, ctx.files(['Astrid App', 'Astrid Mac', 'Astrid']), (line) =>
          line.includes('/api/secure-files/\\(') && 'builds the legacy /api/secure-files/ path — use /api/v1/secure-files/{id}'),
      ]
    },
  },
  {
    id: 'membership-goes-through-the-rules',
    why: 'The membership tabs act through ListMembershipActions (AITD-399), and every surface that decides "may I manage this list" asks ListPermissions rather than hand-rolling owner-or-admin.',
    run(ctx) {
      const tabs = ['Astrid App/Views/Lists/ListMembershipTab.swift', 'Astrid Mac/Views/MacListMembershipTab.swift']
      const direct = ['memberService.addMember', 'memberService.updateMemberRole', 'memberService.removeMember', 'memberService.cancelInvitation',
        'svc.addMember', 'svc.updateMemberRole', 'svc.removeMember', 'svc.cancelInvitation', 'svc.updateInvitationRole']
      const mustAsk = [...tabs.slice(0, 1), 'Astrid App/Views/Lists/ListSettingsModal.swift', tabs[1],
        'Astrid Mac/Views/MacListSettingsWindow.swift', 'Astrid Mac/Views/MacListMenu.swift']
      const mustNotHandRoll = [...mustAsk, 'Astrid Mac/App/MacRootView.swift']
      const present = (files) => files.filter(ctx.exists)
      return [
        ...[...new Set([...tabs, ...mustNotHandRoll])].flatMap((f) => missingFile(ctx, f)),
        ...eachCodeLine(ctx, present(tabs), (line) => {
          const call = direct.find((c) => line.includes(c))
          return call && `calls ${call} — go through ListMembershipActions`
        }),
        ...present(mustAsk).filter((f) => !ctx.read(f).includes('ListPermissions.'))
          .map((file) => ({ file, line: 0, message: 'must ask the shared rule, ListPermissions' })),
        ...eachCodeLine(ctx, present(mustNotHandRoll), (line) => {
          const form = ['role == .owner || role == .admin', 'myRole == "owner"'].find((f) => line.includes(f))
          return form && `hand-rolls the permission rule: ${form}`
        }),
      ]
    },
  },
  {
    id: 'muse-agent-mark',
    why: 'ai-muse is the simple-icons `meta` path in Meta blue, padded like the other circle-clipped marks (AITD-424).',
    run(ctx) {
      const muse = ctx.tryRead('Astrid App/Assets.xcassets/ai-muse.imageset/muse.svg')
      const copilot = ctx.tryRead('Astrid App/Assets.xcassets/ai-copilot.imageset/copilot.svg')
      if (muse === null || copilot === null) return [{ file: 'Astrid App/Assets.xcassets', line: 0, message: 'ai-muse or ai-copilot asset is gone' }]
      const viewBox = (svg) => /viewBox="[^"]*"/.exec(svg)?.[0]
      const file = 'Astrid App/Assets.xcassets/ai-muse.imageset/muse.svg'
      const v = []
      if (!muse.includes('M6.915 4.03c-1.968')) v.push({ file, line: 0, message: 'is not the simple-icons meta path' })
      if (muse.includes('M6.2 5.5c-2.6')) v.push({ file, line: 0, message: 'is the hand-drawn stand-in again' })
      if (!muse.includes('#0467DF')) v.push({ file, line: 0, message: 'lost Meta brand blue #0467DF' })
      if (viewBox(copilot) !== 'viewBox="-3 -3 30 30"') v.push({ file: 'Astrid App/Assets.xcassets/ai-copilot.imageset/copilot.svg', line: 0, message: 'changed the padding convention' })
      if (viewBox(muse) !== viewBox(copilot)) v.push({ file, line: 0, message: 'is not padded like copilot.svg' })
      return v
    },
  },
  {
    id: 'debug-only-local-network',
    why: 'The local-network ATS exception, Bonjour services and its usage string ship in Debug only (a5ce5620).',
    run(ctx) {
      const v = []
      const release = ctx.plist('Info.plist')
      const debug = ctx.plist('Info-Debug.plist')
      for (const key of ['NSAppTransportSecurity', 'NSBonjourServices', 'NSLocalNetworkUsageDescription']) {
        if (key in release) v.push({ file: 'Info.plist', line: 0, message: `carries ${key}, which is Debug-only` })
        if (!(key in debug)) v.push({ file: 'Info-Debug.plist', line: 0, message: `lost ${key}` })
      }
      if (!ctx.read('Astrid App.xcodeproj/project.pbxproj').includes('INFOPLIST_FILE = "Info-Debug.plist";')) {
        v.push({ file: 'Astrid App.xcodeproj/project.pbxproj', line: 0, message: 'no configuration uses Info-Debug.plist' })
      }
      return v
    },
  },
  {
    id: 'mac-entitlements',
    why: 'A key macOS does not define is rejected at upload (ITMS-90285, build #571) — after it builds, runs and notarizes. Reminders ride on the calendars entitlement, which must stay.',
    supported: new Set(['com.apple.security.app-sandbox', 'com.apple.security.network.client', 'com.apple.security.network.server',
      'com.apple.security.files.user-selected.read-only', 'com.apple.security.files.user-selected.read-write',
      'com.apple.security.files.downloads.read-write', 'com.apple.security.personal-information.addressbook',
      'com.apple.security.personal-information.calendars', 'com.apple.security.personal-information.location',
      'com.apple.security.device.camera', 'com.apple.security.device.microphone', 'com.apple.security.device.audio-input',
      'com.apple.security.print', 'com.apple.security.automation.apple-events', 'com.apple.security.application-groups',
      'com.apple.developer.applesignin', 'com.apple.developer.associated-domains', 'com.apple.developer.aps-environment',
      'keychain-access-groups']),
    run(ctx) {
      const v = []
      const shipped = ['Astrid Mac/Astrid Mac.entitlements', 'Astrid Mac/Astrid Mac Direct.entitlements']
      for (const file of [...shipped, 'ci_scripts/AstridMacCI.entitlements']) {
        if (!ctx.exists(file)) { v.push(...missingFile(ctx, file)); continue }
        const plist = ctx.plist(file)
        for (const key of Object.keys(plist)) if (!this.supported.has(key)) v.push({ file, line: 0, message: `${key} is not a macOS entitlement — the upload will be rejected` })
        if (shipped.includes(file) && !('com.apple.security.personal-information.calendars' in plist)) {
          v.push({ file, line: 0, message: 'lost the calendars entitlement, which grants Reminders access' })
        }
      }
      return v
    },
  },
  {
    id: 'mac-text-size',
    why: 'Mac views set fonts with .macFont(…), so the text-size setting reaches them.',
    run(ctx) {
      const files = ctx.files(['Astrid Mac']).filter((f) => !f.endsWith('/MacTextSize.swift'))
      return eachCodeLine(ctx, files, (line) => /\.font\((?!scale:)/.test(line) && !line.includes('size: size *')
        && 'sets a font that ignores the text size — use .macFont(…)')
    },
  },
  {
    id: 'localized-keys',
    why: 'Every key the apps look up exists in all twelve languages — a missing key renders as its own name. Keys built at runtime are listed here; retired copy must stay gone.',
    // Built from parts at runtime, so the literal scan below cannot see them.
    requiredKeys: ['tasks.sync_pending_chip', 'tasks.sync_failed_chip',
      'settings.connections.category.app', 'settings.connections.category.token', 'settings.connections.category.webhook',
      'settings.connections.category.unknown', 'settings.connections.owner.you', 'settings.connections.owner.thirdParty',
      'settings.connections.owner.agent', 'lists.recently_completed', 'notifications.due_soon_title',
      'tasks.wont_do', 'tasks.reopen', 'tasks.wont_do_chip', 'tasks.remove_from_board', 'tasks.remove_from_board_confirm',
      'actions.remove', 'lists.sort_filters_personal_note', 'mac.quick_add_placeholder', 'update.available_title',
      'listInsights.days7', 'listInsights.days30', 'listInsights.days90'],
    retiredKeys: ['lists.sort_filters_shared_note'],
    run(ctx) {
      const v = []
      const missing = (key) => LANGUAGES.filter((l) => !ctx.strings(l).has(key))
      for (const lang of LANGUAGES) {
        if (ctx.strings(lang).size === 0) v.push({ file: `${STRINGS_DIR}/${lang}.lproj/Localizable.strings`, line: 0, message: 'is missing or empty' })
      }
      for (const file of ctx.files(['Astrid App', 'Astrid Mac', 'Shared', 'Astrid'])) {
        ctx.lines(file).forEach((line, index) => {
          if (isComment(line)) return
          for (const match of line.matchAll(/NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)"/g)) {
            if (match[1].includes('\\(')) continue
            const absent = missing(match[1])
            if (absent.length) v.push({ file, line: index + 1, message: `"${match[1]}" is missing in ${absent.length === LANGUAGES.length ? 'every language' : absent.join(', ')}` })
          }
        })
      }
      for (const key of this.requiredKeys) {
        const absent = missing(key)
        if (absent.length) v.push({ file: STRINGS_DIR, line: 0, message: `"${key}" is missing in ${absent.join(', ')}` })
      }
      for (const key of this.retiredKeys) {
        const still = LANGUAGES.filter((l) => ctx.strings(l).has(key))
        if (still.length) v.push({ file: STRINGS_DIR, line: 0, message: `"${key}" was retired (AITD-394) but is still in ${still.join(', ')}` })
      }
      // AITD-512: the update card takes the app's name as an argument, so a partner build is not "A new Astrid".
      for (const lang of LANGUAGES) {
        const title = ctx.strings(lang).get('update.available_title')
        if (title && (title.includes('Astrid') || !title.includes('%@'))) v.push({ file: `${STRINGS_DIR}/${lang}.lproj/Localizable.strings`, line: 0, message: `update.available_title must take the brand name as %@, not spell it: "${title}"` })
      }
      const notifications = 'Astrid App/Core/Notifications/NotificationManager.swift'
      if (ctx.tryRead(notifications)?.includes('"Task Due Soon"')) v.push({ file: notifications, line: 0, message: 'hardcodes "Task Due Soon" — use notifications.due_soon_title' })
      // 3a4b6b1c: the Mac add field is a plain invitation in every language, never a syntax tip.
      for (const lang of LANGUAGES) {
        const value = ctx.strings(lang).get('mac.quick_add_placeholder')
        if (value === undefined) continue
        const file = `${STRINGS_DIR}/${lang}.lproj/Localizable.strings`
        if (['(', '（', '#'].some((m) => value.includes(m))) v.push({ file, line: 0, message: `mac.quick_add_placeholder carries a syntax tip: "${value}"` })
        if (!value.trim() || [...value].length > 32) v.push({ file, line: 0, message: `mac.quick_add_placeholder must be a short invitation: "${value}"` })
      }
      if (ctx.strings('en').get('mac.quick_add_placeholder') !== 'Add a task…') v.push({ file: `${STRINGS_DIR}/en.lproj/Localizable.strings`, line: 0, message: 'mac.quick_add_placeholder must read "Add a task…"' })
      return v
    },
  },
  {
    id: 'keyboard-shortcuts-match-web',
    why: 'The Mac\'s bare-key shortcuts are web\'s KEYBOARD_SHORTCUTS (6ac2968e): same keys, same handler. Read from astrid-web itself so drift fails instead of being transcribed by hand.',
    run(ctx) {
      const webRoot = ctx.webDir ? path.resolve(ctx.webDir) : path.resolve(ctx.root, '..', 'astrid-web')
      const webFile = path.join(webRoot, 'hooks', 'useKeyboardShortcuts.ts')
      if (!fs.existsSync(webFile)) {
        if (ctx.webDir) return [{ file: webFile, line: 0, message: 'ASTRID_WEB_DIR does not contain the keyboard contract' }]
        return { violations: [], notes: ['astrid-web is not checked out next to this repo — keyboard parity not checked'] }
      }
      const web = fs.readFileSync(webFile, 'utf8')
      const table = web.slice(web.indexOf('KEYBOARD_SHORTCUTS'), web.indexOf('] as const'))
      const webKeys = new Map()
      for (const m of table.matchAll(/\{\s*key:\s*"((?:[^"\\]|\\.)*)"[^}]*?action:\s*"(\w+)"(?:\s*,\s*param:\s*(\d+))?/g)) {
        webKeys.set(m[1], m[3] === undefined ? m[2] : `${m[2]}(${m[3]})`)
      }
      const macFile = 'Astrid Mac/Keyboard/KeyboardShortcuts.swift'
      const mac = ctx.tryRead(macFile)
      if (mac === null) return missingFile(ctx, macFile)
      const macKeys = new Map()
      // Keys are matched as string literals, so "]" — itself a shortcut — cannot end the array early.
      for (const m of mac.matchAll(/KeyBinding\(keys:\s*\[((?:\s*"(?:[^"\\]|\\.)*"\s*,?)*)\s*\][^\n]*?webAction:\s*"([^"]+)"/g)) {
        for (const k of m[1].matchAll(/"((?:[^"\\]|\\.)*)"/g)) macKeys.set(k[1], m[2])
      }
      const v = []
      if (webKeys.size === 0) v.push({ file: webFile, line: 0, message: 'no KEYBOARD_SHORTCUTS entries parsed — the table moved' })
      for (const [key, action] of webKeys) {
        if (!macKeys.has(key)) v.push({ file: macFile, line: 0, message: `web key "${key}" (${action}) has no Mac binding` })
        else if (macKeys.get(key) !== action) v.push({ file: macFile, line: 0, message: `key "${key}" is ${macKeys.get(key)} on Mac but ${action} on web` })
      }
      for (const key of macKeys.keys()) if (!webKeys.has(key)) v.push({ file: macFile, line: 0, message: `Mac-only bare key "${key}" — web has no such shortcut` })
      return v
    },
  },  {
    id: 'no-palette-pngs',
    why: 'UIKit cannot decompress an 8-bit colormap PNG for display: it logs "Error -17102 decompressing image -- possibly corrupt" for every row that draws one, on as many threads (AITD-551). Re-encode as RGBA.',
    run(ctx) {
      // PNG colour type is byte 25 — the IHDR chunk's — and 3 is indexed colour.
      const isPalette = (b) => b.length > 25 && b.toString('latin1', 12, 16) === 'IHDR' && b[25] === 3
      return ctx.files(['Astrid App', 'Astrid Mac', 'Shared', 'Brands'], ['.png'])
        .filter((file) => isPalette(fs.readFileSync(ctx.abs(file))))
        .map((file) => ({ file, line: 0, message: 'is a palette (colormap) PNG — re-encode it as RGBA' }))
    },
  },
]

// ─── The Mac string tokenizer (moved from MacHardcodedStringGuardTests) ─────────────────────────

const USER_FACING = ['Text', 'Button', 'Label', 'Toggle', 'Picker', 'Menu', 'Section', 'Link', 'Stepper', 'TextField',
  'LabeledContent', 'confirmationDialog', 'alert', 'navigationTitle', 'help', 'accessibilityLabel']
const ALLOWED = new Set(['Astrid', 'astrid', 'Astrid Mac'])
// `String(…)` is the one call whose argument IS the shown text; everything else (NSLocalizedString,
// Brand.localized, MacMemberRoleLabel.title) takes a key or a value, not prose.
const TRANSPARENT = new Set(['String'])
const isIdent = (c) => c !== undefined && /[A-Za-z0-9_]/.test(c)
const identTail = (text) => { let n = 0; while (n < text.length && isIdent(text[text.length - 1 - n])) n += 1; return n }

function openingParens(code) {
  const opens = []
  for (const api of USER_FACING) {
    let from = 0
    for (;;) {
      const at = code.indexOf(`${api}(`, from)
      if (at < 0) break
      from = at + api.length + 1
      if (at > 0 && isIdent(code[at - 1])) continue
      opens.push(at + api.length + 1)
    }
  }
  return opens
}

function scanArgument(text) {
  let depth = 0, inString = false, escaped = false, argument = ''
  for (const c of text) {
    if (escaped) { escaped = false; argument += c; continue }
    if (inString) { if (c === '\\') escaped = true; if (c === '"') inString = false; argument += c; continue }
    if (c === '"') inString = true
    else if ('([{'.includes(c)) depth += 1
    else if (')]}'.includes(c)) { if (depth === 0) return argument; depth -= 1 }
    else if (c === ',' && depth === 0) return argument
    argument += c
  }
  return null
}

function firstArgument(code, open, lines, index) {
  let text = code.slice(open)
  let ahead = index
  while (scanArgument(text) === null && ahead + 1 < lines.length && ahead - index < 4) {
    ahead += 1
    text += ` ${lines[ahead].trim()}`
  }
  return scanArgument(text) ?? text
}

function skipBalanced(text, start) {
  let depth = 0, inString = false, escaped = false, i = start
  while (i < text.length) {
    const c = text[i]; i += 1
    if (escaped) { escaped = false; continue }
    if (inString) { if (c === '\\') escaped = true; if (c === '"') inString = false; continue }
    if (c === '"') inString = true
    else if (c === '(') depth += 1
    else if (c === ')') { depth -= 1; if (depth === 0) return i }
  }
  return i
}

function stripNestedCalls(argument) {
  let result = '', pending = '', i = 0, inString = false, escaped = false
  while (i < argument.length) {
    const c = argument[i]
    if (escaped) { escaped = false; pending += c; i += 1; continue }
    if (inString) { if (c === '\\') escaped = true; if (c === '"') inString = false; pending += c; i += 1; continue }
    if (c === '"') { inString = true; pending += c; i += 1; continue }
    if (c === '(' && identTail(pending) > 0) {
      const n = identTail(pending)
      const name = pending.slice(pending.length - n)
      result += pending.slice(0, pending.length - n)
      pending = ''
      i = TRANSPARENT.has(name) ? i + 1 : skipBalanced(argument, i)
      continue
    }
    pending += c
    i += 1
  }
  return result + pending
}

const stripComparisons = (text) => text.replace(/[=!]=\s*"(\\.|[^"\\])*"/g, ' ')

function literals(text) {
  const found = []
  let current = null, escaped = false
  for (const c of text) {
    if (current !== null) {
      if (escaped) { escaped = false; current += c; continue }
      if (c === '\\') { escaped = true; current += c; continue }
      if (c === '"') { found.push(current); current = null; continue }
      current += c
    } else if (c === '"') current = ''
  }
  return found
}

function isProse(literal) {
  let stripped = literal
  for (;;) {
    const open = stripped.indexOf('\\(')
    const close = open >= 0 ? stripped.indexOf(')', open + 2) : -1
    if (open < 0 || close < 0) break
    stripped = stripped.slice(0, open) + stripped.slice(close + 1)
  }
  return /[A-Za-z]{2,}/.test(stripped)
}

const proseIn = (expression) => literals(stripComparisons(stripNestedCalls(expression)))
  .filter((l) => !ALLOWED.has(l) && isProse(l))

export function macLiteralViolations(sources) {
  const violations = []
  for (const [file, source] of Object.entries(sources)) {
    const lines = source.split('\n')
    lines.forEach((line, index) => {
      const code = line.trim()
      if (code.startsWith('//')) return
      for (const open of openingParens(code)) {
        const argument = firstArgument(code, open, lines, index)
        if (argument.trim().startsWith('verbatim:')) continue
        for (const literal of proseIn(argument)) violations.push({ file, line: index + 1, message: `shows "${literal}" — use a Localizable.strings key, or Text(verbatim:) for non-prose` })
      }
    })
  }
  return violations
}

function outermostCallees(argument) {
  const names = [], opens = []
  let preceding = '', inString = false, escaped = false
  for (const c of argument) {
    if (escaped) { escaped = false; continue }
    if (inString) { if (c === '\\') escaped = true; if (c === '"') inString = false; continue }
    if (c === '"') inString = true
    else if (c === '(') {
      const name = preceding.slice(preceding.length - identTail(preceding))
      const transparent = TRANSPARENT.has(name)
      if (!transparent && !opens.includes(true) && name) names.push(name)
      opens.push(!transparent)
    } else if (c === ')') opens.pop()
    preceding += c
  }
  return names
}

function returnedExpressions(body) {
  const expressions = []
  for (const raw of body.split('\n')) {
    const line = raw.trim()
    if (line.startsWith('//')) continue
    const ret = /\breturn\s+/.exec(line)
    if (ret) expressions.push(line.slice(ret.index + ret[0].length))
    for (const m of line.matchAll(/\?\?\s*"(\\.|[^"\\])*"/g)) expressions.push(m[0].slice(2))
  }
  const trimmed = body.trim()
  if (!trimmed.includes('\n') && !trimmed.includes('return')) expressions.push(trimmed)
  return expressions
}

function skipBalancedBraces(text, start) {
  let depth = 0, inString = false, escaped = false, i = start
  while (i < text.length) {
    const c = text[i]; i += 1
    if (escaped) { escaped = false; continue }
    if (inString) { if (c === '\\') escaped = true; if (c === '"') inString = false; continue }
    if (c === '"') inString = true
    else if (c === '{') depth += 1
    else if (c === '}') { depth -= 1; if (depth === 0) return i }
  }
  return i
}

export function macHelperLiteralViolations(sources) {
  const shown = new Set()
  for (const source of Object.values(sources)) {
    const lines = source.split('\n')
    lines.forEach((line, index) => {
      const code = line.trim()
      if (code.startsWith('//')) return
      for (const open of openingParens(code)) {
        for (const name of outermostCallees(firstArgument(code, open, lines, index))) shown.add(name)
      }
    })
  }
  const violations = []
  const declaration = /\bfunc\s+(\w+)\s*\([^)]*\)\s*(?:throws\s*)?->\s*String\??\s*\{/g
  for (const [file, source] of Object.entries(sources).sort()) {
    for (const match of source.matchAll(declaration)) {
      if (!shown.has(match[1])) continue
      const brace = match.index + match[0].length - 1
      const body = source.slice(brace + 1, skipBalancedBraces(source, brace) - 1)
      for (const expression of returnedExpressions(body)) {
        for (const literal of proseIn(expression)) violations.push({ file, line: lineOf(source, match.index), message: `${match[1]} returns "${literal}" and is shown — return NSLocalizedString(…)` })
      }
    }
  }
  return violations
}

// ─── Running ────────────────────────────────────────────────────────────────────────────────────

export function runRules(root, only = [], options = {}) {
  const ctx = makeContext(root, options)
  return rules.filter((r) => only.length === 0 || only.includes(r.id)).map((rule) => {
    let result
    try { result = rule.run(ctx) } catch (error) { result = [{ file: rule.id, line: 0, message: `crashed: ${error.message}` }] }
    const { violations, notes } = Array.isArray(result) ? { violations: result, notes: [] } : result
    return { id: rule.id, why: rule.why, violations, notes }
  })
}

function main() {
  const args = process.argv.slice(2)
  const scriptDir = path.dirname(fileURLToPath(import.meta.url))
  let root = path.resolve(scriptDir, '..')
  const only = []
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === '--root') root = path.resolve(args[++i])
    else if (args[i] === '--only') only.push(args[++i])
    else if (args[i] === '--list') { for (const r of rules) console.log(`${r.id}\n    ${r.why}`); return 0 }
  }
  const results = runRules(root, only, { webDir: process.env.ASTRID_WEB_DIR })
  let failed = 0
  for (const { id, why, violations, notes } of results) {
    if (violations.length === 0) {
      console.log(`\x1b[0;32m  ✓ ${id}\x1b[0m`)
    } else {
      failed += 1
      console.log(`\x1b[0;31m  ✗ ${id}\x1b[0m — ${why}`)
      for (const v of violations) console.log(`      ${v.file}${v.line ? `:${v.line}` : ''}: ${v.message}`)
    }
    for (const note of notes) console.log(`\x1b[1;33m    ⚠ ${note}\x1b[0m`)
  }
  if (failed) console.log(`\x1b[0;31m✗ ${failed} source contract(s) broken\x1b[0m`)
  else console.log(`\x1b[0;32m✓ All ${results.length} source contracts hold\x1b[0m`)
  return failed ? 1 : 0
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  process.exit(main())
}
