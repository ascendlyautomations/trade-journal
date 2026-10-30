/**
 * k6 end-of-test summary helpers (handleSummary).
 */

import { FULL_ACTIVITY_IDS, expectedActivityWeight } from "./realistic300-full-activities.js"
import { countVusWithPositiveAllowance } from "./realistic300-full-send-budget.js"

const PAGE_LATENCY_PREFIX = "http_req_duration{"

export function findScenarioGroup(root, name) {
  function walk(node) {
    if (!node) {
      return null
    }
    if (node.name === name) {
      return node
    }
    if (node.groups) {
      for (let i = 0; i < node.groups.length; i++) {
        const found = walk(node.groups[i])
        if (found) {
          return found
        }
      }
    }
    return null
  }
  return walk(root)
}

/**
 * Distinguish k6 setup (auth + preflight) from prod_read_only scenario wall time.
 * HTTP metrics below reflect VU scenario work only, not setup().
 */
export function appendRunTimingBreakdown(lines, data, profile) {
  const state = data && data.state ? data.state : {}
  const metrics = data && data.metrics ? data.metrics : {}
  const setupVals =
    metrics.tradetraxs_setup_wall_ms && metrics.tradetraxs_setup_wall_ms.values
  const setupMs = setupVals && setupVals.max != null ? setupVals.max : setupVals && setupVals.avg
  const totalWallMs = state.testRunDuration
  const plannedScenarioSec = parsePlannedDurationSec(profile && profile.duration)

  lines.push("run timing (wall clock):")
  if (setupMs != null) {
    lines.push("  setup (JWT grants + RPC preflight): " + (setupMs / 1000).toFixed(1) + "s")
  } else {
    lines.push("  setup (JWT grants + RPC preflight): (metric unavailable)")
  }
  if (plannedScenarioSec != null) {
    lines.push(
      "  scenario prod_read_only (planned): " +
        plannedScenarioSec +
        "s constant VUs (+ up to 10s gracefulStop if not aborted early)"
    )
  }
  if (totalWallMs != null) {
    lines.push("  total k6 test run (wall): " + (totalWallMs / 1000).toFixed(1) + "s")
    if (setupMs != null) {
      const approxScenarioMs = Math.max(0, totalWallMs - setupMs)
      lines.push(
        "  approx scenario execution (wall − setup): " +
          (approxScenarioMs / 1000).toFixed(1) +
          "s (includes jitter ramp; abortOnFail may stop before planned duration)"
      )
    }
  }
  lines.push(
    "  note: http_req_* metrics below are from VU iterations only, not setup auth/preflight."
  )
  lines.push("")
}

function parsePlannedDurationSec(duration) {
  if (!duration || typeof duration !== "string") {
    return null
  }
  const m = duration.match(/^(\d+(?:\.\d+)?)s$/)
  if (!m) {
    return null
  }
  return Number(m[1])
}

export function appendHttpAggregate(lines, metrics, label) {
  if (!metrics) {
    return
  }
  const prefix = label ? label + " " : ""
  const rate = metrics.http_reqs && metrics.http_reqs.values.rate
  const fail = metrics.http_req_failed && metrics.http_req_failed.values.rate
  const dur = metrics.http_req_duration && metrics.http_req_duration.values
  const iterations = metrics.iterations && metrics.iterations.values.count
  if (rate != null) {
    lines.push(prefix + "http_reqs rate: " + rate.toFixed(2) + "/s")
  }
  if (fail != null) {
    lines.push(prefix + "http_req_failed rate: " + (fail * 100).toFixed(2) + "%")
  }
  if (dur) {
    if (dur["p(50)"] != null) {
      lines.push(prefix + "http_req_duration p50: " + dur["p(50)"].toFixed(0) + "ms")
    }
    if (dur["p(95)"] != null) {
      lines.push(prefix + "http_req_duration p95: " + dur["p(95)"].toFixed(0) + "ms")
    }
    if (dur["p(99)"] != null) {
      lines.push(prefix + "http_req_duration p99: " + dur["p(99)"].toFixed(0) + "ms")
    }
  }
  if (iterations != null) {
    lines.push(prefix + "iterations completed: " + iterations)
  }
}

