import {
  accountName,
  formatMoney,
  moneyAmount,
  profileName,
  recordId,
  text,
  tradeLabel,
  type DemoDraft,
  type DemoRecord,
} from "./demoAdminModel.ts"

export const DEMO_MEDIA_BUCKET = "demo-media"

export const DEMO_MEDIA_ENTITY_TYPES = [
  "profile",
  "trade",
  "post",
  "clip",
  "story",
  "achievement",
  "room",
  "payout",
] as const

export type DemoMediaEntityType = (typeof DEMO_MEDIA_ENTITY_TYPES)[number]
export type DemoMediaKind = "image" | "video"

const IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"])
const VIDEO_TYPES = new Set(["video/mp4", "video/quicktime", "video/webm"])
const IMAGE_EXT: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
}
const VIDEO_EXT: Record<string, string> = {
  "video/mp4": "mp4",
  "video/quicktime": "mov",
  "video/webm": "webm",
}

export const DEMO_IMAGE_MAX_BYTES = 15 * 1024 * 1024
export const DEMO_CLIP_MAX_BYTES = 100 * 1024 * 1024
export const DEMO_CLIP_MAX_SECONDS = 90
export const DEMO_STORY_MAX_SECONDS = 10
const MAX_DIMENSION = 16000

export function isDemoMediaEntityType(value: string): value is DemoMediaEntityType {
  return (DEMO_MEDIA_ENTITY_TYPES as readonly string[]).includes(value)
}

export function demoMediaObjectPath(
  entityType: string,
  entityId: string,
  extension: string,
  fileId = globalThis.crypto?.randomUUID?.() ?? `file-${Date.now()}`
): string {
  if (!isDemoMediaEntityType(entityType)) {
    throw new Error("Unsupported Demo media type.")
  }
  const id = entityId.replace(/[^A-Za-z0-9._-]/g, "")
  if (!id) throw new Error("Demo record id is missing.")
  const ext = extension.toLowerCase().replace(/[^a-z0-9]/g, "")
  if (!ext) throw new Error("Unsupported Demo media file.")
  const name = fileId.replace(/[^A-Za-z0-9._-]/g, "")
  const path = `demo/${entityType}/${id}/${name}.${ext}`
  if (!isDemoOwnedStoragePath(path)) throw new Error("Demo media path was rejected.")
  return path
}

/** Only objects created for Demo may be deleted. Production paths never match. */
export function isDemoOwnedStoragePath(path: string): boolean {
  if (!path || path.includes("..") || path.includes("\\") || path.startsWith("/") || path.includes("//")) {
    return false
  }
  return /^demo\/(profile|trade|post|clip|story|achievement|room|payout)\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/.test(path)
}

