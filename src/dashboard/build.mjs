// Codex token dashboard generator.
// Reads Codex rollout logs (local, read-only) and writes index.html next to this file.
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import readline from 'node:readline'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const CODEX = path.join(os.homedir(), '.codex')
const TEMPLATE = path.join(HERE, 'template.html')
const OUT_FILE = path.join(HERE, 'index.html')

function listJsonl(dir) {
  const out = []
  const walk = (d) => {
    let entries
    try {
      entries = fs.readdirSync(d, { withFileTypes: true })
    } catch {
      return
    }
    for (const e of entries) {
      const p = path.join(d, e.name)
      if (e.isDirectory()) walk(p)
      else if (e.isFile() && e.name.endsWith('.jsonl')) out.push(p)
    }
  }
  walk(dir)
  return out
}

function loadTitles() {
  const map = new Map()
  try {
    const text = fs.readFileSync(path.join(CODEX, 'session_index.jsonl'), 'utf8')
    for (const line of text.split(/\r?\n/)) {
      if (!line.trim()) continue
      try {
        const o = JSON.parse(line)
        if (o.id && o.thread_name) map.set(String(o.id).toLowerCase(), o.thread_name)
      } catch {}
    }
  } catch {}
  return map
}

const titles = loadTitles()

function cleanTitle(s) {
  if (!s) return ''
  const t = String(s).replace(/\u0000/g, '').replace(/\s+/g, ' ').trim()
  if (!t) return ''
  if (t.startsWith('<') || t.startsWith('#') || t.startsWith('Files mentioned')) return ''
  return t.length > 80 ? t.slice(0, 80) + '…' : t
}

function textOfContent(content) {
  if (typeof content === 'string') return content
  if (!Array.isArray(content)) return ''
  const parts = []
  for (const c of content) {
    if (typeof c === 'string') parts.push(c)
    else if (c && typeof c.text === 'string') parts.push(c.text)
  }
  return parts.join('\n')
}

const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : 0)

async function parseFile(file) {
  const session = {
    id: '',
    cwd: '',
    title: '',
    provider: '',
    cli: '',
    startedAt: 0,
    lastAt: 0,
    turns: new Map(),
    badLines: 0,
  }
  let current = null
  let ctxWindow = 0
  let synthetic = 0

  const makeTurn = (turnId, ts) => {
    const t = {
      id: turnId,
      model: '',
      effort: '',
      start: ts || 0,
      end: 0,
      ctxWindow: 0,
      records: [],
      fallback: [],
      userText: '',
    }
    session.turns.set(turnId, t)
    current = t
    return t
  }

  const ensureTurn = (turnId, ts) => {
    if (turnId) {
      let t = session.turns.get(turnId)
      if (!t) t = makeTurn(turnId, ts)
      if (ts) {
        if (!t.start || ts < t.start) t.start = ts
        if (ts > t.end) t.end = ts
      }
      return t
    }
    if (!current) makeTurn('turn-' + ++synthetic, ts)
    if (ts) {
      if (!current.start || ts < current.start) current.start = ts
      if (ts > current.end) current.end = ts
    }
    return current
  }

  const rl = readline.createInterface({
    input: fs.createReadStream(file, { encoding: 'utf8' }),
    crlfDelay: Infinity,
  })

  for await (const line of rl) {
    if (!line) continue
    const has = (s) => line.includes(s)
    try {
      if (has('"type":"session_meta"')) {
        const o = JSON.parse(line)
        const p = o.payload || {}
        session.id = p.session_id || p.id || session.id
        session.cwd = p.cwd || session.cwd
        session.provider = p.model_provider || session.provider
        session.cli = p.cli_version || session.cli
        const ts = Date.parse(p.timestamp || o.timestamp)
        if (ts) session.startedAt = ts
      } else if (has('"type":"turn_context"')) {
        const o = JSON.parse(line)
        const p = o.payload || {}
        const ts = Date.parse(o.timestamp) || 0
        const t = ensureTurn(p.turn_id, ts)
        t.model = p.model || t.model
        t.effort = p.reasoning_effort || (p.settings && p.settings.reasoning_effort) || t.effort
      } else if (has('"type":"token_usage_record"')) {
        const o = JSON.parse(line)
        const p = o.payload || {}
        const ts = Date.parse(o.timestamp) || 0
        const t = ensureTurn(p.turn_id, ts)
        const u = p.usage || {}
        t.records.push({
          ts,
          input: num(u.input_tokens),
          cached: num(u.cached_input_tokens),
          write: num(u.cache_write_input_tokens),
          output: num(u.output_tokens),
          reasoning: num(u.reasoning_output_tokens),
          total: num(u.total_tokens),
          ctx: ctxWindow,
        })
        if (ts > session.lastAt) session.lastAt = ts
      } else if (has('"type":"event_msg"')) {
        if (has('"type":"token_count"')) {
          const o = JSON.parse(line)
          const p = o.payload || {}
          const info = p.info || {}
          const u = info.last_token_usage
          if (!u) continue
          const ts = Date.parse(o.timestamp) || 0
          const t = ensureTurn(p.turn_id, ts)
          if (info.model_context_window) {
            ctxWindow = num(info.model_context_window)
            t.ctxWindow = ctxWindow
          }
          t.fallback.push({
            ts,
            input: num(u.input_tokens),
            cached: num(u.cached_input_tokens),
            write: num(u.cache_write_input_tokens),
            output: num(u.output_tokens),
            reasoning: num(u.reasoning_output_tokens),
            total: num(u.total_tokens),
            ctx: num(info.model_context_window) || ctxWindow,
          })
          if (ts > session.lastAt) session.lastAt = ts
        } else if (has('"type":"task_started"')) {
          const o = JSON.parse(line)
          const p = o.payload || {}
          const ts = num(p.started_at) ? num(p.started_at) * 1000 : Date.parse(o.timestamp) || 0
          if (num(p.model_context_window)) ctxWindow = num(p.model_context_window)
          const t = ensureTurn(p.turn_id, ts)
          if (ctxWindow) t.ctxWindow = ctxWindow
        } else if (has('"type":"task_complete"')) {
          const o = JSON.parse(line)
          const p = o.payload || {}
          const turnId = p.turn_id || (current && current.id)
          const t = turnId ? session.turns.get(turnId) : current
          if (t) {
            const end = num(p.completed_at) ? num(p.completed_at) * 1000 : Date.parse(o.timestamp) || 0
            t.end = end || t.end
            if (num(p.started_at)) t.start = num(p.started_at) * 1000
            if (end > session.lastAt) session.lastAt = end
          }
        } else if (has('"type":"user_message"')) {
          const o = JSON.parse(line)
          const p = o.payload || {}
          const text = cleanTitle(p.message || textOfContent(p.content))
          if (text) {
            if (current && !current.userText) current.userText = text
            if (!session.title) session.title = text
          }
        }
      } else if (has('"type":"response_item"') && has('"role":"user"')) {
        const o = JSON.parse(line)
        const p = o.payload || {}
        const text = cleanTitle(textOfContent(p.content))
        if (text) {
          if (current && !current.userText) current.userText = text
          if (!session.title) session.title = text
        }
      }
    } catch {
      session.badLines++
    }
  }

  const turns = []
  for (const t of session.turns.values()) {
    const reqs = t.records.length ? t.records : t.fallback
    if (!reqs.length) continue
    const win = t.ctxWindow || reqs.find((r) => r.ctx)?.ctx || 0
    for (const r of reqs) if (!r.ctx) r.ctx = win
    turns.push({
      id: t.id,
      model: t.model,
      effort: t.effort,
      start: t.start || (reqs[0] && reqs[0].ts) || 0,
      end: t.end || (reqs[reqs.length - 1] && reqs[reqs.length - 1].ts) || 0,
      title: t.userText,
      requests: reqs,
    })
  }
  turns.sort((a, b) => a.start - b.start)
  if (!turns.length) return null

  const id = session.id || path.basename(file, '.jsonl')
  return {
    id,
    cwd: session.cwd,
    title: titles.get(id.toLowerCase()) || session.title || id.slice(0, 12),
    provider: session.provider,
    cli: session.cli,
    startedAt: session.startedAt || (turns[0] && turns[0].start) || 0,
    lastAt: session.lastAt || (turns[turns.length - 1] && turns[turns.length - 1].end) || 0,
    turns,
    badLines: session.badLines,
  }
}