/** Tagged http_req_duration metrics (page:feed, page:dashboard_rpc, …). */
export function appendEndpointLatency(lines, metricsRoot, label) {
  if (!metricsRoot) {
    return
  }
  const prefix = label ? label + " " : ""
  const keys = []
  for (const key in metricsRoot) {
    if (key.indexOf(PAGE_LATENCY_PREFIX) === 0 && key.indexOf("page:") !== -1) {
      keys.push(key)
    }
  }
  keys.sort()
  if (keys.length === 0) {
    return
  }
  lines.push(prefix + "endpoint latency (tagged http_req_duration):")
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i]
    const values = metricsRoot[key].values
    if (!values) {
      continue
    }
    const parts = [key]
    if (values["p(50)"] != null) {
      parts.push("p50=" + values["p(50)"].toFixed(0) + "ms")
    }
    if (values["p(95)"] != null) {
      parts.push("p95=" + values["p(95)"].toFixed(0) + "ms")
    }
    if (values["p(99)"] != null) {
      parts.push("p99=" + values["p(99)"].toFixed(0) + "ms")
    }
    if (values.count != null) {
      parts.push("n=" + values.count)
    }
    lines.push("  " + parts.join("  "))
  }
}

/** tradetraxs_http_outcome counter (timeout vs ok vs errors). */
export function appendHttpOutcomeCounters(lines, metricsRoot, label) {
  if (!metricsRoot) {
    return
  }
  const prefix = label ? label + " " : ""
  const keys = []
  for (const key in metricsRoot) {
    if (key.indexOf("tradetraxs_http_outcome{") === 0) {
      keys.push(key)
    }
  }
  keys.sort()
  if (keys.length === 0) {
    return
  }
  lines.push(prefix + "request outcomes (tradetraxs_http_outcome):")
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i]
    const count = metricsRoot[key].values && metricsRoot[key].values.count
    if (count != null) {
      lines.push("  " + key + "  n=" + count)
    }
  }
}

/** Subset of tagged latency for feed first page vs cursor page. */
export function appendFeedCursorLatency(lines, metricsRoot, label) {
  if (!metricsRoot) {
    return
  }
  const prefix = label ? label + " " : ""
  const keys = []
  for (const key in metricsRoot) {
    if (
      key.indexOf(PAGE_LATENCY_PREFIX) === 0 &&
      key.indexOf("feed_cursor:") !== -1
    ) {
      keys.push(key)
    }
  }
  keys.sort()
  if (keys.length === 0) {
    return
  }
  lines.push(prefix + "feed latency by cursor (http_req_duration):")
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i]
    const values = metricsRoot[key].values
    if (!values) {
      continue
    }
    const parts = [key]
    if (values["p(95)"] != null) {
      parts.push("p95=" + values["p(95)"].toFixed(0) + "ms")
    }
    if (values.count != null) {
      parts.push("n=" + values.count)
    }
    lines.push("  " + parts.join("  "))
  }
}

/** Successful request durations only (tradetraxs_ok_duration — excludes client timeouts). */
export function appendOkDurationByPage(lines, metricsRoot, label) {
  if (!metricsRoot) {
    return
  }
  const prefix = label ? label + " " : ""
  const keys = []
  for (const key in metricsRoot) {
    if (key.indexOf("tradetraxs_ok_duration{") === 0) {
      keys.push(key)
    }
  }
  keys.sort()
  if (keys.length === 0) {
    return
  }
  lines.push(prefix + "successful request latency (tradetraxs_ok_duration):")
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i]
    const values = metricsRoot[key].values
    if (!values) {
      continue
    }
    const parts = [key]
    if (values["p(95)"] != null) {
      parts.push("p95=" + values["p(95)"].toFixed(0) + "ms")
    }
    if (values.count != null) {
      parts.push("n=" + values.count)
    }
    lines.push("  " + parts.join("  "))
  }
}

function counterCount(metricsRoot, name) {
  if (!metricsRoot || !metricsRoot[name] || !metricsRoot[name].values) {
    return null
  }
  const count = metricsRoot[name].values.count
  return count != null ? count : null
}

function appendTrendLine(lines, indent, label, values) {
  if (!values || values.count == null || values.count === 0) {
    lines.push(indent + label + ": (no samples)")
    return
  }
  const parts = [label + ": n=" + values.count]
  if (values["p(50)"] != null) {
    parts.push("p50=" + values["p(50)"].toFixed(0) + "ms")
  }
  if (values["p(95)"] != null) {
    parts.push("p95=" + values["p(95)"].toFixed(0) + "ms")
  }
  if (values["p(99)"] != null) {
    parts.push("p99=" + values["p(99)"].toFixed(0) + "ms")
  }
  if (values.avg != null) {
    parts.push("avg=" + values.avg.toFixed(0) + "ms")
  }
  lines.push(indent + parts.join("  "))
}

