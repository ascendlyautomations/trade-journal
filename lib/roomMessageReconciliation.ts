/** Max confirmed server IDs retained to suppress late Realtime echoes. */
export const ROOM_MESSAGE_CONFIRMED_MAX = 200

export type PendingSendInput = {
  tempId: string
  roomId: string
  userId: string
  sectionId: string | null
  type: string
  /** Normalized correlation key (text content, trade id, image marker, etc.). */
  contentKey: string
}

export type PendingSendHandle = {
  tempId: string
  complete: (row: Record<string, unknown> | null) => void
  fail: () => void
}

export type RealtimeInsertContext = {
  messageId: string
  partial: Record<string, unknown>
  roomId: string
  viewerId: string | null
  hydrate: () => Promise<Record<string, unknown> | null>
}

export type ReconcileRealtimeResult =
  | "skipped_confirmed"
  | "awaited_local_send"
  | "hydrated"
  | "hydrate_failed"
  | "no_viewer"

function normalizeContentKey(input: {
  type?: string | null
  content?: string | null
  trade_id?: string | null
  image_url?: string | null
}): string {
  const type = String(input.type ?? "text")
  if (type === "trade" && input.trade_id) {
    return `trade:${String(input.trade_id)}`
  }
  if (type === "image") {
    return `image:${String(input.content ?? "").trim()}`
  }
  if (type === "voice") {
    return `voice:${String(input.content ?? "").trim()}`
  }
  return `text:${String(input.content ?? "").trim()}`
}

export function buildPendingSendContentKey(
  input: PendingSendInput["type"] extends string
    ? {
        type: string
        content?: string | null
        trade_id?: string | null
        image_url?: string | null
      }
    : never
): string {
  return normalizeContentKey(input)
}

type PendingMutation = PendingSendInput & {
  promise: Promise<Record<string, unknown> | null>
  resolve: (row: Record<string, unknown> | null) => void
  serverId?: string
}

/**
 * Race-safe reconciliation for local sends vs Realtime INSERT echoes.
 * Viewer-scoped; reset on logout via resetRoomMessageReconciliation().
 */
export class RoomMessageReconciliationOwner {
  readonly viewerId: string
  private confirmedHydrated = new Map<string, number>()
  private pendingByTempId = new Map<string, PendingMutation>()
  private hydrationFlights = new Map<
    string,
    Promise<Record<string, unknown> | null>
  >()

  constructor(viewerId: string) {
    this.viewerId = viewerId
  }

  beginPendingSend(input: PendingSendInput): PendingSendHandle {
    let resolve!: (row: Record<string, unknown> | null) => void
    const promise = new Promise<Record<string, unknown> | null>((res) => {
      resolve = res
    })

    const mutation: PendingMutation = {
      ...input,
      promise,
      resolve,
    }
    this.pendingByTempId.set(input.tempId, mutation)

    const cleanup = () => {
      this.pendingByTempId.delete(input.tempId)
    }

    return {
      tempId: input.tempId,
      complete: (row) => {
        if (row?.id) {
          this.markConfirmed(String(row.id))
          mutation.serverId = String(row.id)
        }
        resolve(row)
        cleanup()
      },
      fail: () => {
        resolve(null)
        cleanup()
      },
    }
  }

  markConfirmed(messageId: string): void {
    if (!messageId) return
    this.confirmedHydrated.set(messageId, Date.now())
    while (this.confirmedHydrated.size > ROOM_MESSAGE_CONFIRMED_MAX) {
      const oldest = this.confirmedHydrated.keys().next().value
      if (oldest == null) break
      this.confirmedHydrated.delete(oldest)
    }
  }

  isConfirmedHydrated(messageId: string): boolean {
    return this.confirmedHydrated.has(messageId)
  }

  clearRoom(roomId: string): void {
    for (const [tempId, pending] of this.pendingByTempId) {
      if (pending.roomId === roomId) {
        pending.resolve(null)
        this.pendingByTempId.delete(tempId)
      }
    }
  }

  reset(): void {
    for (const pending of this.pendingByTempId.values()) {
      pending.resolve(null)
    }
    this.pendingByTempId.clear()
    this.confirmedHydrated.clear()
    this.hydrationFlights.clear()
  }

  private findPendingLocalMutation(
    messageId: string,
    partial: Record<string, unknown>,
    roomId: string,
    viewerId: string
  ): PendingMutation | null {
    for (const pending of this.pendingByTempId.values()) {
      if (pending.serverId === messageId) return pending
      if (pending.roomId !== roomId) continue
      if (pending.userId !== viewerId) continue
      if (String(partial.user_id ?? "") !== viewerId) continue
      if (String(partial.room_id ?? roomId) !== roomId) continue
      const partialSection =
        partial.section_id == null ? null : String(partial.section_id)
      if (pending.sectionId !== partialSection) continue
      const partialType = String(partial.type ?? "text")
      if (pending.type !== partialType) continue
      const partialKey = normalizeContentKey({
        type: partialType,
        content: partial.content as string | null,
        trade_id: partial.trade_id as string | null,
        image_url: partial.image_url as string | null,
      })
      if (pending.contentKey !== partialKey) continue
      return pending
    }
    return null
  }

  async reconcileRealtimeInsert(
    ctx: RealtimeInsertContext
  ): Promise<{ result: ReconcileRealtimeResult; row: Record<string, unknown> | null }> {
    const { messageId, partial, roomId, viewerId, hydrate } = ctx
    if (!viewerId) {
      return { result: "no_viewer", row: null }
    }

    if (this.isConfirmedHydrated(messageId)) {
      return { result: "skipped_confirmed", row: null }
    }

    const pending = this.findPendingLocalMutation(
      messageId,
      partial,
      roomId,
      viewerId
    )
    if (pending) {
      pending.serverId = messageId
      const row = await pending.promise
      if (row?.id) {
        this.markConfirmed(messageId)
        return { result: "awaited_local_send", row }
      }
    }

    const row = await this.hydrateOnce(messageId, hydrate)
    if (row?.id) {
      this.markConfirmed(messageId)
      return { result: "hydrated", row }
    }
    return { result: "hydrate_failed", row: null }
  }

  private hydrateOnce(
    messageId: string,
    hydrate: () => Promise<Record<string, unknown> | null>
  ): Promise<Record<string, unknown> | null> {
    const existing = this.hydrationFlights.get(messageId)
    if (existing) return existing

    const flight = hydrate().finally(() => {
      this.hydrationFlights.delete(messageId)
    })
    this.hydrationFlights.set(messageId, flight)
    return flight
  }
}

let activeOwner: RoomMessageReconciliationOwner | null = null

export function getRoomMessageReconciliation(
  viewerId: string
): RoomMessageReconciliationOwner {
  if (!activeOwner || activeOwner.viewerId !== viewerId) {
    activeOwner = new RoomMessageReconciliationOwner(viewerId)
  }
  return activeOwner
}

export function resetRoomMessageReconciliation(): void {
  activeOwner?.reset()
  activeOwner = null
}

/** @internal tests */
export function __roomMessageReconciliationTestOnlyReset(): void {
  resetRoomMessageReconciliation()
}

export { normalizeContentKey }