export function demoMediaPathFromUrl(value: string): string | null {
  const marker = `/${DEMO_MEDIA_BUCKET}/`
  const index = value.indexOf(marker)
  if (index < 0) return null
  const path = decodeURIComponent(value.slice(index + marker.length).split(/[?#]/)[0] || "")
  return isDemoOwnedStoragePath(path) ? path : null
}

export function collectDemoMediaPaths(value: unknown, found = new Set<string>()): string[] {
  if (typeof value === "string") {
    const path = demoMediaPathFromUrl(value)
    if (path) found.add(path)
    return [...found]
  }
  if (Array.isArray(value)) {
    for (const item of value) collectDemoMediaPaths(item, found)
    return [...found]
  }
  if (value && typeof value === "object") {
    for (const item of Object.values(value as Record<string, unknown>)) collectDemoMediaPaths(item, found)
  }
  return [...found]
}

export type DemoMediaFile = {
  name: string
  type: string
  size: number
  bytes: Uint8Array
}

export function validateDemoMediaFile(
  file: DemoMediaFile,
  options: { entityType: DemoMediaEntityType; kind: DemoMediaKind }
): string | null {
  if (!file.bytes.byteLength || file.size <= 0) return "The file is empty."
  if (file.bytes.byteLength !== file.size) return "The upload was incomplete."

  const mime = resolvedMime(file)
  if (options.kind === "image") {
    if (!mime || !IMAGE_TYPES.has(mime)) return "Use a JPEG, PNG, WebP, or GIF image."
    if (file.size > DEMO_IMAGE_MAX_BYTES) return "Image must be 15 MB or smaller."
    if (!imageMagicMatches(file.bytes, mime)) return "That image file looks empty or corrupt."
    const dimensions = imageDimensions(file.bytes, mime)
    if (dimensions && (dimensions.width < 1 || dimensions.height < 1)) return "That image has no usable dimensions."
    if (dimensions && (dimensions.width > MAX_DIMENSION || dimensions.height > MAX_DIMENSION)) {
      return "That image is larger than Demo Mode can display."
    }
    return null
  }

  if (!mime || !VIDEO_TYPES.has(mime)) return "Use an MP4, MOV, or WebM video."
  if (file.size > DEMO_CLIP_MAX_BYTES) return "Video must be 100 MB or smaller."
  if (!videoMagicMatches(file.bytes, mime)) return "That video file looks empty or corrupt."
  const duration = mime === "video/webm" ? null : mp4DurationSeconds(file.bytes)
  const limit = options.entityType === "story" ? DEMO_STORY_MAX_SECONDS : DEMO_CLIP_MAX_SECONDS
  if (duration != null && duration > limit + 0.05) {
    return options.entityType === "story"
      ? "Story videos must be 10 seconds or less."
      : "Clips must be 90 seconds or less."
  }
  return null
}

export function extensionForMime(mime: string): string | null {
  return IMAGE_EXT[mime] || VIDEO_EXT[mime] || null
}

export function resolvedMime(file: Pick<DemoMediaFile, "name" | "type">): string | null {
  const mime = file.type.toLowerCase().split(";")[0].trim()
  if (IMAGE_TYPES.has(mime) || VIDEO_TYPES.has(mime)) return mime
  const ext = file.name.toLowerCase().slice(file.name.lastIndexOf("."))
  if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg"
  if (ext === ".png") return "image/png"
  if (ext === ".webp") return "image/webp"
  if (ext === ".gif") return "image/gif"
  if (ext === ".mp4") return "video/mp4"
  if (ext === ".mov") return "video/quicktime"
  if (ext === ".webm") return "video/webm"
  return null
}

function imageMagicMatches(bytes: Uint8Array, mime: string): boolean {
  if (mime === "image/jpeg") return bytes[0] === 0xff && bytes[1] === 0xd8
  if (mime === "image/png") return bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47
  if (mime === "image/gif") return bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46
  if (mime === "image/webp") {
    return bytes.length > 12 && ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WEBP"
  }
  return false
}

function videoMagicMatches(bytes: Uint8Array, mime: string): boolean {
  if (mime === "video/webm") return bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3
  return bytes.length > 12 && ascii(bytes, 4, 4) === "ftyp"
}

function imageDimensions(bytes: Uint8Array, mime: string): { width: number; height: number } | null {
  if (mime === "image/png" && bytes.length >= 24) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
    return { width: view.getUint32(16), height: view.getUint32(20) }
  }
  if (mime === "image/gif" && bytes.length >= 10) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
    return { width: view.getUint16(6, true), height: view.getUint16(8, true) }
  }
  if (mime === "image/jpeg") return jpegSize(bytes)
  return null
}

function jpegSize(bytes: Uint8Array): { width: number; height: number } | null {
  let index = 2
  while (index + 8 < bytes.length) {
    if (bytes[index] !== 0xff) return null
    const marker = bytes[index + 1]
    if (marker === 0xd8 || marker === 0xd9) {
      index += 2
      continue
    }
    const length = (bytes[index + 2] << 8) + bytes[index + 3]
    if (length < 2) return null
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      return {
        height: (bytes[index + 5] << 8) + bytes[index + 6],
        width: (bytes[index + 7] << 8) + bytes[index + 8],
      }
    }
    index += 2 + length
  }
  return null
}

