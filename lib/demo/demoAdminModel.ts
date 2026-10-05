export type DemoRecord = Record<string, unknown>

export type DemoProfileRow = {
  role: "viewer" | "peer" | "host"
  record: DemoRecord
}

export type DemoDraft = {
  profiles: DemoProfileRow[]
  accounts: DemoRecord[]
  trades: DemoRecord[]
  posts: DemoRecord[]
  clips: DemoRecord[]
  stories: DemoRecord[]
  achievements: DemoRecord[]
  activity: DemoRecord[]
  conversations: DemoRecord[]
  messages: DemoRecord[]
  rooms: DemoRecord[]
  channels: DemoRecord[]
  memberships: DemoRecord[]
  roomMessages: DemoRecord[]
  checkIns: DemoRecord[]
  payouts: DemoRecord[]
  vaultFolders: DemoRecord[]
  vaultItems: DemoRecord[]
}

export type DemoPublication = {
  version: number
  publishedAt: string | null
  publisherEmail: string | null
  restoredFrom: number | null
  changeSummary?: { lines?: string[]; restoredFrom?: number } | null
  isCurrent: boolean
}

export type DemoChangeSummary = {
  counts?: Record<string, { added: number; changed: number; removed: number }>
  lines?: string[]
}

export type DemoAdminState = {
  ok: boolean
  error?: string
  errors?: string[]
  publishedVersion?: number
  dirty: boolean
  changes?: DemoChangeSummary
  published: DemoPublication | null
  history: DemoPublication[]
  draft: DemoDraft
}

export const DEMO_VIEWER_ID = "demo.explore.trader"

export const STRESS_LABELS: Record<number, string> = {
  1: "Calm",
  2: "Slightly Stressed",
  3: "Moderate",
  4: "Stressed",
  5: "Very Stressed",
}

export const TRADE_EMOTIONS = [
  "Confident",
  "Calm",
  "Focused",
  "Fearful",
  "FOMO",
  "Overconfident",
  "Hesitant",
  "Frustrated",
]

export const ACTIVITY_KINDS = [
  { value: "like", label: "Like" },
  { value: "comment", label: "Comment" },
  { value: "follow", label: "Follow" },
  { value: "room_mention", label: "Trade Room mention" },
  { value: "trading_report", label: "Monthly trading report" },
  { value: "system", label: "System" },
] as const

export function text(value: unknown): string {
  return value == null ? "" : String(value)
}

export function recordId(record: DemoRecord | undefined): string {
  return text(record?.id)
}

export function moneyAmount(record: DemoRecord | undefined, key = "realizedPnL"): number | null {
  const money = record?.[key]
  if (!money || typeof money !== "object") return null
  const amount = (money as { amount?: unknown }).amount
  const parsed = typeof amount === "number" ? amount : Number(amount)
  return Number.isFinite(parsed) ? parsed : null
}

export function formatMoney(amount: number | null): string {
  if (amount == null) return "—"
  const sign = amount > 0 ? "+" : ""
  return `${sign}$${amount.toLocaleString(undefined, { maximumFractionDigits: 2 })}`
}

export function profileName(record: DemoRecord | undefined): string {
  return text(record?.displayName) || text(record?.username) || recordId(record) || "Profile"
}

export function accountName(record: DemoRecord | undefined): string {
  return text(record?.name) || recordId(record) || "Account"
}

export function tradeLabel(record: DemoRecord | undefined): string {
  if (!record) return "Trade"
  const symbol = record.symbol
  const ticker =
    symbol && typeof symbol === "object" ? text((symbol as { ticker?: unknown }).ticker) : text(symbol)
  const when = text(record.entryAt).slice(0, 10)
  return [ticker || "Trade", formatMoney(moneyAmount(record)), when].filter(Boolean).join(" · ")
}

export function sumTradePnL(trades: DemoRecord[]): number {
  return trades.reduce((total, trade) => total + (moneyAmount(trade) ?? 0), 0)
}

/** Swift encodes associated-value enums as `{ case: { _0: id } }`. */
export function sharedContent(kind: "trade" | "feedPost" | "profilePost" | "achievementPost" | "reel", id: string) {
  return { [kind]: { _0: id } }
}

