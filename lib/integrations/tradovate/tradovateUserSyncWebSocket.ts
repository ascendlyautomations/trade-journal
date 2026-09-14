import type { TradovateApiEnvironment } from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import { getTradovateWebSocketUrl } from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import type { TradovatePropsEvent } from "@/lib/integrations/tradovate/tradovateSyncEventRouting"

export type { TradovatePropsEvent } from "@/lib/integrations/tradovate/tradovateSyncEventRouting"

export type TradovateUserSyncHandlers = {
  onPropsEvent: (event: TradovatePropsEvent) => void
  onConnected: () => void
  onDisconnected: (reason: string) => void
  onFatalError: (code: string) => void
}

const HEARTBEAT_MS = 2_500

/**
 * Minimal Tradovate user WebSocket client (authorize + user/syncrequest).
 * Events with e=props trigger downstream REST reconciliation only.
 */
export class TradovateUserSyncWebSocket {
  private ws: WebSocket | null = null
  private requestId = 1
  private lastMessageAt = Date.now()
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null
  private closed = false
  private readonly apiEnvironment: TradovateApiEnvironment
  private readonly accessToken: string
  private readonly providerUserId: string
  private readonly handlers: TradovateUserSyncHandlers

  constructor(
    apiEnvironment: TradovateApiEnvironment,
    accessToken: string,
    providerUserId: string,
    handlers: TradovateUserSyncHandlers
  ) {
    this.apiEnvironment = apiEnvironment
    this.accessToken = accessToken
    this.providerUserId = providerUserId
    this.handlers = handlers
  }

  connect(): void {
    this.closed = false
    const url = getTradovateWebSocketUrl(this.apiEnvironment)
    this.ws = new WebSocket(url)
    this.ws.onopen = () => {
      this.sendFrame("authorize", this.accessToken)
      const body = JSON.stringify({
        users: [Number(this.providerUserId)],
      })
      this.sendFrame("user/syncrequest", body)
      this.startHeartbeat()
    }
    this.ws.onmessage = (ev) => {
      this.lastMessageAt = Date.now()
      this.handleMessage(String(ev.data ?? ""))
    }
    this.ws.onclose = () => {
      this.stopHeartbeat()
      if (!this.closed) this.handlers.onDisconnected("socket_closed")
    }
    this.ws.onerror = () => {
      this.handlers.onFatalError("socket_error")
    }
  }

  close(): void {
    this.closed = true
    this.stopHeartbeat()
    this.ws?.close()
    this.ws = null
  }

  private sendFrame(endpoint: string, body: string): void {
    const id = this.requestId++
    const frame = `${endpoint}\n${id}\n\n${body}`
    this.ws?.send(frame)
  }

  private startHeartbeat(): void {
    this.stopHeartbeat()
    this.heartbeatTimer = setInterval(() => {
      if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return
      if (Date.now() - this.lastMessageAt >= HEARTBEAT_MS) {
        this.ws.send("[]")
      }
    }, HEARTBEAT_MS)
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer)
    this.heartbeatTimer = null
  }

  private handleMessage(raw: string): void {
    if (!raw || raw === "[]") return
    const payload = raw.startsWith("a[") ? raw.slice(2, -1) : raw
    let parsed: unknown
    try {
      parsed = JSON.parse(payload)
    } catch {
      return
    }
    const messages = Array.isArray(parsed) ? parsed : [parsed]
    for (const msg of messages) {
      if (!msg || typeof msg !== "object") continue
      const record = msg as Record<string, unknown>
      if (record.s === 200 && record.i === 1) {
        this.handlers.onConnected()
        continue
      }
      if (record.e === "props" && record.d && typeof record.d === "object") {
        const d = record.d as Record<string, unknown>
        const entityType = String(d.entityType ?? "")
        const eventType = String(d.eventType ?? "")
        const entity = (d.entity ?? {}) as Record<string, unknown>
        if (!entityType) continue
        this.handlers.onPropsEvent({ entityType, eventType, entity })
      }
      if (record.e === "shutdown") {
        this.handlers.onDisconnected("shutdown")
      }
    }
  }
}