/** Reads an mvhd box when the file is a QuickTime/MP4 container. */
export function mp4DurationSeconds(bytes: Uint8Array): number | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  let offset = 0
  while (offset + 8 <= bytes.length) {
    let size = view.getUint32(offset)
    const type = ascii(bytes, offset + 4, 4)
    let header = 8
    if (size === 1) {
      if (offset + 16 > bytes.length) return null
      const large = view.getBigUint64(offset + 8)
      if (large > BigInt(Number.MAX_SAFE_INTEGER)) return null
      size = Number(large)
      header = 16
    }
    if (size < header || offset + size > bytes.length) return null
    if (type === "moov" || type === "trak" || type === "mdia") {
      const nested = mp4DurationSeconds(bytes.subarray(offset + header, offset + size))
      if (nested != null) return nested
    }
    if (type === "mvhd") {
      const start = offset + header
      const version = bytes[start]
      if (version === 0 && start + 20 <= bytes.length) {
        const timescale = view.getUint32(start + 12)
        const duration = view.getUint32(start + 16)
        return timescale > 0 ? duration / timescale : null
      }
      if (version === 1 && start + 32 <= bytes.length) {
        const timescale = view.getUint32(start + 20)
        const duration = Number(view.getBigUint64(start + 24))
        return timescale > 0 ? duration / timescale : null
      }
      return null
    }
    if (size === 0) break
    offset += size
  }
  return null
}

function ascii(bytes: Uint8Array, start: number, length: number): string {
  let value = ""
  for (let index = 0; index < length; index += 1) value += String.fromCharCode(bytes[start + index] || 0)
  return value
}

export type DemoChangeCounts = { added: number; changed: number; removed: number }
export type DemoChangeSummary = {
  counts?: Record<string, DemoChangeCounts>
  lines?: string[]
  restoredFrom?: number
}

const ISSUE_PATTERNS: Array<{ pattern: RegExp; render: (match: RegExpMatchArray, draft: DemoDraft) => string }> = [
  {
    pattern: /^Trade (\S+) references account \S+, which does not exist\.$/,
    render: (match, draft) => `Trade “${entityLabel(draft, "trade", match[1])}” is assigned to an account that no longer exists.`,
  },
  {
    pattern: /^Trade (\S+) owner \S+ is not a Demo profile\.$/,
    render: (match, draft) => `Trade “${entityLabel(draft, "trade", match[1])}” has an owner that is not a Demo profile.`,
  },
  {
    pattern: /^Post (\S+) author \S+ is not a Demo profile\.$/,
    render: (match, draft) => `Post “${entityLabel(draft, "post", match[1])}” has an author that is not a Demo profile.`,
  },
  {
    pattern: /^Post (\S+) references trade \S+, which does not exist\.$/,
    render: (match, draft) => `Post “${entityLabel(draft, "post", match[1])}” points at a trade that no longer exists.`,
  },
  {
    pattern: /^Clip (\S+) author \S+ is not a Demo profile\.$/,
    render: (match, draft) => `Clip “${entityLabel(draft, "clip", match[1])}” has an author that is not a Demo profile.`,
  },
  {
    pattern: /^Clip (\S+) references trade \S+, which does not exist\.$/,
    render: (match, draft) => `Clip “${entityLabel(draft, "clip", match[1])}” points at a trade that no longer exists.`,
  },
  {
    pattern: /^Story (\S+) author \S+ is not a Demo profile\.$/,
    render: (match, draft) => `Story by ${entityLabel(draft, "story", match[1])} has an author that is not a Demo profile.`,
  },
  {
    pattern: /^Activity (\S+) references trade \S+, which does not exist\.$/,
    render: (match, draft) => `Activity “${entityLabel(draft, "activity", match[1])}” points at a trade that no longer exists.`,
  },
  {
    pattern: /^Activity (\S+) actor \S+ is not a Demo profile\.$/,
    render: (match, draft) => `Activity “${entityLabel(draft, "activity", match[1])}” uses an actor that is not a Demo profile.`,
  },
  {
    pattern: /^Message (\S+) shares trade \S+, which does not exist\.$/,
    render: (match, draft) => `Message in “${messageConversation(draft, match[1])}” shares a trade that no longer exists.`,
  },
  {
    pattern: /^Message (\S+) sender \S+ is not a Demo profile\.$/,
    render: (match, draft) => `Message in “${messageConversation(draft, match[1])}” has a sender that is not a Demo profile.`,
  },
  {
    pattern: /^Payout (\S+) references account \S+, which does not exist\.$/,
    render: (match, draft) => `Payout “${entityLabel(draft, "payout", match[1])}” is assigned to an account that no longer exists.`,
  },
  {
    pattern: /^Vault item (\S+) references trade \S+, which does not exist\.$/,
    render: () => "A Vault item points at a trade that no longer exists.",
  },
]

