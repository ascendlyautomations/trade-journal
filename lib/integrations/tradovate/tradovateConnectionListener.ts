import type { SupabaseClient } from "@supabase/supabase-js"
import type { TradovateListenerSnapshot } from "@/lib/integrations/tradovate/tradovateListenerStatus"

export async function loadTradovateConnectionListenerSnapshot(
  supabase: SupabaseClient,
  connectionId: string,
  userId: string
): Promise<TradovateListenerSnapshot | null> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select(
      "listener_status, listener_last_connected_at, listener_last_disconnected_at, listener_reconnect_count, listener_last_error_code, listener_last_error_message, listener_worker_heartbeat_at"
    )
    .eq("id", connectionId)
    .eq("user_id", userId)
    .eq("provider", "tradovate")
    .maybeSingle()

  if (error || !data) return null

  return {
    listenerStatus: String(data.listener_status ?? "stopped"),
    listenerLastConnectedAt: data.listener_last_connected_at,
    listenerLastDisconnectedAt: data.listener_last_disconnected_at,
    listenerReconnectCount: Number(data.listener_reconnect_count ?? 0),
    listenerLastErrorCode: data.listener_last_error_code,
    listenerLastErrorMessage: data.listener_last_error_message,
    listenerWorkerHeartbeatAt: data.listener_worker_heartbeat_at,
  }
}
