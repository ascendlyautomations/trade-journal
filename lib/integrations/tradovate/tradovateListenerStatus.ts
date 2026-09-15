/** Stale if no worker heartbeat within this window. */
export const TRADOVATE_WORKER_HEARTBEAT_STALE_MS = 90_000

export type TradovateListenerSnapshot = {
  listenerStatus: string
  listenerLastConnectedAt: string | null
  listenerLastDisconnectedAt: string | null
  listenerReconnectCount: number
  listenerLastErrorCode: string | null
  listenerLastErrorMessage: string | null
  listenerWorkerHeartbeatAt: string | null
}

export type TradovateListenerUiState = {
  workerAlive: boolean
  listenerLabel: string
  detail: string
}

export function tradovateListenerUiState(
  snapshot: TradovateListenerSnapshot | null | undefined
): TradovateListenerUiState {
  if (!snapshot) {
    return {
      workerAlive: false,
      listenerLabel: "Worker offline",
      detail: "Automatic sync requires the broker-sync worker process.",
    }
  }

  const heartbeatMs = snapshot.listenerWorkerHeartbeatAt
    ? new Date(snapshot.listenerWorkerHeartbeatAt).getTime()
    : NaN
  const workerAlive =
    Number.isFinite(heartbeatMs) &&
    Date.now() - heartbeatMs <= TRADOVATE_WORKER_HEARTBEAT_STALE_MS

  if (!workerAlive) {
    return {
      workerAlive: false,
      listenerLabel: "Worker offline",
      detail:
        snapshot.listenerStatus === "connected"
          ? "OAuth is connected but no sync worker heartbeat — deploy broker-sync-worker."
          : "Start broker-sync-worker (see docs/tradovate/BROKER_SYNC_WORKER.md).",
    }
  }

  const status = snapshot.listenerStatus
  if (status === "connected") {
    return {
      workerAlive: true,
      listenerLabel: "Listener connected",
      detail: snapshot.listenerLastConnectedAt
        ? `Connected since ${new Date(snapshot.listenerLastConnectedAt).toLocaleString()}`
        : "Receiving Tradovate user events.",
    }
  }
  if (status === "connecting") {
    return {
      workerAlive: true,
      listenerLabel: "Listener connecting",
      detail: "Opening Tradovate user WebSocket…",
    }
  }
  if (status === "reconnect_required") {
    return {
      workerAlive: true,
      listenerLabel: "Reconnect required",
      detail: "Tradovate authorization expired — reconnect in Settings.",
    }
  }
  if (status === "error") {
    return {
      workerAlive: true,
      listenerLabel: "Listener reconnecting",
      detail: snapshot.listenerLastErrorMessage
        ? String(snapshot.listenerLastErrorMessage)
        : "WebSocket disconnected; retrying with backoff.",
    }
  }

  return {
    workerAlive: true,
    listenerLabel: "Listener stopped",
    detail: "Worker is running but this connection session is not active.",
  }
}
