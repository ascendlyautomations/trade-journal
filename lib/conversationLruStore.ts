/** Bounded least-recently-used store for conversation session snapshots. */

export const CONVERSATION_LRU_MAX_SIZE = 25

export type LruConversationEntry<T> = T & {
  lastAccessedAt: number
}

export class ConversationLruStore<T extends { conversationId: string }> {
  private readonly entries = new Map<string, LruConversationEntry<T>>()
  /** Oldest at index 0, most recently used at end. */
  private readonly order: string[] = []
  private pinnedKey: string | null = null

  setPinned(key: string | null) {
    this.pinnedKey = key
  }

  private promote(key: string) {
    const index = this.order.indexOf(key)
    if (index >= 0) {
      this.order.splice(index, 1)
    }
    this.order.push(key)
  }

  peek(key: string): LruConversationEntry<T> | null {
    return this.entries.get(key) ?? null
  }

  get(key: string): LruConversationEntry<T> | null {
    const entry = this.entries.get(key)
    if (!entry) return null
    this.promote(key)
    const touched = { ...entry, lastAccessedAt: Date.now() }
    this.entries.set(key, touched)
    return touched
  }

  touch(key: string): boolean {
    const entry = this.entries.get(key)
    if (!entry) return false
    this.promote(key)
    this.entries.set(key, { ...entry, lastAccessedAt: Date.now() })
    return true
  }

  set(key: string, entry: LruConversationEntry<T>) {
    const isNew = !this.entries.has(key)
    this.entries.set(key, entry)
    this.promote(key)
    if (isNew) {
      this.evict()
    }
  }

  patch(key: string, patch: Partial<T>): LruConversationEntry<T> | null {
    const prev = this.entries.get(key)
    if (!prev) return null
    const next = {
      ...prev,
      ...patch,
      lastAccessedAt: Date.now(),
    }
    this.entries.set(key, next)
    this.promote(key)
    return next
  }

  delete(key: string) {
    this.entries.delete(key)
    const index = this.order.indexOf(key)
    if (index >= 0) {
      this.order.splice(index, 1)
    }
  }

  deleteByPrefix(prefix: string) {
    for (const key of [...this.order]) {
      if (key.startsWith(prefix)) {
        this.delete(key)
      }
    }
  }

  clear() {
    this.entries.clear()
    this.order.length = 0
    this.pinnedKey = null
  }

  size(): number {
    return this.entries.size
  }

  oldestKey(): string | null {
    return this.order[0] ?? null
  }

  findEntry(
    predicate: (entry: LruConversationEntry<T>) => boolean
  ): LruConversationEntry<T> | null {
    for (let i = this.order.length - 1; i >= 0; i--) {
      const key = this.order[i]
      const entry = this.entries.get(key)
      if (entry && predicate(entry)) {
        return entry
      }
    }
    return null
  }

  findEntryForKeyPrefix(
    keyPrefix: string,
    predicate: (entry: LruConversationEntry<T>) => boolean
  ): LruConversationEntry<T> | null {
    for (let i = this.order.length - 1; i >= 0; i--) {
      const key = this.order[i]
      if (!key.startsWith(keyPrefix)) continue
      const entry = this.entries.get(key)
      if (entry && predicate(entry)) {
        return entry
      }
    }
    return null
  }

  private evict() {
    while (this.entries.size > CONVERSATION_LRU_MAX_SIZE) {
      const victim = this.order.find((key) => key !== this.pinnedKey)
      if (!victim) break
      this.delete(victim)
    }
  }
}
