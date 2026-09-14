import type { SupabaseClient } from "@supabase/supabase-js"
import { decryptIntegrationCredentials } from "@/lib/integrations/credentialEncryption"
import { markBrokerConnectionReconnectRequired } from "@/lib/integrations/brokerIntegrationConnection"
import { TradovateMappingSyncCoalescer } from "@/lib/integrations/tradovate/tradovateSyncCoalesce"
import { syncTradovateBrokerAccount } from "@/lib/integrations/tradovate/syncTradovateBrokerAccount"
import { logTradovateSync } from "@/lib/integrations/tradovate/tradovateSyncLogger"
import {
  resolveExternalAccountIdFromPropsEvent,
  tradovatePropsEventTriggersSync,
  type TradovatePropsEvent,
} from "@/lib/integrations/tradovate/tradovateSyncEventRouting"
import { TradovateUserSyncWebSocket } from "@/lib/integrations/tradovate/tradovateUserSyncWebSocket"
import type { TradovateApiEnvironment } from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import {
  credentialsFromRefreshTokens,
  refreshTradovateAccessToken,
  tokenExpiryDates,
} from "@/lib/integrations/tradovate/tradovateTokenRefresh"
import { updateBrokerConnectionCredentials } from "@/lib/integrations/brokerIntegrationConnection"

export type ActiveTradovateConnection = {
  id: string
  user_id: string
  api_environment: TradovateApiEnvironment
  provider_user_id: string
  credentials_ciphertext: string
  access_token_expires_at: string | null
}

export type LinkedMapping = {
  mappingId: string
  userId: string
  externalAccountId: string
  autoSyncEnabled: boolean
}

export async function loadLinkedAutoSyncMappings(
  supabase: SupabaseClient,
  connectionId: string
): Promise<LinkedMapping[]> {
  const { data: rows } = await supabase
    .from("broker_integration_accounts")
    .select("id, user_id, external_account_id, tradetraxs_account_id, sync_enabled, status")
    .eq("connection_id", connectionId)
    .eq("provider", "tradovate")
    .not("tradetraxs_account_id", "is", null)

  const mappings: LinkedMapping[] = []
  for (const row of rows ?? []) {
    if (!row.tradetraxs_account_id || row.sync_enabled === false) continue
    if (row.status === "inactive") continue
    const { data: syncRow } = await supabase
      .from("broker_integration_account_sync")
      .select("auto_sync_enabled")
      .eq("broker_integration_account_id", row.id)
      .maybeSingle()
    const autoSyncEnabled = syncRow?.auto_sync_enabled !== false
    mappings.push({
      mappingId: String(row.id),
      userId: String(row.user_id),
      externalAccountId: String(row.external_account_id),
      autoSyncEnabled,
    })
  }
  return mappings
}

export class TradovateConnectionAutoSyncSession {
  private socket: TradovateUserSyncWebSocket | null = null
  private readonly coalescer = new TradovateMappingSyncCoalescer()
  private readonly orderAccountById = new Map<string, string>()
  private mappingsByExternalAccount = new Map<string, LinkedMapping>()
  private reconnectAttempt = 0
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private stopped = false
  private readonly supabase: SupabaseClient
  private connection: ActiveTradovateConnection

  constructor(supabase: SupabaseClient, connection: ActiveTradovateConnection) {
    this.supabase = supabase
    this.connection = connection
  }

  async start(): Promise<void> {
    this.stopped = false
    await this.refreshMappings()
    await this.reconcileAll("startup")
    await this.openSocket()
  }

