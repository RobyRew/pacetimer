import { tr, type BotModule, type Lang, type ModuleApi, type Reply } from '@robyrew/bot-sdk'

const help: Record<Lang, string> = {
  en: 'A countdown on the server. /tide 10m starts it. /tide pause, /tide resume, /tide stop, /tide status.',
  ro: 'O numărătoare pe server. /tide 10m o pornește. /tide pause, /tide resume, /tide stop, /tide status.',
  es: 'Una cuenta atrás en el servidor. /tide 10m la empieza. /tide pause, /tide resume, /tide stop, /tide status.',
}

interface Timer {
  /** Epoch ms when it hits zero, or null while paused. */
  endsAt: number | null
  /** Remaining ms while paused. */
  left: number
  chatId: string
}

function key(chatId: string): string {
  return `timer:${chatId}`
}

function read(api: ModuleApi, chatId: string): Timer | null {
  const raw = api.get(key(chatId))
  if (!raw) return null
  try {
    return JSON.parse(raw) as Timer
  } catch {
    return null
  }
}

function write(api: ModuleApi, timer: Timer): void {
  api.set(key(timer.chatId), JSON.stringify(timer))
}

function remaining(timer: Timer, now: number): number {
  if (timer.endsAt == null) return timer.left
  return Math.max(0, timer.endsAt - now)
}

function format(ms: number): string {
  const total = Math.ceil(ms / 1000)
  const m = Math.floor(total / 60)
  const s = total % 60
  return `${m}:${s.toString().padStart(2, '0')}`
}

function parseDuration(raw: string): number | null {
  const match = raw.trim().match(/^(\d+)\s*(s|m|h)?$/i)
  if (!match) return null
  const n = Number(match[1])
  const unit = (match[2] ?? 'm').toLowerCase()
  if (n <= 0) return null
  if (unit === 's') return n * 1000
  if (unit === 'h') return n * 3_600_000
  return n * 60_000
}

export const tideModule: BotModule = {
  id: 'tide',
  commands: ['tide'],
  bucket: 'none',
  signIn: 'no',
  menu: (lang) => 'Tide',
  help: (lang) => help[lang],
  async handle(input, api): Promise<Reply> {
    const arg = input.args.trim().toLowerCase()
    const now = input.now.getTime()
    const current = read(api, input.chatId)
    if (!arg) {
      return { kind: 'text', text: current ? format(remaining(current, now)) : help[input.lang] }
    }
    if (arg === 'status') {
      return {
        kind: 'text',
        text: current
          ? format(remaining(current, now))
          : tr(input.lang, { en: 'No timer in this chat.', ro: 'Nu e numărătoare în chatul ăsta.', es: 'No hay cuenta atrás en este chat.' }),
      }
    }
    if (arg === 'stop') {
      api.del(key(input.chatId))
      return { kind: 'text', text: tr(input.lang, { en: 'Timer cleared.', ro: 'Numărătoarea a fost ștearsă.', es: 'Cuenta atrás borrada.' }) }
    }
    if (arg === 'pause' && current && current.endsAt != null) {
      current.left = remaining(current, now)
      current.endsAt = null
      write(api, current)
      return { kind: 'text', text: format(current.left) }
    }
    if (arg === 'resume' && current && current.endsAt == null && current.left > 0) {
      current.endsAt = now + current.left
      write(api, current)
      return { kind: 'text', text: format(current.left) }
    }
    const ms = parseDuration(arg)
    if (ms == null) return { kind: 'text', text: help[input.lang] }
    write(api, { endsAt: now + ms, left: ms, chatId: input.chatId })
    return { kind: 'text', text: format(ms) }
  },
}