function appendCounterLine(lines, indent, label, count) {
  lines.push(indent + label + ": " + (count != null ? count : 0))
}

/**
 * Realtime, messaging sends, and global cap counters for realistic300_full.
 */
export function appendRealistic300FullMetrics(lines, metricsRoot) {
  if (!metricsRoot) {
    lines.push("realtime/messaging metrics: (unavailable)")
    return
  }

  const wsOk = counterCount(metricsRoot, "tradetraxs_ws_connect_ok")
  const wsFail = counterCount(metricsRoot, "tradetraxs_ws_connect_fail")
  const subOk = counterCount(metricsRoot, "tradetraxs_ws_subscribe_ok")
  const subFail = counterCount(metricsRoot, "tradetraxs_ws_subscribe_fail")

  lines.push("realtime / websocket:")
  appendCounterLine(lines, "  ", "ws connect ok (socket open)", wsOk)
  appendCounterLine(lines, "  ", "ws connect fail (socket error)", wsFail)
  const attempts =
    wsOk != null || wsFail != null ? (wsOk || 0) + (wsFail || 0) : null
  if (attempts != null) {
    lines.push("  ws connect attempts (ok+fail): " + attempts)
  }
  appendCounterLine(lines, "  ", "phx_join subscribe ok", subOk)
  appendCounterLine(lines, "  ", "phx_join subscribe fail", subFail)
  lines.push(
    "  ws disconnects: (not instrumented; sessions close after sessionMs timeout)"
  )

  const k6WsSessions = counterCount(metricsRoot, "ws_sessions")
  if (k6WsSessions != null) {
    appendCounterLine(lines, "  ", "k6 ws_sessions (builtin)", k6WsSessions)
  }
  const wsDur = metricsRoot.ws_session_duration && metricsRoot.ws_session_duration.values
  if (wsDur && wsDur.count > 0) {
    appendTrendLine(lines, "  ", "k6 ws_session_duration", wsDur)
  }

  const dmAttempt = counterCount(metricsRoot, "tradetraxs_dm_send_attempt")
  const roomAttempt = counterCount(metricsRoot, "tradetraxs_room_send_attempt")
  const dmOk = counterCount(metricsRoot, "tradetraxs_dm_send_ok")
  const roomOk = counterCount(metricsRoot, "tradetraxs_room_send_ok")
  const dmBlocked = counterCount(metricsRoot, "tradetraxs_global_dm_cap_blocked")
  const roomBlocked = counterCount(metricsRoot, "tradetraxs_global_room_cap_blocked")

  lines.push("messaging sends (attempt → cap gate → HTTP ok):")
  appendCounterLine(lines, "  ", "dm send attempt (rolled thread send)", dmAttempt)
  appendCounterLine(lines, "  ", "dm blocked by cap", dmBlocked)
  appendCounterLine(lines, "  ", "dm send ok (HTTP)", dmOk)
  appendCounterLine(
    lines,
    "  ",
    "dm send fail",
    counterCount(metricsRoot, "tradetraxs_dm_send_fail")
  )
  appendCounterLine(lines, "  ", "room send attempt (rolled thread send)", roomAttempt)
  appendCounterLine(lines, "  ", "room blocked by cap", roomBlocked)
  appendCounterLine(lines, "  ", "room send ok (HTTP)", roomOk)
  appendCounterLine(
    lines,
    "  ",
    "room send fail",
    counterCount(metricsRoot, "tradetraxs_room_send_fail")
  )

  lines.push("global send caps (partitioned across VUs; race-free per-VU allowances):")

  const delOk = counterCount(metricsRoot, "tradetraxs_realtime_delivery_success")
  const delTimeout = counterCount(metricsRoot, "tradetraxs_realtime_delivery_timeout")
  const delSubFail = counterCount(metricsRoot, "tradetraxs_realtime_delivery_subscribe_fail")
  const delDenom = delOk + delTimeout + delSubFail
  lines.push("correlated realtime delivery (subscribe → send on same WS → match message id):")
  appendCounterLine(lines, "  ", "delivery success", delOk)
  appendCounterLine(lines, "  ", "delivery timeout", delTimeout)
  appendCounterLine(lines, "  ", "subscribe failed (join before send)", delSubFail)
  if (delDenom > 0) {
    lines.push(
      "  delivery success rate: " + ((100 * delOk) / delDenom).toFixed(1) + "% (" + delOk + "/" + delDenom + ")"
    )
  }
  appendTrendLine(
    lines,
    "  ",
    "correlated delivery latency ms (success only)",
    metricsRoot.tradetraxs_realtime_delivery_ms &&
      metricsRoot.tradetraxs_realtime_delivery_ms.values
  )
  appendCounterLine(
    lines,
    "  ",
    "delivery miss (legacy counter; timeout+subscribe_fail also increment)",
    counterCount(metricsRoot, "tradetraxs_realtime_delivery_miss")
  )

  lines.push("activity mix (iteration picks; expected read 85% / messaging 15%):")
  appendActivityMixLines(lines, metricsRoot, "  ")

  lines.push("messaging bootstrap latency:")
  appendTrendLine(
    lines,
    "  ",
    "tradetraxs_messaging_bootstrap_ms",
    metricsRoot.tradetraxs_messaging_bootstrap_ms &&
      metricsRoot.tradetraxs_messaging_bootstrap_ms.values
  )
  appendTrendLine(
    lines,
    "  ",
    "tradetraxs_dm_thread_bootstrap_ms",
    metricsRoot.tradetraxs_dm_thread_bootstrap_ms &&
      metricsRoot.tradetraxs_dm_thread_bootstrap_ms.values
  )
}

