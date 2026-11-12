/**
 * Turn-completion notifier for DeepSeek Harness (macOS).
 *
 * Host-side Cordis plugin. It listens to `agent/status` and, when the main
 * agent finishes a turn that lasted at least `minDurationMs`, posts a macOS
 * notification through the DSHNotify.app helper. The helper is needed on
 * macOS 26+, where legacy NSUserNotification (osascript, terminal-notifier) is
 * authorized but never rendered; it uses UNUserNotificationCenter instead.
 *
 * `activate: true` additionally brings the Harness window to the front, and
 * `sound` names a system sound to play (or "default" / "none").
 *
 * Diagnostics are appended to `logPath` so delivery can be verified.
 */
import { execFile } from 'node:child_process'
import { appendFile, mkdir, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'

export const name = 'turn-notify'

const CACHE_DIR = join(homedir(), 'Library', 'Caches', 'dsh-turn-notify')

const DEFAULTS = {
  /** Show a macOS notification when a turn ends. */
  notify: true,
  /** Bring the Harness window to the front when a turn ends. */
  activate: false,
  /** System sound name without extension, "default", or "none". */
  sound: 'Glass',
  /** Ignore turns shorter than this; short answers are usually still on screen. */
  minDurationMs: 3000,
  /** Skip subagents; only the session's main agent notifies. */
  onlyMainAgent: true,
  /**
   * Treat turns that were already running when this plugin loaded as long
   * enough to notify, instead of dropping them for a missing start time.
   */
  seedRunningTurns: true,
  /** Notification title. */
  title: 'DeepSeek Harness',
  /** Body used when the session has no generated title yet. */
  fallbackBody: 'Turn finished — you can come back',
  /** Bundle id of the Harness app, used by `activate`. */
  appBundleId: 'com.deepseek.dsh',
  /** Notification helper app. */
  appPath: join(homedir(), 'Applications', 'DSHNotify.app'),
  /** Request file read by the helper app. */
  requestPath: join(CACHE_DIR, 'request.json'),
  /** Incremental log used to verify delivery. */
  logPath: join(CACHE_DIR, 'plugin.log'),
}

export function apply(ctx, config = {}) {
  const cfg = { ...DEFAULTS, ...config }
  const runningSince = new Map()
  let queue = Promise.resolve()
  const prepared = new Set()

  const ensureDir = (file) => {
    const dir = dirname(file)
    if (prepared.has(dir)) return Promise.resolve()
    return mkdir(dir, { recursive: true })
      .catch(() => {})
      .then(() => {
        prepared.add(dir)
      })
  }

  const log = (line) => {
    const stamp = new Date().toISOString()
    void ensureDir(cfg.logPath)
      .then(() => appendFile(cfg.logPath, `${stamp} ${line}\n`))
      .catch(() => {})
  }

  const run = (command, args) =>
    new Promise((resolve) => {
      execFile(command, args, { timeout: 20000 }, (error, stdout, stderr) => {
        resolve({ error, stdout, stderr })
      })
    })

  const playSound = async () => {
    if (!cfg.sound || cfg.sound === 'none' || cfg.sound === 'default') return
    const file = `/System/Library/Sounds/${cfg.sound}.aiff`
    if (existsSync(file)) await run('/usr/bin/afplay', [file])
  }

  const deliver = async (title, body) => {
    let delivered = false
    if (cfg.notify && existsSync(cfg.appPath)) {
      // `open` cannot pass argv or environment through LaunchServices, so the
      // helper reads one fixed request file; deliveries are serialized.
      await ensureDir(cfg.requestPath)
      await writeFile(cfg.requestPath, JSON.stringify({ title, body, sound: cfg.sound }))
      const { error, stderr } = await run('/usr/bin/open', ['-n', '-W', cfg.appPath])
      if (error) {
        log(`notify failed: ${error.message} ${stderr ?? ''}`.trim())
      } else {
        delivered = true
        log(`notified: ${body}`)
      }
    }
    // A helper that is missing, disabled, or blocked must still make a sound.
    if (!delivered) await playSound()
    if (cfg.activate) await run('/usr/bin/open', ['-b', cfg.appBundleId])
  }

  const enqueue = (title, body) => {
    queue = queue
      .then(() => deliver(title, body))
      .catch((error) => log(`delivery failed: ${String(error)}`))
    return queue
  }

  const sessionTitleOf = (agent) => {
    try {
      const snapshot = ctx.get('sessionTitle')?.get(agent.session)
      if (typeof snapshot?.title === 'string' && snapshot.title.length > 0) return snapshot.title
    } catch {
      // A missing or failing title service must never block the notification.
    }
    return undefined
  }

  ctx.on('agent/status', ({ agent, status }) => {
    if (status === 'running') {
      runningSince.set(agent, Date.now())
      return
    }
    if (status !== 'idle') return
    const since = runningSince.get(agent)
    runningSince.delete(agent)
    if (since === undefined) return
    const elapsed = Date.now() - since
    if (elapsed < cfg.minDurationMs) return
    if (cfg.onlyMainAgent && agent.session?.header?.parentSession !== undefined) return
    const body = sessionTitleOf(agent) ?? cfg.fallbackBody
    log(`turn end after ${elapsed}ms body=${JSON.stringify(body)}`)
    void enqueue(cfg.title, body)
  })

  if (cfg.seedRunningTurns) {
    try {
      for (const live of ctx.get('agents')?.list() ?? []) {
        if (live.status === 'running') runningSince.set(live, Date.now() - cfg.minDurationMs)
      }
    } catch {
      // Seeding is a convenience; live events still cover later turns.
    }
  }

  log(`installed (notify=${cfg.notify} activate=${cfg.activate} sound=${cfg.sound})`)
}
