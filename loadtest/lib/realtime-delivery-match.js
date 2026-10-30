/**
 * Pure helpers for correlating Supabase Realtime postgres_changes to a sent row.
 * (Unit-tested in Node; imported by k6 realtime-phoenix.js.)
 */

export function extractPostgresChangeRecord(obj) {
  if (!obj || typeof obj !== "object") {
    return null
  }
  const ev = obj.event
  if (ev !== "postgres_changes" && ev !== "INSERT" && ev !== "UPDATE" && ev !== "DELETE") {
    return null
  }
  const payload = obj.payload
  if (!payload) {
    return null
  }
  const data = payload.data || payload
  const record = data.record || data.new || data
  if (!record || typeof record !== "object") {
    return null
  }
  return record
}

/**
 * @param {object} record — postgres row from Realtime
 * @param {{ table: string, messageId: string, conversationId?: string, roomId?: string }} watch
 */
export function matchesCorrelatedDelivery(record, watch) {
  if (!record || !watch) {
    return false
  }
  const id = record.id != null ? String(record.id) : ""
  if (!id || id !== String(watch.messageId)) {
    return false
  }
  if (watch.table === "messages") {
    const cid = record.conversation_id != null ? String(record.conversation_id) : ""
    return !!watch.conversationId && cid === String(watch.conversationId)
  }
  if (watch.table === "room_messages") {
    const rid = record.room_id != null ? String(record.room_id) : ""
    return !!watch.roomId && rid === String(watch.roomId)
  }
  return false
}

export function deliveryTimeoutMsFromEnv(env) {
  const raw = env && env.LOADTEST_FULL_REALTIME_DELIVERY_TIMEOUT_MS
  if (raw == null || String(raw).trim() === "") {
    return 8000
  }
  const n = Number(raw)
  if (!Number.isFinite(n) || n < 1000 || Math.floor(n) !== n) {
    throw new Error("LOADTEST_FULL_REALTIME_DELIVERY_TIMEOUT_MS must be an integer >= 1000")
  }
  return n
}