/** JSON-serializable snapshot for loadtest/out/realistic300-full-last-summary.json */
export function snapshotRealistic300FullMetrics(metricsRoot) {
  const names = [
    "tradetraxs_ws_connect_ok",
    "tradetraxs_ws_connect_fail",
    "tradetraxs_ws_subscribe_ok",
    "tradetraxs_ws_subscribe_fail",
    "tradetraxs_dm_send_ok",
    "tradetraxs_dm_send_fail",
    "tradetraxs_room_send_ok",
    "tradetraxs_room_send_fail",
    "tradetraxs_global_dm_cap_blocked",
    "tradetraxs_global_room_cap_blocked",
    "tradetraxs_global_dm_allowance_consumed",
    "tradetraxs_global_room_allowance_consumed",
    "tradetraxs_realtime_delivery_miss",
    "tradetraxs_realtime_delivery_success",
    "tradetraxs_realtime_delivery_timeout",
    "tradetraxs_realtime_delivery_subscribe_fail",
    "tradetraxs_realtime_delivery_ms",
    "tradetraxs_dm_send_attempt",
    "tradetraxs_room_send_attempt",
    "tradetraxs_messaging_bootstrap_ms",
    "tradetraxs_dm_thread_bootstrap_ms",
    "ws_sessions",
    "ws_session_duration",
  ]
  const out = { counters: {}, trends: {} }
  if (!metricsRoot) {
    return out
  }
  for (let i = 0; i < names.length; i++) {
    const name = names[i]
    const m = metricsRoot[name]
    if (!m || !m.values) {
      if (name.indexOf("_ms") !== -1 || name === "ws_session_duration") {
        out.trends[name] = { count: 0 }
      } else {
        out.counters[name] = 0
      }
      continue
    }
    if (m.type === "trend" || name.indexOf("_ms") !== -1 || name === "ws_session_duration") {
      out.trends[name] = { ...m.values }
    } else {
      out.counters[name] = m.values.count != null ? m.values.count : 0
    }
  }
  return out
}

function counterOrZero(metricsRoot, name) {
  if (!metricsRoot || !metricsRoot[name] || !metricsRoot[name].values) {
    return 0
  }
  const c = metricsRoot[name].values.count
  return c != null ? c : 0
}

function trendOrEmpty(metricsRoot, name) {
  if (!metricsRoot || !metricsRoot[name] || !metricsRoot[name].values) {
    return { count: 0 }
  }
  return { ...metricsRoot[name].values }
}

function appendActivityMixLines(lines, metricsRoot, indent) {
  const snap = snapshotActivityMix(metricsRoot)
  for (let i = 0; i < snap.activities.length; i++) {
    const a = snap.activities[i]
    lines.push(
      indent +
        a.id +
        ": count=" +
        a.count +
        " (" +
        a.actualPct.toFixed(1) +
        "%) expected_weight=" +
        a.expectedWeightPct +
        "%"
    )
  }
  lines.push(
    indent +
      "read_bucket: " +
      snap.readBucketPct.toFixed(1) +
      "% (expected 85%)  messaging_bucket: " +
      snap.messagingBucketPct.toFixed(1) +
      "% (expected 15%)"
  )
}

