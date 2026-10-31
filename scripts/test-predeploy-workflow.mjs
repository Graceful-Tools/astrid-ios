import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { test } from 'node:test'

const workflow = JSON.parse(execFileSync('ruby', [
  '-ryaml', '-rjson', '-e',
  'puts JSON.generate(YAML.safe_load(File.read(ARGV.fetch(0))))',
  '.github/workflows/predeploy.yml',
], { encoding: 'utf8' }))
const runs = (step, command) => new RegExp(`(^|\\s)${command}(?=\\s|$)`).test(step.run ?? '')

test('AITD-447: the full CI gate runs every local full-gate suite with scoped UI secrets', () => {
  const job = workflow.jobs.predeploy
  const steps = job.steps
  const full = steps.filter((step) => step.if?.includes("inputs.mode == 'full'"))
  for (const command of ['npm run predeploy', 'npm run test:ui', 'npm run test:mac', 'npm run test:mac:ui']) {
    assert.ok(full.some((step) => runs(step, command)), `full gate is missing ${command}`)
  }
  for (const command of ['npm run test:ui', 'npm run test:mac:ui']) {
    const step = full.find((item) => runs(item, command))
    assert.ok(step.env?.DATABASE_URL, `${command} is missing the UI-test database secret`)
    assert.ok(step.env?.NEXTAUTH_SECRET, `${command} is missing the UI-test session secret`)
  }
  assert.equal(job.env?.DATABASE_URL, undefined)
  assert.equal(job.env?.NEXTAUTH_SECRET, undefined)
  assert.ok(steps.some((step) => step.run?.includes('npm run simulator:prepare')))
})

test('AITD-447: CI uses its pinned web checkout for all standard-gate checks', () => {
  const job = workflow.jobs.predeploy
  const web = job.steps.find((step) => step.with?.repository === 'Graceful-Tools/astrid-web')
  assert.equal(web?.with?.path, 'astrid-web')
  assert.equal(web?.with?.ref, 'uitest-run-accounts-v1')
  assert.match(job.env?.ASTRID_WEB_DIR ?? '', /github\.workspace.*astrid-web/)
  assert.match(job.env?.APP_VERSION_TABLE_FILE ?? '', /github\.workspace.*astrid-web\/lib\/app-version\.ts/)
})
