/**
 * Activity ids and counters for realistic300_full / realistic600_full mix verification.
 */

import { Counter } from "k6/metrics"

export const FULL_ACTIVITY_IDS = [
  "feed",
  "dashboard",
  "profile_trades",
  "calendar",
  "passive_view",
  "idle",
  "dm_inbox",
  "dm_thread",
  "room_inbox",
  "room_thread",
  "notifications_watch",
]

const counterById = {}
for (let i = 0; i < FULL_ACTIVITY_IDS.length; i++) {
  const id = FULL_ACTIVITY_IDS[i]
  counterById[id] = new Counter("tradetraxs_activity_" + id)
}

export function recordFullActivity(activityId) {
  const c = counterById[activityId]
  if (c) {
    c.add(1)
  }
}

export function expectedActivityWeight(activityId) {
  const weights = {
    feed: 21,
    dashboard: 13,
    profile_trades: 13,
    calendar: 8,
    passive_view: 13,
    idle: 17,
    dm_inbox: 4,
    dm_thread: 5,
    room_inbox: 2,
    room_thread: 3,
    notifications_watch: 1,
  }
  return weights[activityId] || 0
}