export function snapshotActivityMix(metricsRoot) {
  const activities = []
  let total = 0
  let readCount = 0
  let messagingCount = 0
  const readIds = {
    feed: true,
    dashboard: true,
    profile_trades: true,
    calendar: true,
    passive_view: true,
    idle: true,
  }
  for (let i = 0; i < FULL_ACTIVITY_IDS.length; i++) {
    const id = FULL_ACTIVITY_IDS[i]
    const count = counterOrZero(metricsRoot, "tradetraxs_activity_" + id)
    total += count
    if (readIds[id]) {
      readCount += count
    } else {
      messagingCount += count
    }
    activities.push({
      id: id,
      count: count,
      expectedWeightPct: expectedActivityWeight(id),
      actualPct: 0,
    })
  }
  for (let j = 0; j < activities.length; j++) {
    activities[j].actualPct = total > 0 ? (100 * activities[j].count) / total : 0
  }
  return {
    totalIterationsInstrumented: total,
    readBucketPct: total > 0 ? (100 * readCount) / total : 0,
    messagingBucketPct: total > 0 ? (100 * messagingCount) / total : 0,
    activities: activities,
  }
}

/**
 * Partitioned cap usage: unused = configured − consumed (successful send consumed allowance).
 * Blocked = rolled send when VU allowance exhausted (separate from unused).
 */
export function computeSendCapUtilization(metricsRoot, configured) {
  const dmTotal = configured.dmTotal
  const roomTotal = configured.roomTotal
  const maxVus = configured.maxVus
  const dmConsumed = counterOrZero(metricsRoot, "tradetraxs_global_dm_allowance_consumed")
  const roomConsumed = counterOrZero(metricsRoot, "tradetraxs_global_room_allowance_consumed")
  const dmBlocked = counterOrZero(metricsRoot, "tradetraxs_global_dm_cap_blocked")
  const roomBlocked = counterOrZero(metricsRoot, "tradetraxs_global_room_cap_blocked")
  return {
    dm: {
      configuredTotal: dmTotal,
      allowanceConsumed: dmConsumed,
      allowanceUnused: Math.max(0, dmTotal - dmConsumed),
      blockedAttempts: dmBlocked,
      vusWithAllowance: countVusWithPositiveAllowance(dmTotal, maxVus),
    },
    room: {
      configuredTotal: roomTotal,
      allowanceConsumed: roomConsumed,
      allowanceUnused: Math.max(0, roomTotal - roomConsumed),
      blockedAttempts: roomBlocked,
      vusWithAllowance: countVusWithPositiveAllowance(roomTotal, maxVus),
    },
    combined: {
      configuredTotal: dmTotal + roomTotal,
      allowanceConsumed: dmConsumed + roomConsumed,
      allowanceUnused: Math.max(0, dmTotal + roomTotal - dmConsumed - roomConsumed),
      blockedAttempts: dmBlocked + roomBlocked,
    },
  }
}

export function appendSendCapUtilizationLines(lines, utilization, indent) {
  if (!utilization) {
    return
  }
  lines.push("global send cap utilization (unused ≠ blocked):")
  appendCounterLine(
    lines,
    indent,
    "dm allowance consumed (partition slots used)",
    utilization.dm.allowanceConsumed
  )
  appendCounterLine(lines, indent, "dm allowance unused", utilization.dm.allowanceUnused)
  appendCounterLine(lines, indent, "dm blocked attempts (no allowance left)", utilization.dm.blockedAttempts)
  appendCounterLine(
    lines,
    indent,
    "dm VUs with ≥1 send allowance",
    utilization.dm.vusWithAllowance
  )
  appendCounterLine(
    lines,
    indent,
    "room allowance consumed (partition slots used)",
    utilization.room.allowanceConsumed
  )
  appendCounterLine(lines, indent, "room allowance unused", utilization.room.allowanceUnused)
  appendCounterLine(
    lines,
    indent,
    "room blocked attempts (no allowance left)",
    utilization.room.blockedAttempts
  )
  appendCounterLine(
    lines,
    indent,
    "room VUs with ≥1 send allowance",
    utilization.room.vusWithAllowance
  )
  appendCounterLine(
    lines,
    indent,
    "combined allowance unused",
    utilization.combined.allowanceUnused
  )
  appendCounterLine(
    lines,
    indent,
    "combined blocked attempts",
    utilization.combined.blockedAttempts
  )
}