async function main() {
  const files = [...listJsonl(path.join(CODEX, 'sessions')), ...listJsonl(path.join(CODEX, 'archived_sessions'))]
  const byId = new Map()
  let bad = 0
  for (const file of files) {
    const s = await parseFile(file)
    if (!s) continue
    bad += s.badLines
    const key = s.id.toLowerCase()
    const prev = byId.get(key)
    if (!prev) {
      byId.set(key, s)
      continue
    }
    for (const t of s.turns) {
      if (!prev.turns.some((x) => x.id === t.id)) prev.turns.push(t)
    }
    prev.turns.sort((a, b) => a.start - b.start)
    prev.startedAt = Math.min(prev.startedAt || Infinity, s.startedAt || Infinity)
    prev.lastAt = Math.max(prev.lastAt, s.lastAt)
    if (!prev.cwd) prev.cwd = s.cwd
    if (!prev.title || prev.title === prev.id.slice(0, 12)) prev.title = s.title
  }

  const sessions = [...byId.values()].filter((s) => s.turns.length).sort((a, b) => b.lastAt - a.lastAt)
  const data = {
    generatedAt: new Date().toISOString(),
    source: CODEX,
    sessions,
  }

  const template = fs.readFileSync(TEMPLATE, 'utf8')
  const json = JSON.stringify(data).replace(/</g, '\\u003c')
  const html = template.replace('__DATA__', () => json)
  fs.writeFileSync(OUT_FILE, html, 'utf8')

  let turns = 0
  let requests = 0
  let input = 0
  let cached = 0
  let output = 0
  for (const s of sessions) {
    for (const t of s.turns) {
      turns++
      requests += t.requests.length
      for (const r of t.requests) {
        input += r.input
        cached += r.cached
        output += r.output
      }
    }
  }
  console.log(
    `sessions=${sessions.length} turns=${turns} requests=${requests} input=${input} cached=${cached} output=${output} badLines=${bad}`,
  )
  console.log(`written: ${OUT_FILE}`)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
