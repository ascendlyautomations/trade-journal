/**
 * Production messaging HTTP paths — mirrors iOS DefaultMessageRepository / inbox RPCs.
 */

import http from "k6/http"
import { assertHttpOk, httpParams, supabaseHeaders } from "./k6-shared.js"
import {
  dmSendFail,
  dmSendOk,
  dmThreadBootstrapMs,
  messagingBootstrapMs,
  roomSendFail,
  roomSendOk,
} from "./realistic300-full-metrics.js"

import { REALISTIC300_FULL_MESSAGE_TAG } from "./realistic300-full-tag.js"
export function getLoadtestMessageTag() {
  const fromEnv = __ENV.LOADTEST_FULL_MESSAGE_TAG
  if (fromEnv && String(fromEnv).trim()) {
    return String(fromEnv).trim()
  }
  return REALISTIC300_FULL_MESSAGE_TAG
}

/** Default tag for realistic300_full; realistic600_full sets LOADTEST_FULL_MESSAGE_TAG in env. */
export const LOADTEST_MESSAGE_TAG = REALISTIC300_FULL_MESSAGE_TAG

export function scenarioMessagingBootstrap(base, anonKey, session) {
  const started = Date.now()
  const res = http.post(
    base + "/rest/v1/rpc/rpc_v2_messaging_bootstrap",
    JSON.stringify({
      p_limit: 40,
      p_cursor: null,
      p_mark_message_notifications_read: false,
    }),
    {
      headers: supabaseHeaders(anonKey, session.token, { "Content-Type": "application/json" }),
      ...httpParams("messaging_bootstrap", { parseBody: false }),
    }
  )
  messagingBootstrapMs.add(Date.now() - started)
  assertHttpOk(res, "messaging_bootstrap", 200)
}

export function scenarioDmThreadBootstrap(base, anonKey, session, conversationId) {
  const started = Date.now()
  const res = http.post(
    base + "/rest/v1/rpc/rpc_v1_conversation_thread_bootstrap",
    JSON.stringify({
      p_conversation_id: conversationId,
      p_message_limit: 40,
      p_cursor: null,
      p_mark_read: false,
    }),
    {
      headers: supabaseHeaders(anonKey, session.token, { "Content-Type": "application/json" }),
      ...httpParams("dm_thread_bootstrap", { parseBody: false }),
    }
  )
  dmThreadBootstrapMs.add(Date.now() - started)
  assertHttpOk(res, "dm_thread_bootstrap", 200)
}

export function insertDirectMessage(base, anonKey, session, conversationId, content) {
  const body = {
    conversation_id: conversationId,
    sender_id: session.userId,
    content: content,
    image_url: null,
    channel: null,
  }
  const res = http.post(base + "/rest/v1/messages?select=id,created_at", JSON.stringify(body), {
    headers: supabaseHeaders(anonKey, session.token, {
      "Content-Type": "application/json",
      Prefer: "return=representation",
    }),
    ...httpParams("dm_send", { parseBody: true, extraTags: { op: "insert" } }),
  })
  if (res.status >= 200 && res.status < 300) {
    dmSendOk.add(1)
    let messageId = null
    try {
      const rows = JSON.parse(res.body)
      if (Array.isArray(rows) && rows[0] && rows[0].id) {
        messageId = String(rows[0].id)
      }
    } catch (_e) {
      /* body parse optional */
    }
    return { ok: true, status: res.status, sentAtMs: Date.now(), messageId: messageId }
  }
  dmSendFail.add(1)
  return { ok: false, status: res.status, sentAtMs: Date.now(), messageId: null }
}

export function insertRoomTextMessage(base, anonKey, session, roomId, content, sectionId) {
  const body = {
    room_id: roomId,
    user_id: session.userId,
    content: content,
  }
  if (sectionId) {
    body.section_id = sectionId
  }
  const res = http.post(
    base + "/rest/v1/room_messages?select=id,created_at",
    JSON.stringify(body),
    {
      headers: supabaseHeaders(anonKey, session.token, {
        "Content-Type": "application/json",
        Prefer: "return=representation",
      }),
      ...httpParams("room_send", { parseBody: true, extraTags: { op: "insert" } }),
    }
  )
  if (res.status >= 200 && res.status < 300) {
    roomSendOk.add(1)
    let messageId = null
    try {
      const rows = JSON.parse(res.body)
      if (Array.isArray(rows) && rows[0] && rows[0].id) {
        messageId = String(rows[0].id)
      }
    } catch (_e) {
      /* body parse optional */
    }
    return { ok: true, status: res.status, sentAtMs: Date.now(), messageId: messageId }
  }
  roomSendFail.add(1)
  return { ok: false, status: res.status, sentAtMs: Date.now(), messageId: null }
}

export function taggedLoadTestBody(suffix) {
  return getLoadtestMessageTag() + " " + String(suffix || "").slice(0, 120)
}