/** Structured messaging / Realtime section for JSON reports (600_full and shared builder). */
export function snapshotMessagingAndRealtime(metricsRoot, capConfig) {
  const wsConnectOk = counterOrZero(metricsRoot, "tradetraxs_ws_connect_ok")
  const wsConnectFail = counterOrZero(metricsRoot, "tradetraxs_ws_connect_fail")
  const delOk = counterOrZero(metricsRoot, "tradetraxs_realtime_delivery_success")
  const delTimeout = counterOrZero(metricsRoot, "tradetraxs_realtime_delivery_timeout")
  const delSubFail = counterOrZero(metricsRoot, "tradetraxs_realtime_delivery_subscribe_fail")
  const delDenom = delOk + delTimeout + delSubFail
  return {
    sends: {
      dmAttempt: counterOrZero(metricsRoot, "tradetraxs_dm_send_attempt"),
      dmOk: counterOrZero(metricsRoot, "tradetraxs_dm_send_ok"),
      dmFail: counterOrZero(metricsRoot, "tradetraxs_dm_send_fail"),
      roomAttempt: counterOrZero(metricsRoot, "tradetraxs_room_send_attempt"),
      roomOk: counterOrZero(metricsRoot, "tradetraxs_room_send_ok"),
      roomFail: counterOrZero(metricsRoot, "tradetraxs_room_send_fail"),
    },
    capBlocked: {
      dm: counterOrZero(metricsRoot, "tradetraxs_global_dm_cap_blocked"),
      room: counterOrZero(metricsRoot, "tradetraxs_global_room_cap_blocked"),
    },
    capUtilization:
      capConfig && capConfig.maxVus
        ? computeSendCapUtilization(metricsRoot, capConfig)
        : null,
    websocket: {
      connectOk: wsConnectOk,
      connectFail: wsConnectFail,
      connectAttempts: wsConnectOk + wsConnectFail,
      subscribeOk: counterOrZero(metricsRoot, "tradetraxs_ws_subscribe_ok"),
      subscribeFail: counterOrZero(metricsRoot, "tradetraxs_ws_subscribe_fail"),
      k6WsSessions: counterOrZero(metricsRoot, "ws_sessions"),
      k6WsSessionDuration: trendOrEmpty(metricsRoot, "ws_session_duration"),
    },
    realtimeDelivery: {
      success: delOk,
      timeout: delTimeout,
      subscribeFail: delSubFail,
      successRatePct: delDenom > 0 ? (100 * delOk) / delDenom : null,
      latencyMs: trendOrEmpty(metricsRoot, "tradetraxs_realtime_delivery_ms"),
      missesLegacy: counterOrZero(metricsRoot, "tradetraxs_realtime_delivery_miss"),
    },
    activityMix: snapshotActivityMix(metricsRoot),
  }
}

export function appendThresholdResults(lines, metricsRoot, options) {
  if (!metricsRoot) {
    return
  }
  const observeOnly = options && options.observeOnly
  const crossed = []
  for (const key in metricsRoot) {
    const m = metricsRoot[key]
    if (m && m.thresholds) {
      for (const tname in m.thresholds) {
        if (m.thresholds[tname].ok === false) {
          crossed.push(key + " → " + tname)
        }
      }
    }
  }
  if (crossed.length) {
    lines.push(
      observeOnly
        ? "Thresholds crossed (informational — run did not abort on fail):"
        : "Thresholds crossed (abortOnFail):"
    )
    for (let i = 0; i < crossed.length; i++) {
      lines.push("  " + crossed[i])
    }
  } else if (observeOnly) {
    lines.push("Thresholds: none crossed (informational SLOs only)")
  }
}

/**
 * Shared end-of-test stdout + JSON for realistic300_full / realistic600_full.
 */
