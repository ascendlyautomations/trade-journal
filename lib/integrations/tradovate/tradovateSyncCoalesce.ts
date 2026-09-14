/**
 * In-process debounce/coalesce for account-scoped canonical REST sync.
 * Used by the long-lived broker-sync worker (not Vercel serverless).
 */
export class TradovateMappingSyncCoalescer {
  private readonly debounceMs: number
  private timers = new Map<string, ReturnType<typeof setTimeout>>()
  private syncing = new Set<string>()
  private pendingAfterSync = new Set<string>()
  private pendingRun = new Map<string, () => Promise<void>>()

  constructor(debounceMs = 1_500) {
    this.debounceMs = debounceMs
  }

  /** Schedule a sync run after debounce; collapses rapid events. */
  schedule(mappingId: string, run: () => Promise<void>): void {
    this.pendingRun.set(mappingId, run)
    if (this.syncing.has(mappingId)) {
      this.pendingAfterSync.add(mappingId)
      return
    }
    const existing = this.timers.get(mappingId)
    if (existing) clearTimeout(existing)
    const timer = setTimeout(() => {
      this.timers.delete(mappingId)
      const fn = this.pendingRun.get(mappingId)
      if (fn) void this.runCoalesced(mappingId, fn)
    }, this.debounceMs)
    this.timers.set(mappingId, timer)
  }

  /** Immediate coalesced run (startup/reconnect reconciliation). */
  async runNow(mappingId: string, run: () => Promise<void>): Promise<void> {
    this.pendingRun.set(mappingId, run)
    const t = this.timers.get(mappingId)
    if (t) {
      clearTimeout(t)
      this.timers.delete(mappingId)
    }
    await this.runCoalesced(mappingId, run)
  }

  private async runCoalesced(
    mappingId: string,
    run: () => Promise<void>
  ): Promise<void> {
    if (this.syncing.has(mappingId)) {
      this.pendingAfterSync.add(mappingId)
      this.pendingRun.set(mappingId, run)
      return
    }
    this.syncing.add(mappingId)
    try {
      await run()
    } finally {
      this.syncing.delete(mappingId)
      if (this.pendingAfterSync.has(mappingId)) {
        this.pendingAfterSync.delete(mappingId)
        const next = this.pendingRun.get(mappingId) ?? run
        await this.runCoalesced(mappingId, next)
      }
    }
  }

  clear(mappingId: string): void {
    const t = this.timers.get(mappingId)
    if (t) clearTimeout(t)
    this.timers.delete(mappingId)
    this.pendingAfterSync.delete(mappingId)
  }
}