export function sharedContentId(record: DemoRecord | undefined): { kind: string; id: string } | null {
  const shared = record?.sharedContent
  if (!shared || typeof shared !== "object") return null
  for (const [kind, value] of Object.entries(shared as Record<string, unknown>)) {
    if (value && typeof value === "object" && "_0" in value) {
      return { kind, id: text((value as { _0?: unknown })._0) }
    }
  }
  return null
}

export function isoNow(): string {
  return new Date().toISOString()
}

export function toDateTimeLocal(value: unknown): string {
  const raw = text(value)
  if (!raw) return ""
  const date = new Date(raw)
  if (Number.isNaN(date.getTime())) return ""
  const pad = (part: number) => String(part).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

export function fromDateTimeLocal(value: string): string {
  if (!value) return isoNow()
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return isoNow()
  return date.toISOString()
}

export function newDemoId(prefix: string): string {
  const token = Math.random().toString(36).slice(2, 10)
  return `demo.${prefix}.${token}`
}

export function cloneRecord<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T
}

export function readPath(record: DemoRecord, path: string): unknown {
  return path.split(".").reduce<unknown>((current, key) => {
    if (!current || typeof current !== "object") return undefined
    return (current as DemoRecord)[key]
  }, record)
}

export function writePath(record: DemoRecord, path: string, value: unknown): DemoRecord {
  const next = cloneRecord(record)
  const keys = path.split(".")
  let cursor: DemoRecord = next
  for (const key of keys.slice(0, -1)) {
    const child = cursor[key]
    if (!child || typeof child !== "object" || Array.isArray(child)) cursor[key] = {}
    cursor = cursor[key] as DemoRecord
  }
  const last = keys[keys.length - 1]
  if (value === undefined) delete cursor[last]
  else cursor[last] = value
  return next
}

export function setMoney(record: DemoRecord, key: string, amount: string): DemoRecord {
  if (amount.trim() === "") return writePath(record, key, null)
  const parsed = Number(amount)
  const existing = record[key]
  const currency =
    existing && typeof existing === "object"
      ? text((existing as { currencyCode?: unknown }).currencyCode) || "USD"
      : "USD"
  return writePath(record, key, { amount: parsed, currencyCode: currency })
}

export function setMedia(record: DemoRecord, key: string, url: string, kind = "image"): DemoRecord {
  if (!url.trim()) return writePath(record, key, null)
  const existing = record[key]
  const alt =
    existing && typeof existing === "object" ? text((existing as { altText?: unknown }).altText) : ""
  return writePath(record, key, { id: url.trim(), kind, altText: alt || key })
}

export function blankTrade(accountID: string, ownerID = DEMO_VIEWER_ID): DemoRecord {
  const now = isoNow()
  return {
    id: newDemoId("trade"),
    ownerProfileID: ownerID,
    accountID,
    symbol: { ticker: "NQ" },
    side: "long",
    mode: "sim",
    quantity: 1,
    entryPrice: 0,
    exitPrice: 0,
    entryAt: now,
    exitAt: now,
    realizedPnL: { amount: 0, currencyCode: "USD" },
    visibility: "public",
    imageDisplayMode: "fit",
    createdAt: now,
    updatedAt: now,
  }
}

export function blankProfile(): DemoRecord {
  const id = newDemoId("profile")
  const now = isoNow()
  return {
    id,
    userID: id,
    displayName: "New trader",
    username: id.replaceAll(".", ""),
    bio: "",
    traderType: "Futures",
    tradingStyle: "",
    isPrivate: false,
    isCreator: false,
    usernameChangeCount: 0,
    createdAt: now,
  }
}

export function mediaURL(value: unknown): string {
  if (Array.isArray(value)) return mediaURL(value[0])
  if (value && typeof value === "object") return text((value as { id?: unknown }).id)
  return text(value)
}

export function setPostMedia(record: DemoRecord, url: string): DemoRecord {
  if (!url.trim()) return writePath(record, "media", [])
  return writePath(record, "media", [{ id: url.trim(), kind: "image", altText: "Post" }])
}

export function blankActivity(actorID: string, tradeID: string): DemoRecord {
  return {
    id: newDemoId("activity"),
    kind: "like",
    actorProfileID: actorID,
    title: "like",
    body: "",
    tradeID,
    isMention: false,
    isRead: false,
    isReply: false,
    createdAt: isoNow(),
  }
}