export function buildRealisticFullSummaryOutput(data, profile) {
  const dmCap =
    profile.configuredDmCap != null
      ? String(profile.configuredDmCap)
      : __ENV.LOADTEST_FULL_MAX_DM_SENDS_TOTAL || "200"
  const roomCap =
    profile.configuredRoomCap != null
      ? String(profile.configuredRoomCap)
      : __ENV.LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL || "200"
  const messageTag =
    (profile.messageTag && String(profile.messageTag).trim()) ||
    (__ENV.LOADTEST_FULL_MESSAGE_TAG && String(__ENV.LOADTEST_FULL_MESSAGE_TAG).trim()) ||
    "[loadtest:realistic300_full]"
  const lines = [
    profile.title,
    "mode: " +
      profile.mode +
      "  VUs: " +
      profile.maxVus +
      "  duration: " +
      profile.durationDesc,
    "sessions: up to " +
      profile.maxVus +
      " concurrent VUs on " +
      (profile.userCount || 50) +
      " authenticated accounts" +
      (profile.vuMappingDesc ? " (" + profile.vuMappingDesc + ")" : " (VU→user map)"),
    profile.maxVus +
      " concurrent virtual sessions ≠ " +
      profile.maxVus +
      " unique users",
    "fixture: " +
      (profile.fixtureEnvKey || "LOADTEST_REALISTIC300_FULL_FIXTURE_JSON") +
      " (isolated DM/room IDs only)",
    "push_notify: " +
      (__ENV.LOADTEST_FULL_SKIP_PUSH === "no"
        ? "ENABLED (avoid in prod)"
        : "disabled (LOADTEST_FULL_SKIP_PUSH=yes)"),
    "",
    "Workload: realistic150 read mix (85%) + DM/room/Realtime/notifications (15%)",
    "Writes: tagged " +
      messageTag +
      " only; global caps " +
      dmCap +
      " DM / " +
      roomCap +
      " room (partitioned across VUs, race-free)",
    "",
  ]
  if (profile.overloadNote) {
    lines.push(profile.overloadNote)
    lines.push("")
  }
  appendRunTimingBreakdown(lines, data, {
    duration: profile.plannedDuration,
    vus: profile.maxVus,
  })
  appendHttpAggregate(lines, data.metrics, "")
  appendEndpointLatency(lines, data.metrics, "")
  appendFeedCursorLatency(lines, data.metrics, "")
  appendHttpOutcomeCounters(lines, data.metrics, "")
  appendOkDurationByPage(lines, data.metrics, "")
  appendThresholdResults(lines, data.metrics, { observeOnly: profile.observeOnlyThresholds })
  lines.push("")
  const capConfig = {
    dmTotal: Number(dmCap),
    roomTotal: Number(roomCap),
    maxVus: profile.maxVus,
  }
  const capUtilization = computeSendCapUtilization(data.metrics, capConfig)
  appendRealistic300FullMetrics(lines, data.metrics)
  lines.push("")
  appendSendCapUtilizationLines(lines, capUtilization, "  ")
  lines.push("")
  lines.push(
    "note: interrupted iterations during graceful ramp-down appear in k6 progress line, not as a separate metric"
  )
  lines.push(profile.sloLine || "")
  lines.push("Cleanup: loadtest/scripts/cleanup-realistic300-full-data.mjs (after run)")
  lines.push("Audit: loadtest/docs/IOS_MESSAGING_REALTIME_AUDIT.md")
  lines.push("metrics JSON: " + profile.jsonReportPath + " (this run)")

  const snapshot = {
    mode: profile.mode,
    maxVus: profile.maxVus,
    generatedAt: new Date().toISOString(),
    wallMs: data.state && data.state.testRunDuration,
    sendCapsConfigured: {
      dmTotal: Number(dmCap),
      roomTotal: Number(roomCap),
      messageSendsTotal: Number(dmCap) + Number(roomCap),
      maxVus: profile.maxVus,
      enforcement: "global_partitioned_across_vus",
      messageTag: messageTag,
    },
    http: data.metrics && {
      http_req_failed_rate:
        data.metrics.http_req_failed && data.metrics.http_req_failed.values.rate,
      http_req_duration:
        data.metrics.http_req_duration && data.metrics.http_req_duration.values,
      iterations: data.metrics.iterations && data.metrics.iterations.values.count,
    },
    sendCapUtilization: capUtilization,
    messagingAndRealtime: snapshotMessagingAndRealtime(data.metrics, capConfig),
    activityMix: snapshotActivityMix(data.metrics),
    realistic300Full: snapshotRealistic300FullMetrics(data.metrics),
  }

  return {
    stdout: lines.join("\n") + "\n",
    [profile.jsonReportPath]: JSON.stringify(snapshot, null, 2) + "\n",
  }
}
