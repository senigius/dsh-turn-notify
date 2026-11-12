import assert from 'node:assert/strict'
import { mkdtemp, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { apply } from '../plugin/turn-notify.js'

const dir = await mkdtemp(join(tmpdir(), 'dsh-turn-notify-'))
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

async function readLog(path, timeoutMs = 2000) {
  const started = Date.now()
  let content = ''
  while (Date.now() - started < timeoutMs) {
    try {
      content = await readFile(path, 'utf8')
      if (content.includes('turn end after')) return content
    } catch {
      // The plugin writes asynchronously; the file may not exist yet.
    }
    await wait(25)
  }
  return content
}

function makeContext() {
  const listeners = new Map()
  return {
    ctx: {
      on(name, cb) {
        listeners.set(name, cb)
      },
      get() {
        return undefined
      },
    },
    emit(payload) {
      listeners.get('agent/status')(payload)
    },
  }
}

function config(overrides = {}) {
  return {
    notify: true,
    activate: false,
    sound: 'none',
    minDurationMs: 0,
    onlyMainAgent: true,
    seedRunningTurns: false,
    appPath: join(dir, 'missing.app'),
    requestPath: join(dir, 'request.json'),
    logPath: join(dir, 'plugin.log'),
    ...overrides,
  }
}

{
  const { ctx, emit } = makeContext()
  apply(ctx, config())
  const main = { session: { header: {} } }
  emit({ agent: main, status: 'running' })
  await wait(30)
  emit({ agent: main, status: 'idle' })
  const log = await readLog(join(dir, 'plugin.log'))
  assert.match(log, /installed/)
  assert.equal((log.match(/turn end after/g) ?? []).length, 1)
}

{
  const { ctx, emit } = makeContext()
  const logPath = join(dir, 'subagent.log')
  apply(ctx, config({ logPath }))
  const subagent = { session: { header: { parentSession: 'parent' } } }
  emit({ agent: subagent, status: 'running' })
  await wait(30)
  emit({ agent: subagent, status: 'idle' })
  await wait(200)
  assert.doesNotMatch(await readFile(logPath, 'utf8'), /turn end after/)
}

{
  const { ctx, emit } = makeContext()
  const logPath = join(dir, 'short.log')
  apply(ctx, config({ logPath, minDurationMs: 5000 }))
  const main = { session: { header: {} } }
  emit({ agent: main, status: 'running' })
  emit({ agent: main, status: 'idle' })
  await wait(200)
  assert.doesNotMatch(await readFile(logPath, 'utf8'), /turn end after/)
}

console.log('ok')
