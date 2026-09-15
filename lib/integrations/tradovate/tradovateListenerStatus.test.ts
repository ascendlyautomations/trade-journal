import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  tradovateListenerUiState,
  TRADOVATE_WORKER_HEARTBEAT_STALE_MS,
} from "./tradovateListenerStatus.ts"

describe("tradovateListenerUiState", () => {
  it("marks worker offline when heartbeat is stale", () => {
    const stale = new Date(Date.now() - TRADOVATE_WORKER_HEARTBEAT_STALE_MS - 1).toISOString()
    const ui = tradovateListenerUiState({
      listenerStatus: "connected",
      listenerLastConnectedAt: stale,
      listenerLastDisconnectedAt: null,
      listenerReconnectCount: 0,
      listenerLastErrorCode: null,
      listenerLastErrorMessage: null,
      listenerWorkerHeartbeatAt: stale,
    })
    assert.equal(ui.workerAlive, false)
    assert.match(ui.listenerLabel, /offline/i)
  })

  it("shows connected when heartbeat is fresh and status connected", () => {
    const fresh = new Date().toISOString()
    const ui = tradovateListenerUiState({
      listenerStatus: "connected",
      listenerLastConnectedAt: fresh,
      listenerLastDisconnectedAt: null,
      listenerReconnectCount: 0,
      listenerLastErrorCode: null,
      listenerLastErrorMessage: null,
      listenerWorkerHeartbeatAt: fresh,
    })
    assert.equal(ui.workerAlive, true)
    assert.equal(ui.listenerLabel, "Listener connected")
  })
})
