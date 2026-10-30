/**
 * realistic300_full — realistic150 read mix + occasional DM/room HTTP + Realtime (iOS-shaped).
 */

import exec from "k6/execution"
import { sleep } from "k6"
import {
  postgresBinding,
  buildRealtimeWsUrl,
  runCorrelatedDeliverySession,
  runRealtimeSession,
} from "./realtime-phoenix.js"
import { deliveryTimeoutMsFromEnv } from "./realtime-delivery-match.js"
import { recordFullActivity } from "./realistic300-full-activities.js"
import {
  dmSendAttempt,
  roomSendAttempt,
} from "./realistic300-full-metrics.js"
import {
  buildInboxDmFilter,
  buildMemberRoomsFilter,
  pickConversationForEmail,
  pickRoomForEmail,
} from "./realistic300-full-fixture.js"
import {
  insertDirectMessage,
  insertRoomTextMessage,
  scenarioDmThreadBootstrap,
  scenarioMessagingBootstrap,
  taggedLoadTestBody,
} from "./messaging-workload-prod.js"
import { runRealistic150Activity } from "./read-workload-realistic150.js"
import {
  canSendDm,
  canSendRoom,
  parseGlobalSendCaps,
  recordDmAllowanceConsumed,
  recordDmBlockedByCap,
  recordRoomAllowanceConsumed,
  recordRoomBlockedByCap,
  vuSendBudgetState,
} from "./realistic300-full-send-budget.js"

/** Baseline realistic150 weights, scaled to 85% + 15% messaging/realtime. */
const ACTIVITIES = [
  { id: "feed", weight: 21 },
  { id: "dashboard", weight: 13 },
  { id: "profile_trades", weight: 13 },
  { id: "calendar", weight: 8 },
  { id: "passive_view", weight: 13 },
  { id: "idle", weight: 17 },
  { id: "dm_inbox", weight: 4 },
  { id: "dm_thread", weight: 5 },
  { id: "room_inbox", weight: 2 },
  { id: "room_thread", weight: 3 },
  { id: "notifications_watch", weight: 1 },
]

const SEND_DM_IN_THREAD_CHANCE = 0.28
const SEND_ROOM_IN_THREAD_CHANCE = 0.22

function activityTotalWeight() {
  let sum = 0
  for (let i = 0; i < ACTIVITIES.length; i++) {
    sum += ACTIVITIES[i].weight
  }
  return sum
}

function pickFullActivity(vuId, iteration) {
  const total = activityTotalWeight()
  const slot = (vuId * 31 + iteration * 47 + vuId * iteration) % total
  let cursor = 0
  for (let i = 0; i < ACTIVITIES.length; i++) {
    cursor += ACTIVITIES[i].weight
    if (slot < cursor) {
      return ACTIVITIES[i].id
    }
  }
  return ACTIVITIES[0].id
}

function sendCapsFromCtx(ctx) {
  if (ctx && ctx.sendCaps) {
    return ctx.sendCaps
  }
  if (!globalThis.__realistic300FullCaps) {
    globalThis.__realistic300FullCaps = parseGlobalSendCaps(__ENV)
  }
  return globalThis.__realistic300FullCaps
}

function dmTopicsForInbox(fixture, userId) {
  const filter = buildInboxDmFilter(fixture.inboxRealtimeConversationIds)
  if (!filter) {
    return []
  }
  return [
    {
      topic: "realtime:inbox-dms",
      bindings: [postgresBinding("messages", filter)],
    },
    {
      topic: "realtime:dm-read-" + userId,
      bindings: [postgresBinding("conversation_member_preferences", "user_id=eq." + userId)],
    },
  ]
}

function dmTopicsForThread(conversationId, userId) {
  return [
    {
      topic: "realtime:dm-" + conversationId,
      bindings: [
        postgresBinding("messages", "conversation_id=eq." + conversationId),
        postgresBinding("message_reactions", "conversation_id=eq." + conversationId),
      ],
    },
    {
      topic: "realtime:dm-read-" + userId,
      bindings: [postgresBinding("conversation_member_preferences", "user_id=eq." + userId)],
    },
  ]
}