export function humanizeDemoIssue(issue: string, draft: DemoDraft | undefined): string {
  if (!draft) return issue.replace(/\bdemo[.\w-]*/g, "this item")
  for (const rule of ISSUE_PATTERNS) {
    const match = issue.match(rule.pattern)
    if (match) return rule.render(match, draft)
  }
  return replaceKnownIds(issue, draft)
}

function replaceKnownIds(issue: string, draft: DemoDraft): string {
  const labels = new Map<string, string>()
  for (const row of draft.profiles) labels.set(recordId(row.record), profileOptionLabel(row.record))
  for (const row of draft.accounts) labels.set(recordId(row), accountOptionLabel(row))
  for (const row of draft.trades) labels.set(recordId(row), tradeOptionLabel(row, accountName(draft.accounts.find((account) => recordId(account) === text(row.accountID)))))
  for (const row of draft.conversations) labels.set(recordId(row), text(row.title) || "Conversation")
  let next = issue
  for (const [id, label] of labels) {
    if (id) next = next.replaceAll(id, label)
  }
  return next
}

function entityLabel(draft: DemoDraft, kind: string, id: string): string {
  if (kind === "trade") {
    const trade = draft.trades.find((row) => recordId(row) === id)
    return trade ? tradeOptionLabel(trade, accountName(draft.accounts.find((account) => recordId(account) === text(trade.accountID)))) : "this trade"
  }
  if (kind === "post") return text(draft.posts.find((row) => recordId(row) === id)?.body).slice(0, 60) || "this post"
  if (kind === "clip") return text(draft.clips.find((row) => recordId(row) === id)?.caption) || "this clip"
  if (kind === "story") return profileName(draft.profiles.find((row) => recordId(row.record) === text(draft.stories.find((story) => recordId(story) === id)?.authorProfileID))?.record)
  if (kind === "activity") {
    const row = draft.activity.find((item) => recordId(item) === id)
    return text(row?.body) || text(row?.title) || text(row?.kind) || "this activity"
  }
  if (kind === "payout") {
    const row = draft.payouts.find((item) => recordId(item) === id)
    return row ? formatMoney(moneyAmount(row, "amount")) : "this payout"
  }
  return "this item"
}

function messageConversation(draft: DemoDraft, messageId: string): string {
  const message = draft.messages.find((row) => recordId(row) === messageId)
  const conversation = draft.conversations.find((row) => recordId(row) === text(message?.conversationID))
  return text(conversation?.title) || "a conversation"
}

export function profileOptionLabel(record: DemoRecord | undefined): string {
  const name = profileName(record)
  const username = text(record?.username)
  return username ? `${name} (@${username})` : name
}

export function accountOptionLabel(record: DemoRecord | undefined): string {
  const mode = text(record?.mode)
  const labels: Record<string, string> = {
    evaluation: "Evaluation",
    funded: "Funded",
    live: "Live",
    sim: "Sim",
    backtest: "Backtest",
  }
  return `${accountName(record)} · ${labels[mode] || mode || "Account"}`
}

export function tradeOptionLabel(record: DemoRecord | undefined, account = ""): string {
  if (!record) return "Trade"
  const base = tradeLabel(record)
  return account && account !== "Account" ? `${base} · ${account}` : base
}
