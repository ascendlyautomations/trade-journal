/** V1: per-room/channel scroll restore via localStorage (no DB). */

export type RoomScrollPosition = {
  roomId: string
  sectionId: string | null
  lastMessageId: string | null
  scrollTop: number
  updatedAt: number
}

const STORAGE_KEY = "trade-room-scroll-positions-v1"
const MAX_ENTRIES = 40

export function buildRoomScrollStorageKey(
  roomId: string,
  sectionId: string | null
): string {
  return `${roomId}::${sectionId ?? "null"}`
}

type StoredPayload = {
  version: 1
  positions: Record<
    string,
    Omit<RoomScrollPosition, "roomId" | "sectionId">
  >
}

function readStore(): StoredPayload {
  if (typeof window === "undefined") {
    return { version: 1, positions: {} }
  }
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY)
    if (!raw) return { version: 1, positions: {} }
    const parsed = JSON.parse(raw) as StoredPayload
    if (parsed?.version !== 1 || typeof parsed.positions !== "object") {
      return { version: 1, positions: {} }
    }
    return parsed
  } catch {
    return { version: 1, positions: {} }
  }
}

function writeStore(payload: StoredPayload) {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(payload))
  } catch {
    // Quota or private mode — ignore.
  }
}

export function saveRoomScrollPosition(input: {
  roomId: string
  sectionId: string | null
  lastMessageId: string | null
  scrollTop: number
}): void {
  const key = buildRoomScrollStorageKey(input.roomId, input.sectionId)
  const store = readStore()
  store.positions[key] = {
    lastMessageId: input.lastMessageId,
    scrollTop: Math.max(0, Math.round(input.scrollTop)),
    updatedAt: Date.now(),
  }

  const entries = Object.entries(store.positions).sort(
    (a, b) => (b[1].updatedAt ?? 0) - (a[1].updatedAt ?? 0)
  )
  if (entries.length > MAX_ENTRIES) {
    store.positions = Object.fromEntries(entries.slice(0, MAX_ENTRIES))
  }

  writeStore(store)
}

export function loadRoomScrollPosition(
  roomId: string,
  sectionId: string | null
): RoomScrollPosition | null {
  const key = buildRoomScrollStorageKey(roomId, sectionId)
  const row = readStore().positions[key]
  if (!row) return null
  return {
    roomId,
    sectionId,
    lastMessageId: row.lastMessageId ?? null,
    scrollTop: row.scrollTop ?? 0,
    updatedAt: row.updatedAt ?? 0,
  }
}

/** Topmost message row at or below the upper quarter of the scroll container. */
export function findAnchorMessageId(container: HTMLElement): string | null {
  const nodes = container.querySelectorAll<HTMLElement>(
    "[data-room-message-id]"
  )
  if (nodes.length === 0) return null

  const rect = container.getBoundingClientRect()
  const anchorY = rect.top + rect.height * 0.25

  for (const node of nodes) {
    const nodeRect = node.getBoundingClientRect()
    if (nodeRect.bottom >= anchorY) {
      return node.getAttribute("data-room-message-id")
    }
  }

  return nodes[nodes.length - 1]?.getAttribute("data-room-message-id") ?? null
}

export function isScrollContainerNearBottom(
  container: HTMLElement,
  thresholdPx = 80
): boolean {
  return (
    container.scrollHeight -
      container.scrollTop -
      container.clientHeight <=
    thresholdPx
  )
}

/** Scroll within the messages container (avoids document scroll on mobile Safari). */
export function scrollRoomMessageInContainer(
  container: HTMLElement,
  messageId: string,
  block: "start" | "center" = "start"
): boolean {
  const target = container.querySelector<HTMLElement>(
    `[data-room-message-id="${messageId}"]`
  )
  if (!target) return false

  const containerRect = container.getBoundingClientRect()
  const targetRect = target.getBoundingClientRect()
  const offset =
    targetRect.top - containerRect.top + container.scrollTop

  if (block === "center") {
    container.scrollTop =
      offset - container.clientHeight / 2 + target.clientHeight / 2
  } else {
    container.scrollTop = offset
  }

  return true
}

export function clampScrollTop(container: HTMLElement, scrollTop: number): number {
  const max = Math.max(0, container.scrollHeight - container.clientHeight)
  return Math.min(Math.max(0, scrollTop), max)
}

/** Skip persist while skeleton loaders are shown (no message rows in DOM). */
export function canPersistRoomScrollPosition(
  container: HTMLElement,
  loadingMessages: boolean
): boolean {
  if (loadingMessages) return false
  return container.querySelector("[data-room-message-id]") != null
}

/** After saved restore, avoid treating clamped short layout as "near bottom". */
export function isNearBottomAfterSavedRestore(
  container: HTMLElement,
  savedScrollTop: number,
  thresholdPx = 80
): boolean {
  if (savedScrollTop > container.scrollTop + thresholdPx) {
    return false
  }
  return isScrollContainerNearBottom(container, thresholdPx)
}