function roomTopicsForThread(roomId, userId) {
  return [
    {
      topic: "realtime:room-live-" + roomId,
      bindings: [
        postgresBinding("room_messages", "room_id=eq." + roomId),
        postgresBinding("room_message_reactions", "room_id=eq." + roomId),
      ],
    },
    {
      topic: "realtime:room-read-" + userId,
      bindings: [postgresBinding("room_members", "user_id=eq." + userId)],
    },
  ]
}

function roomTopicsForInbox(fixture, userId) {
  const filter = buildMemberRoomsFilter(fixture.memberRoomIds)
  if (!filter) {
    return []
  }
  return [
    {
      topic: "realtime:member-rooms",
      bindings: [postgresBinding("room_messages", filter)],
    },
    {
      topic: "realtime:room-read-" + userId,
      bindings: [postgresBinding("room_members", "user_id=eq." + userId)],
    },
  ]
}

function notificationTopics(userId) {
  return [
    {
      topic: "realtime:notifications-" + userId,
      bindings: [postgresBinding("notifications", "user_id=eq." + userId)],
    },
  ]
}

function runDmInbox(base, anonKey, session, ctx, fixture) {
  scenarioMessagingBootstrap(base, anonKey, session)
  sleep(1 + Math.random() * 3)
  const wsUrl = buildRealtimeWsUrl(base, anonKey)
  runRealtimeSession({
    url: wsUrl,
    accessToken: session.token,
    topics: dmTopicsForInbox(fixture, session.userId),
    sessionMs: 8000 + Math.floor(Math.random() * 7000),
    tags: { page: "realtime_dm_inbox" },
  })
  sleep(8 + Math.random() * 40)
}

function runDmThread(base, anonKey, session, ctx, fixture) {
  const conv = pickConversationForEmail(fixture, session.email)
  if (!conv) {
    sleep(5)
    return
  }
  const topics = dmTopicsForThread(conv.id, session.userId)
  const wsUrl = buildRealtimeWsUrl(base, anonKey)
  scenarioDmThreadBootstrap(base, anonKey, session, conv.id)
  sleep(0.8 + Math.random() * 2)

  const budget = vuSendBudgetState(sendCapsFromCtx(ctx))
  const deliveryTimeoutMs = deliveryTimeoutMsFromEnv(__ENV)
  const rollSend = Math.random() < SEND_DM_IN_THREAD_CHANCE

  if (rollSend) {
    dmSendAttempt.add(1)
    if (!canSendDm(budget)) {
      recordDmBlockedByCap()
      runRealtimeSession({
        url: wsUrl,
        accessToken: session.token,
        topics: topics,
        sessionMs: 8000 + Math.floor(Math.random() * 6000),
        tags: { page: "realtime_dm_thread" },
      })
    } else {
      const body = taggedLoadTestBody("vu" + exec.vu.idInTest + "-i" + exec.vu.iterationInScenario)
      const delivery = runCorrelatedDeliverySession({
        url: wsUrl,
        accessToken: session.token,
        topics: topics,
        deliveryTimeoutMs: deliveryTimeoutMs,
        joinTimeoutMs: 15000,
        tags: { page: "realtime_dm_thread_delivery" },
        scope: { table: "messages", conversationId: conv.id },
        sendFn: function () {
          const sent = insertDirectMessage(base, anonKey, session, conv.id, body)
          if (sent.ok && sent.messageId) {
            return {
              ok: true,
              messageId: sent.messageId,
              sentAtMs: sent.sentAtMs,
              table: "messages",
              conversationId: conv.id,
            }
          }
          return { ok: false }
        },
      })
      if (delivery.sendSucceeded) {
        budget.dm += 1
        recordDmAllowanceConsumed()
      }
    }
  } else {
    runRealtimeSession({
      url: wsUrl,
      accessToken: session.token,
      topics: topics,
      sessionMs: 10000 + Math.floor(Math.random() * 8000),
      tags: { page: "realtime_dm_thread" },
    })
  }
  sleep(10 + Math.random() * 50)
}

