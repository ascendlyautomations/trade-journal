/**
 * Minimal Supabase Realtime Phoenix client for k6/ws (mirrors iOS joinChannel shape).
 */

import ws from "k6/ws"
import { check } from "k6"
import {
  extractPostgresChangeRecord,
  matchesCorrelatedDelivery,
} from "./realtime-delivery-match.js"
import {
  realtimeDeliveryMs,
  realtimeDeliveryMiss,
  realtimeDeliverySubscribeFail,
  realtimeDeliverySuccess,
  realtimeDeliveryTimeout,
  wsConnectFail,
  wsConnectOk,
  wsSubscribeFail,
  wsSubscribeOk,
} from "./realistic300-full-metrics.js"

export function buildRealtimeWsUrl(supabaseHttpsBase, anonKey) {
  const base = supabaseHttpsBase.replace(/\/+$/, "")
  return (
    base.replace(/^https:/i, "wss:") +
    "/realtime/v1/websocket?apikey=" +
    encodeURIComponent(anonKey) +
    "&vsn=1.0.0"
  )
}

export function postgresBinding(table, filter) {
  return {
    event: "*",
    schema: "public",
    table: table,
    filter: filter,
  }
}

export function phxJoinPayload(accessToken, bindings, presenceEnabled) {
  const postgresChanges = []
  for (let i = 0; i < bindings.length; i++) {
    const b = bindings[i]
    postgresChanges.push({
      event: b.event || "*",
      schema: b.schema || "public",
      table: b.table,
      filter: b.filter,
    })
  }
  const config = {
    broadcast: { ack: false, self: false },
    presence: { key: "", enabled: !!presenceEnabled },
    postgres_changes: postgresChanges,
  }
  const payload = { config: config }
  if (accessToken) {
    payload.access_token = accessToken
  }
  return payload
}

function nextRef(state) {
  state.ref += 1
  return String(state.ref)
}

function sendFrame(socket, state, frame) {
  socket.send(JSON.stringify(frame))
}

export function joinTopic(socket, state, topic, accessToken, bindings) {
  const ref = nextRef(state)
  state.pendingJoins[ref] = { topic: topic, ok: false }
  sendFrame(socket, state, {
    topic: topic,
    event: "phx_join",
    payload: phxJoinPayload(accessToken, bindings, false),
    ref: ref,
    join_ref: ref,
  })
}

export function sendHeartbeat(socket, state) {
  const ref = nextRef(state)
  sendFrame(socket, state, {
    topic: "phoenix",
    event: "heartbeat",
    payload: {},
    ref: ref,
  })
}

function parseRealtimeEvent(raw) {
  try {
    return JSON.parse(raw)
  } catch (_e) {
    return null
  }
}

function handlePhxReply(obj, state) {
  const ref = obj.ref != null ? String(obj.ref) : null
  if (!ref || !state.pendingJoins[ref]) {
    return
  }
  const payload = obj.payload || {}
  const pending = state.pendingJoins[ref]
  if (payload.status === "ok" && obj.topic === pending.topic) {
    pending.ok = true
    wsSubscribeOk.add(1)
  } else if (payload.status && payload.status !== "ok") {
    wsSubscribeFail.add(1)
    pending.failed = true
  }
}

function allTopicsJoined(state, topicCount) {
  let okCount = 0
  for (const ref in state.pendingJoins) {
    if (state.pendingJoins[ref].ok) {
      okCount += 1
    }
  }
  return okCount >= topicCount
}

function anyJoinFailed(state) {
  for (const ref in state.pendingJoins) {
    if (state.pendingJoins[ref].failed) {
      return true
    }
  }
  return false
}

/**
 * Short-lived Realtime session: connect, join topics, optional browse, close.
 */
export function runRealtimeSession(options) {
  const url = options.url
  const topics = options.topics || []
  const sessionMs = options.sessionMs || 12000
  const tags = options.tags || {}

  const state = { ref: 0, pendingJoins: {} }

  const res = ws.connect(
    url,
    { tags: tags },
    function (socket) {
      socket.on("open", function () {
        wsConnectOk.add(1)
        for (let i = 0; i < topics.length; i++) {
          joinTopic(socket, state, topics[i].topic, options.accessToken, topics[i].bindings)
        }
        sendHeartbeat(socket, state)
      })

      socket.on("message", function (raw) {
        const obj = parseRealtimeEvent(raw)
        if (!obj) {
          return
        }
        if (obj.event === "phx_reply") {
          handlePhxReply(obj, state)
        }
      })

      socket.on("error", function () {
        wsConnectFail.add(1)
      })

      socket.setTimeout(function () {
        socket.close()
      }, sessionMs)
    }
  )

  check(res, {
    "ws session finished": function (r) {
      return r && r.status === 101
    },
  })

  return { joinedOk: topics.length }
}