  stop(): void {
    this.stopped = true
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer)
    this.socket?.close()
    this.socket = null
    void this.patchListenerStatus("stopped")
  }

  private async refreshMappings(): Promise<void> {
    const mappings = await loadLinkedAutoSyncMappings(this.supabase, this.connection.id)
    this.mappingsByExternalAccount = new Map(
      mappings.map((m) => [m.externalAccountId, m])
    )
  }

  private async reconcileAll(trigger: "startup" | "reconnect"): Promise<void> {
    const mappings = [...this.mappingsByExternalAccount.values()].filter(
      (m) => m.autoSyncEnabled
    )
    for (const mapping of mappings) {
      await this.coalescer.runNow(mapping.mappingId, async () => {
        await syncTradovateBrokerAccount(this.supabase, {
          userId: mapping.userId,
          connectionId: this.connection.id,
          brokerIntegrationAccountId: mapping.mappingId,
          trigger,
        })
      })
    }
  }

  private scheduleMappingSync(
    mapping: LinkedMapping,
    eventCategory: string
  ): void {
    if (!mapping.autoSyncEnabled) return
    void this.supabase
      .from("broker_integration_account_sync")
      .update({
        last_event_at: new Date().toISOString(),
        sync_dirty_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("broker_integration_account_id", mapping.mappingId)

    this.coalescer.schedule(mapping.mappingId, async () => {
      logTradovateSync("auto_sync_debounced", {
        connectionId: this.connection.id,
        mappingId: mapping.mappingId,
        eventCategory,
        trigger: "auto",
      })
      await syncTradovateBrokerAccount(this.supabase, {
        userId: mapping.userId,
        connectionId: this.connection.id,
        brokerIntegrationAccountId: mapping.mappingId,
        trigger: "auto",
      })
    })
  }

  private onPropsEvent(event: TradovatePropsEvent): void {
    if (!tradovatePropsEventTriggersSync(event.entityType)) return
    if (event.entityType.toLowerCase() === "order" && event.entity.id != null) {
      const orderId = String(event.entity.id)
      if (event.entity.accountId != null) {
        this.orderAccountById.set(orderId, String(event.entity.accountId))
      }
    }
    const externalAccountId = resolveExternalAccountIdFromPropsEvent(
      event,
      this.orderAccountById
    )
    logTradovateSync("tradovate_props_event", {
      connectionId: this.connection.id,
      eventCategory: `${event.entityType}.${event.eventType}`,
      provider: "tradovate",
    })
    if (!externalAccountId) {
      for (const mapping of this.mappingsByExternalAccount.values()) {
        if (mapping.autoSyncEnabled) {
          this.scheduleMappingSync(mapping, `${event.entityType}.${event.eventType}`)
        }
      }
      return
    }
    const mapping = this.mappingsByExternalAccount.get(externalAccountId)
    if (mapping) this.scheduleMappingSync(mapping, `${event.entityType}.${event.eventType}`)
  }

  private async ensureAccessToken(): Promise<string | null> {
    let credentials = decryptIntegrationCredentials(
      this.connection.credentials_ciphertext
    )
    const expiresAt = this.connection.access_token_expires_at
    const skewMs = 60_000
    if (expiresAt) {
      const exp = new Date(expiresAt).getTime()
      if (!Number.isNaN(exp) && exp - skewMs > Date.now()) {
        return credentials.access_token
      }
    }
    if (!credentials.refresh_token?.trim()) {
      await markBrokerConnectionReconnectRequired(
        this.supabase,
        this.connection.id,
        this.connection.user_id
      )
      return null
    }
    const refreshed = await refreshTradovateAccessToken(credentials.refresh_token)
    if (!refreshed.ok) {
      await markBrokerConnectionReconnectRequired(
        this.supabase,
        this.connection.id,
        this.connection.user_id
      )
      return null
    }
    const next = credentialsFromRefreshTokens(refreshed.tokens)
    const expiries = tokenExpiryDates(refreshed.tokens)
    await updateBrokerConnectionCredentials(this.supabase, {
      connectionId: this.connection.id,
      userId: this.connection.user_id,
      credentials: next,
      accessTokenExpiresAt: expiries.accessTokenExpiresAt,
      refreshTokenExpiresAt: expiries.refreshTokenExpiresAt,
    })
    const { data } = await this.supabase
      .from("broker_integration_connections")
      .select("credentials_ciphertext, access_token_expires_at")
      .eq("id", this.connection.id)
      .maybeSingle()
    if (data?.credentials_ciphertext) {
      this.connection = {
        ...this.connection,
        credentials_ciphertext: data.credentials_ciphertext,
        access_token_expires_at: data.access_token_expires_at,
      }
      credentials = decryptIntegrationCredentials(data.credentials_ciphertext)
    }
    return credentials.access_token
  }

  private async openSocket(): Promise<void> {
    if (this.stopped) return
    await this.patchListenerStatus("connecting")
    const token = await this.ensureAccessToken()
    if (!token) {
      await this.patchListenerStatus("reconnect_required")
      return
    }
    this.socket?.close()
    this.socket = new TradovateUserSyncWebSocket(
      this.connection.api_environment,
      token,
      this.connection.provider_user_id,
      {
        onPropsEvent: (ev) => this.onPropsEvent(ev),
        onConnected: async () => {
          this.reconnectAttempt = 0
          await this.patchListenerStatus("connected")
        },
        onDisconnected: (reason) => {
          void this.handleDisconnect(reason)
        },
        onFatalError: () => {
          void this.handleDisconnect("fatal")
        },
      }
    )
    this.socket.connect()
  }

  private async handleDisconnect(reason: string): Promise<void> {
    if (this.stopped) return
    await this.patchListenerStatus("error", reason)
    this.socket?.close()
    this.socket = null
    const delay = Math.min(60_000, 1_000 * 2 ** this.reconnectAttempt)
    const jitter = Math.floor(Math.random() * 500)
    this.reconnectAttempt += 1
    this.reconnectTimer = setTimeout(() => {
      void (async () => {
        await this.refreshMappings()
        await this.reconcileAll("reconnect")
        await this.openSocket()
      })()
    }, delay + jitter)
  }

  private async patchListenerStatus(
    status: string,
    errorMessage?: string
  ): Promise<void> {
    const now = new Date().toISOString()
    const patch: Record<string, unknown> = {
      listener_status: status,
      updated_at: now,
    }
    if (status === "connected") {
      patch.listener_last_connected_at = now
      patch.listener_last_error_code = null
      patch.listener_last_error_message = null
    }
    if (status === "stopped" || status === "error") {
      patch.listener_last_disconnected_at = now
    }
    if (status === "error" && errorMessage) {
      patch.listener_last_error_message = errorMessage
      patch.listener_last_error_code = "websocket_disconnect"
    }
    if (this.reconnectAttempt > 0 && status === "connected") {
      patch.listener_reconnect_count = this.reconnectAttempt
    }
    await this.supabase
      .from("broker_integration_connections")
      .update(patch)
      .eq("id", this.connection.id)
  }
}