function runRoomInbox(base, anonKey, session, fixture) {
  scenarioMessagingBootstrap(base, anonKey, session)
  sleep(0.5 + Math.random() * 2)
  const wsUrl = buildRealtimeWsUrl(base, anonKey)
  runRealtimeSession({
    url: wsUrl,
    accessToken: session.token,
    topics: roomTopicsForInbox(fixture, session.userId),
    sessionMs: 8000 + Math.floor(Math.random() * 6000),
    tags: { page: "realtime_room_inbox" },
  })
  sleep(8 + Math.random() * 35)
}

function runRoomThread(base, anonKey, session, ctx, fixture) {
  const room = pickRoomForEmail(fixture, session.email)
  if (!room) {
    sleep(5)
    return
  }
  const topics = roomTopicsForThread(room.id, session.userId)
  const wsUrl = buildRealtimeWsUrl(base, anonKey)
  const budget = vuSendBudgetState(sendCapsFromCtx(ctx))
  const deliveryTimeoutMs = deliveryTimeoutMsFromEnv(__ENV)
  const rollSend = Math.random() < SEND_ROOM_IN_THREAD_CHANCE

  if (rollSend) {
    roomSendAttempt.add(1)
    if (!canSendRoom(budget)) {
      recordRoomBlockedByCap()
      runRealtimeSession({
        url: wsUrl,
        accessToken: session.token,
        topics: topics,
        sessionMs: 8000 + Math.floor(Math.random() * 6000),
        tags: { page: "realtime_room_thread" },
      })
    } else {
      const body = taggedLoadTestBody("room-vu" + exec.vu.idInTest)
      const delivery = runCorrelatedDeliverySession({
        url: wsUrl,
        accessToken: session.token,
        topics: topics,
        deliveryTimeoutMs: deliveryTimeoutMs,
        joinTimeoutMs: 15000,
        tags: { page: "realtime_room_thread_delivery" },
        scope: { table: "room_messages", roomId: room.id },
        sendFn: function () {
          const sent = insertRoomTextMessage(
            base,
            anonKey,
            session,
            room.id,
            body,
            room.sectionId || null
          )
          if (sent.ok && sent.messageId) {
            return {
              ok: true,
              messageId: sent.messageId,
              sentAtMs: sent.sentAtMs,
              table: "room_messages",
              roomId: room.id,
            }
          }
          return { ok: false }
        },
      })
      if (delivery.sendSucceeded) {
        budget.room += 1
        recordRoomAllowanceConsumed()
      }
    }
  } else {
    runRealtimeSession({
      url: wsUrl,
      accessToken: session.token,
      topics: topics,
      sessionMs: 10000 + Math.floor(Math.random() * 8000),
      tags: { page: "realtime_room_thread" },
    })
  }
  sleep(10 + Math.random() * 45)
}

function runNotificationsWatch(base, anonKey, session) {
  const wsUrl = buildRealtimeWsUrl(base, anonKey)
  runRealtimeSession({
    url: wsUrl,
    accessToken: session.token,
    topics: notificationTopics(session.userId),
    sessionMs: 12000 + Math.floor(Math.random() * 10000),
    tags: { page: "realtime_notifications" },
  })
  sleep(15 + Math.random() * 45)
}

export function runRealistic300FullIteration(base, anonKey, session, ctx, fixture) {
  if (!ctx) {
    ctx = {}
  }
  const activity = pickFullActivity(exec.vu.idInTest, exec.vu.iterationInScenario)
  recordFullActivity(activity)

  if (activity === "dm_inbox") {
    runDmInbox(base, anonKey, session, ctx, fixture)
    return
  }
  if (activity === "dm_thread") {
    runDmThread(base, anonKey, session, ctx, fixture)
    return
  }
  if (activity === "room_inbox") {
    runRoomInbox(base, anonKey, session, fixture)
    return
  }
  if (activity === "room_thread") {
    runRoomThread(base, anonKey, session, ctx, fixture)
    return
  }
  if (activity === "notifications_watch") {
    runNotificationsWatch(base, anonKey, session)
    return
  }

  runRealistic150Activity(activity, base, anonKey, session, ctx)
}
