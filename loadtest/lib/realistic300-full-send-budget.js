/**
 * Global write caps for realistic300_full.
 *
 * k6 VUs do not share memory — we enforce a cluster-wide maximum by partitioning
 * a fixed total budget across VU ids (deterministic, race-free).
 * Sum of all VU allowances === global cap exactly.
 */

import exec from "k6/execution"
import { Counter } from "k6/metrics"

export const globalDmCapBlocked = new Counter("tradetraxs_global_dm_cap_blocked")
export const globalRoomCapBlocked = new Counter("tradetraxs_global_room_cap_blocked")
export const globalDmAllowanceConsumed = new Counter("tradetraxs_global_dm_allowance_consumed")
export const globalRoomAllowanceConsumed = new Counter(
  "tradetraxs_global_room_allowance_consumed"
)

export const DEFAULT_MAX_VUS = 300
export const DEFAULT_DM_SENDS_TOTAL = 200
export const DEFAULT_ROOM_SENDS_TOTAL = 200

export function parseGlobalSendCaps(env) {
  const maxVus = parsePositiveInt(env.LOADTEST_MAX_VUS, DEFAULT_MAX_VUS)
  const dmTotal = parsePositiveInt(
    env.LOADTEST_FULL_MAX_DM_SENDS_TOTAL,
    DEFAULT_DM_SENDS_TOTAL
  )
  const roomTotal = parsePositiveInt(
    env.LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL,
    DEFAULT_ROOM_SENDS_TOTAL
  )
  const perVuDm = parseOptionalCap(env.LOADTEST_FULL_MAX_DM_SENDS_PER_VU)
  const perVuRoom = parseOptionalCap(env.LOADTEST_FULL_MAX_ROOM_SENDS_PER_VU)
  return { maxVus, dmTotal, roomTotal, perVuDm, perVuRoom }
}

function parsePositiveInt(raw, fallback) {
  if (raw === undefined || raw === null || String(raw).trim() === "") {
    return fallback
  }
  const n = Number(raw)
  if (!Number.isFinite(n) || n < 0 || Math.floor(n) !== n) {
    throw new Error("Invalid integer cap: " + raw)
  }
  return n
}

function parseOptionalCap(raw) {
  if (raw === undefined || raw === null || String(raw).trim() === "") {
    return null
  }
  const n = Number(raw)
  if (!Number.isFinite(n) || n < 0 || Math.floor(n) !== n) {
    throw new Error("Invalid per-VU cap: " + raw)
  }
  return n
}

/** VUs 1..remainder get base+1 sends; the rest get base (sum === globalCap). */
export function vuAllowanceFromGlobalPartition(globalCap, maxVus, vuIdInTest) {
  const cap = Math.max(0, Math.floor(globalCap))
  const vus = Math.max(1, Math.floor(maxVus))
  const vu = Math.max(1, Math.min(vuIdInTest, vus))
  const base = Math.floor(cap / vus)
  const remainder = cap % vus
  return base + (vu <= remainder ? 1 : 0)
}

function effectiveMax(partitionAllowance, perVuCap) {
  if (perVuCap === null) {
    return partitionAllowance
  }
  return Math.min(partitionAllowance, perVuCap)
}

export function vuSendBudgetState(caps) {
  const vuId = exec.vu.idInTest
  const dmPartition = vuAllowanceFromGlobalPartition(caps.dmTotal, caps.maxVus, vuId)
  const roomPartition = vuAllowanceFromGlobalPartition(caps.roomTotal, caps.maxVus, vuId)
  if (!globalThis.__realistic300FullSendBudget) {
    globalThis.__realistic300FullSendBudget = {}
  }
  const key = vuId
  if (!globalThis.__realistic300FullSendBudget[key]) {
    globalThis.__realistic300FullSendBudget[key] = {
      dm: 0,
      room: 0,
      maxDm: effectiveMax(dmPartition, caps.perVuDm),
      maxRoom: effectiveMax(roomPartition, caps.perVuRoom),
    }
  }
  return globalThis.__realistic300FullSendBudget[key]
}

export function canSendDm(budget) {
  return budget.dm < budget.maxDm
}

export function canSendRoom(budget) {
  return budget.room < budget.maxRoom
}

export function recordDmBlockedByCap() {
  globalDmCapBlocked.add(1)
}

export function recordRoomBlockedByCap() {
  globalRoomCapBlocked.add(1)
}

export function recordDmAllowanceConsumed() {
  globalDmAllowanceConsumed.add(1)
}

export function recordRoomAllowanceConsumed() {
  globalRoomAllowanceConsumed.add(1)
}

/** VUs with partition allowance > 0 (for summary; sum of allowances === globalCap). */
export function countVusWithPositiveAllowance(globalCap, maxVus) {
  const vus = Math.max(1, Math.floor(maxVus))
  let count = 0
  for (let vu = 1; vu <= vus; vu++) {
    if (vuAllowanceFromGlobalPartition(globalCap, vus, vu) > 0) {
      count += 1
    }
  }
  return count
}