/**
 * Subscribe → wait for phx_join → HTTP send on same socket → correlated delivery wait.
 *
 * sendFn(): { ok, messageId, sentAtMs, conversationId?, roomId?, table }
 * scope: { table, conversationId?, roomId? }
 */
export function runCorrelatedDeliverySession(options) {
  const url = options.url
  const topics = options.topics || []
  const tags = options.tags || {}
  const joinTimeoutMs = options.joinTimeoutMs || 15000
  const deliveryTimeoutMs = options.deliveryTimeoutMs || 8000
  const sessionMs =
    options.sessionMs || joinTimeoutMs + deliveryTimeoutMs + 3000
  const sendFn = options.sendFn
  const scope = options.scope || {}

  const state = {
    ref: 0,
    pendingJoins: {},
    phase: "joining",
    sentAtMs: null,
    watch: null,
    deliveryRecorded: false,
    sendAttempted: false,
    outcome: null,
  }

  const res = ws.connect(
    url,
    { tags: tags },
    function (socket) {
      socket.on("open", function () {
        wsConnectOk.add(1)
        for (let i = 0; i < topics.length; i++) {
          joinTopic(socket, state, topics[i].topic, options.accessToken, topics[i].bindings)
        }
        sendHeartbeat(socket, state)

        socket.setTimeout(function tryJoinDeadline() {
          if (state.phase !== "joining") {
            return
          }
          if (!allTopicsJoined(state, topics.length) || anyJoinFailed(state)) {
            state.phase = "done"
            state.outcome = "subscribe_fail"
            realtimeDeliverySubscribeFail.add(1)
            realtimeDeliveryMiss.add(1)
            socket.close()
          }
        }, joinTimeoutMs)
      })

      socket.on("message", function (raw) {
        const obj = parseRealtimeEvent(raw)
        if (!obj) {
          return
        }
        if (obj.event === "phx_reply") {
          handlePhxReply(obj, state)
          if (
            state.phase === "joining" &&
            allTopicsJoined(state, topics.length) &&
            !anyJoinFailed(state) &&
            !state.sendAttempted
          ) {
            state.sendAttempted = true
            state.phase = "sending"
            const sent = sendFn()
            if (!sent || !sent.ok || !sent.messageId) {
              state.phase = "done"
              state.outcome = "send_failed"
              socket.close()
              return
            }
            state.sentAtMs = sent.sentAtMs
            state.watch = {
              table: scope.table || sent.table,
              messageId: sent.messageId,
              conversationId: scope.conversationId || sent.conversationId,
              roomId: scope.roomId || sent.roomId,
              timeoutMs: deliveryTimeoutMs,
            }
            state.phase = "waiting_delivery"
          }
          return
        }

        if (state.phase === "waiting_delivery" && state.watch && !state.deliveryRecorded) {
          if (Date.now() - state.sentAtMs > state.watch.timeoutMs) {
            state.outcome = "delivery_timeout"
            realtimeDeliveryTimeout.add(1)
            realtimeDeliveryMiss.add(1)
            state.phase = "done"
            socket.close()
            return
          }
          const record = extractPostgresChangeRecord(obj)
          if (record && matchesCorrelatedDelivery(record, state.watch)) {
            realtimeDeliveryMs.add(Date.now() - state.sentAtMs)
            realtimeDeliverySuccess.add(1)
            state.deliveryRecorded = true
            state.phase = "done"
            state.outcome = "success"
            socket.close()
          }
        }
      })

      socket.on("error", function () {
        wsConnectFail.add(1)
      })

      socket.setTimeout(function () {
        if (state.phase === "waiting_delivery" && state.watch && !state.deliveryRecorded) {
          if (Date.now() - state.sentAtMs > state.watch.timeoutMs) {
            state.outcome = "delivery_timeout"
            realtimeDeliveryTimeout.add(1)
            realtimeDeliveryMiss.add(1)
          }
        }
        if (state.phase === "joining" && !state.sendAttempted) {
          state.outcome = "subscribe_fail"
          realtimeDeliverySubscribeFail.add(1)
          realtimeDeliveryMiss.add(1)
        }
        socket.close()
      }, sessionMs)
    }
  )

  check(res, {
    "ws delivery session finished": function (r) {
      return r && r.status === 101
    },
  })

  return {
    outcome: state.outcome,
    deliveryRecorded: state.deliveryRecorded,
    sendSucceeded: state.watch != null,
  }
}
