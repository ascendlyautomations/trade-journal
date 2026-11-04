#!/usr/bin/env node
/**
 * Guest showcase demo seed generator (v1).
 * Writes:
 *   scripts/seed-showcase-demo-v1-trades.sql
 *   scripts/seed-showcase-demo-v1-payouts.sql
 *   scripts/showcase-demo-v1-validation.sql
 *
 * Usage: node scripts/generate-showcase-demo-seed.mjs
 * Does NOT connect to Supabase.
 */

import { createHash } from "node:crypto"
import { writeFileSync } from "node:fs"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))

const SHOWCASE_USER_ID = "3daf15b8-2f5d-48c8-ac98-75bca6c878f4"
const SHOWCASE_EMAIL = "tradetraxsdemo@gmail.com"

const SEED_NAMESPACE = "showcase_demo:v1"
const GENERATOR_VERSION = "1.0.0"
const PRNG_SEED = `${SEED_NAMESPACE}:generator:2026-05-01:2026-10-31`

/** Most recent six months (deterministic window for review before apply). */
const START_DATE = "2026-05-01"
const END_DATE = "2026-10-31"

const TARGET_TRADES = 300
const TARGET_TRADES_MIN = 280
const TARGET_TRADES_MAX = 320
const TARGET_WIN_RATE_MIN = 0.54
const TARGET_WIN_RATE_MAX = 0.64
const PSYCH_COVERAGE_TARGET = 0.85
const PUBLIC_TRADES_MIN = 10
const PUBLIC_TRADES_MAX = 14

const ACCOUNT_EVAL_ID = deterministicUuid("showcase:account:eval")
const ACCOUNT_FUNDED_ID = deterministicUuid("showcase:account:funded")
const ACCOUNT_LIVE_ID = deterministicUuid("showcase:account:live")
const ACCOUNT_SIM_ID = deterministicUuid("showcase:account:sim")

const ACCOUNTS = {
  eval: {
    id: ACCOUNT_EVAL_ID,
    name: "Apex 50K Evaluation",
    category: "Prop Firm",
    mode: "Eval",
    size: "50000",
    tradeMode: "Eval",
  },
  funded: {
    id: ACCOUNT_FUNDED_ID,
    name: "Apex 50K Funded",
    category: "Prop Firm",
    mode: "Funded",
    size: "50000",
    tradeMode: "Funded",
  },
  live: {
    id: ACCOUNT_LIVE_ID,
    name: "Personal Futures",
    category: "Personal",
    mode: "Live",
    size: "25000",
    tradeMode: "Live",
  },
  sim: {
    id: ACCOUNT_SIM_ID,
    name: "Replay Simulator",
    category: "Personal",
    mode: "Sim",
    size: null,
    tradeMode: "Sim",
  },
}

const INSTRUMENTS = {
  MNQ: { pointValue: 2, feePerContract: 1.02, priceBase: 22850 },
  NQ: { pointValue: 20, feePerContract: 4.04, priceBase: 22850 },
}

const EMOTIONS = [
  "Confident",
  "Calm",
  "Focused",
  "Fearful",
  "FOMO",
  "Overconfident",
  "Hesitant",
  "Frustrated",
]

const MARKET_CONDITIONS = [
  "Trending",
  "Strong Trend",
  "Ranging",
  "Choppy",
  "Low Volume",
  "High Volume",
  "Volatile",
]

const STRATEGIES = [
  { name: "Opening Range Breakout", winBias: 0.62, rrScale: 1.05 },
  { name: "Liquidity Sweep", winBias: 0.58, rrScale: 1.15 },
  { name: "VWAP Reclaim", winBias: 0.55, rrScale: 0.95 },
  { name: "Trend Pullback", winBias: 0.6, rrScale: 1.0 },
  { name: "Support / Resistance", winBias: 0.52, rrScale: 0.88 },
  { name: "Breakout Retest", winBias: 0.57, rrScale: 1.08 },
]

const MISTAKES = [
  "Early entry",
  "Revenge trade",
  "Moved stop",
  "Chased entry",
  "Ignored plan",
  "Overtrading",
  "Exited early",
  "Oversized",
]

const TRADE_TYPES = ["Day trade", "Scalp", "Swing scalp"]
const TIMEFRAMES = ["1m", "2m", "5m", "15m"]
const CONFLUENCES = [
  "Opening drive, liquidity sweep",
  "VWAP, prior day high",
  "Prior day low, imbalance",
  null,
]

const OUT_TRADES_SQL = resolve(__dirname, "seed-showcase-demo-v1-trades.sql")
const OUT_PAYOUTS_SQL = resolve(__dirname, "seed-showcase-demo-v1-payouts.sql")
const OUT_VALIDATION_SQL = resolve(__dirname, "showcase-demo-v1-validation.sql")

function mulberry32(seed) {
  let t = seed >>> 0
  return () => {
    t += 0x6d2b79f5
    let r = Math.imul(t ^ (t >>> 15), 1 | t)
    r ^= r + Math.imul(r ^ (r >>> 7), 61 | r)
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296
  }
}

function hashSeedToInt(str) {
  const h = createHash("sha256").update(str).digest()
  return h.readUInt32BE(0)
}

function deterministicUuid(key) {
  const hash = createHash("sha256").update(`${SEED_NAMESPACE}:${key}`).digest("hex")
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-4${hash.slice(13, 16)}-8${hash.slice(17, 20)}-${hash.slice(20, 32)}`
}

function parseDate(s) {
  const [y, m, d] = s.split("-").map(Number)
  return new Date(Date.UTC(y, m - 1, d))
}

function formatDate(d) {
  return d.toISOString().slice(0, 10)
}

function addDays(d, n) {
  const x = new Date(d)
  x.setUTCDate(x.getUTCDate() + n)
  return x
}

function isWeekday(d) {
  const dow = d.getUTCDay()
  return dow >= 1 && dow <= 5
}

function periodForDate(dateStr) {
  const t = parseDate(dateStr).getTime()
  const start = parseDate(START_DATE).getTime()
  const end = parseDate(END_DATE).getTime()
  const third = (end - start) / 3
  if (t < start + third) return "early"
  if (t < start + 2 * third) return "middle"
  return "recent"
}

function pick(rng, arr) {
  return arr[Math.floor(rng() * arr.length)]
}

function pickWeighted(rng, items) {
  const total = items.reduce((s, x) => s + x.weight, 0)
  let r = rng() * total
  for (const item of items) {
    r -= item.weight
    if (r <= 0) return item.value
  }
  return items[items.length - 1].value
}

function clamp(n, lo, hi) {
  return Math.max(lo, Math.min(hi, n))
}

function round2(n) {
  return Math.round(n * 100) / 100
}

function sqlStr(s) {
  if (s == null) return "null"
  return `'${String(s).replace(/'/g, "''")}'`
}

function sqlNum(n) {
  if (n == null) return "null"
  return String(n)
}

function sqlBool(b) {
  return b ? "true" : "false"
}

function formatDuration(seconds) {
  if (seconds < 60) return `${seconds}s`
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  if (m < 60) return s ? `${m}m ${s}s` : `${m}m`
  const h = Math.floor(m / 60)
  const rm = m % 60
  return rm ? `${h}h ${rm}m` : `${h}h`
}

function easternOffsetForDate(dateStr) {
  const d = parseDate(dateStr)
  const y = d.getUTCFullYear()
  const secondSundayMarch = nthWeekdayOfMonth(y, 2, 0, 2)
  const firstSundayNov = nthWeekdayOfMonth(y, 10, 0, 1)
  const t = d.getTime()
  if (t >= secondSundayMarch.getTime() && t < firstSundayNov.getTime()) return "-04:00"
  return "-05:00"
}

function nthWeekdayOfMonth(year, monthIndex, weekday, n) {
  const d = new Date(Date.UTC(year, monthIndex, 1))
  let count = 0
  while (d.getUTCMonth() === monthIndex) {
    if (d.getUTCDay() === weekday) {
      count++
      if (count === n) return new Date(d)
    }
    d.setUTCDate(d.getUTCDate() + 1)
  }
  return new Date(Date.UTC(year, monthIndex, 28))
}

function buildTimestamp(dateStr, hour, minute) {
  const off = easternOffsetForDate(dateStr)
  const hh = String(hour).padStart(2, "0")
  const mm = String(minute).padStart(2, "0")
  return `${dateStr}T${hh}:${mm}:00${off}`
}

function sessionForHour(h) {
  if (h >= 9 && h <= 16) return "NY"
  if (h >= 3 && h <= 8) return "London"
  return "Asia"
}

function computePoints(direction, entry, exit) {
  const raw = direction === "Long" ? exit - entry : entry - exit
  return round2(raw)
}

function computePnl(ticker, contracts, points) {
  const spec = INSTRUMENTS[ticker]
  const gross = points * spec.pointValue * contracts
  const fee = spec.feePerContract * contracts
  return round2(gross - fee)
}

function pickAccount(rng) {
  return pickWeighted(rng, [
    { weight: 40, value: "eval" },
    { weight: 25, value: "funded" },
    { weight: 25, value: "live" },
    { weight: 10, value: "sim" },
  ])
}

function composePsychNote(rng, emotion, mistake) {
  const lines = [
    `Pre-trade felt ${emotion.toLowerCase()}.`,
    mistake
      ? `Primary mistake today: ${mistake.toLowerCase()}.`
      : "No major mistake tag — review execution anyway.",
    pick(rng, [
      "Will re-read plan before tomorrow's open.",
      "Need to respect max trades per day rule.",
      "Sleep and prep matter — keep morning routine.",
      "Coach note: pause after consecutive losses.",
    ]),
  ]
  return lines.join(" ")
}

function computeRrFields(points, pnl, strategyMeta, rng) {
  const absPts = Math.abs(points)
  const sign = points >= 0 ? 1 : -1
  let targetR = round2((absPts / (4 + rng() * 5)) * strategyMeta.rrScale * sign)
  if (Math.abs(targetR) < 0.35) targetR = round2(0.5 * sign)

  let maxRr
  if (pnl > 0) {
    maxRr = round2(Math.abs(targetR) * (0.85 + rng() * 0.55))
  } else if (pnl < 0) {
    maxRr = round2(Math.abs(targetR) * (0.25 + rng() * 0.45))
  } else {
    maxRr = round2(Math.abs(targetR) * 0.3)
  }

  let realizedRr = null
  if (pnl > 0 && Math.abs(targetR) > 0) {
    realizedRr = round2(Math.min(maxRr, Math.abs(targetR) * (0.75 + rng() * 0.35)) * sign)
  } else if (pnl < 0) {
    realizedRr = round2(-Math.min(Math.abs(targetR), maxRr) * (0.6 + rng() * 0.4))
  }

  return { rr: targetR, max_rr_reached: maxRr, realized_rr: realizedRr }
}

function generateTrade(rng, ctx) {
  const { dateStr, period, accountKey, seqOnDay, dayIndex, streakWinBias } = ctx
  const accountMeta = ACCOUNTS[accountKey]
  const strategyMeta = pick(rng, STRATEGIES)

  let ticker = rng() < 0.85 ? "MNQ" : "NQ"
  if (accountKey === "sim" && rng() < 0.3) ticker = "MNQ"

  const direction = rng() < 0.52 ? "Long" : "Short"
  let contracts =
    ticker === "NQ"
      ? 1
      : pickWeighted(rng, [
          { weight: 2, value: 1 },
          { weight: 3, value: 2 },
          { weight: accountKey === "sim" ? 1 : 2, value: 3 },
        ])

  const sessionRoll = rng()
  let hour
  if (sessionRoll < 0.8) hour = 9 + Math.floor(rng() * 7)
  else if (sessionRoll < 0.93) hour = 3 + Math.floor(rng() * 5)
  else hour = 18 + Math.floor(rng() * 3)
  const minute = pick(rng, [5, 12, 18, 22, 35, 42, 48, 55])
  const entryTime = buildTimestamp(dateStr, hour, minute)

  const holdMinutes = pickWeighted(rng, [
    { weight: 2, value: 4 + Math.floor(rng() * 10) },
    { weight: 3, value: 12 + Math.floor(rng() * 28) },
    { weight: 2, value: 35 + Math.floor(rng() * 35) },
    { weight: 1, value: 55 + Math.floor(rng() * 50) },
  ])
  let exitHour = hour
  let exitMinute = minute + holdMinutes
  while (exitMinute >= 60) {
    exitMinute -= 60
    exitHour++
  }
  if (exitHour >= 24) {
    exitHour = 16
    exitMinute = 30
  }
  const exitTime = buildTimestamp(formatDate(parseDate(dateStr)), exitHour, exitMinute)
  const durationSeconds = Math.max(120, holdMinutes * 60)

  const priceDrift = (dayIndex / 130) * 280 + (rng() - 0.5) * 35
  const base = INSTRUMENTS[ticker].priceBase + priceDrift
  const tick = 0.25

  const winBias = clamp(
    strategyMeta.winBias + streakWinBias + (period === "recent" ? 0.04 : period === "early" ? -0.03 : 0),
    0.42,
    0.72
  )
  const isScratch = rng() < 0.035
  const isWin = !isScratch && rng() < winBias
  const isLoss = !isScratch && !isWin

  let points
  if (isScratch) {
    points = round2((rng() < 0.5 ? 1 : -1) * (0.25 + rng() * 0.75))
  } else if (isWin) {
    points = round2(
      pickWeighted(rng, [
        { weight: 3, value: 4 + rng() * 9 },
        { weight: 2, value: 12 + rng() * 14 },
        { weight: 1, value: 22 + rng() * 16 },
      ])
    )
  } else {
    points = round2(
      -pickWeighted(rng, [
        { weight: 3, value: 4 + rng() * 8 },
        { weight: 2, value: 10 + rng() * 11 },
        { weight: 1, value: 16 + rng() * 12 },
      ])
    )
  }

  let entryPrice = round2(Math.round((base + (rng() - 0.5) * 18) / tick) * tick)
  let exitPrice =
    direction === "Long"
      ? round2(entryPrice + (points >= 0 ? Math.abs(points) : -Math.abs(points)))
      : round2(entryPrice - (points >= 0 ? Math.abs(points) : -Math.abs(points)))
  points = computePoints(direction, entryPrice, exitPrice)
  let pnl = computePnl(ticker, contracts, points)

  const hasPsych = rng() < 0.88
  let executionRating = hasPsych
    ? clamp(Math.round(2.2 + rng() * 2.5 + (period === "recent" ? 0.35 : 0)), 1, 5)
    : null
  let confidence = hasPsych ? clamp(Math.round(2 + rng() * 3), 1, 5) : null
  let emotion = hasPsych ? pick(rng, EMOTIONS) : null
  let exitEmotion = hasPsych ? pick(rng, EMOTIONS) : null
  let followedPlan = hasPsych ? rng() < (period === "early" ? 0.64 : 0.78) : null

  let mistakeType = null
  if (hasPsych && (isLoss || !followedPlan) && rng() < 0.32) {
    mistakeType = pick(rng, MISTAKES)
    if (executionRating != null && executionRating > 3 && rng() < 0.45) {
      executionRating -= 1
    }
  }

  const { rr, max_rr_reached, realized_rr } = computeRrFields(points, pnl, strategyMeta, rng)
  const psychologyNotes = hasPsych && rng() < 0.72 ? composePsychNote(rng, emotion ?? "Calm", mistakeType) : null
  const notes = `[${SEED_NAMESPACE}] ${pick(rng, [
    "Waited for confirmation at the level before sizing in.",
    "Opening range was clean; thesis was continuation after the sweep.",
    "Pullback to structure with defined invalidation.",
    "Reduced size after drawdown — good risk control.",
    "Respected the stop when structure broke down.",
  ])}`

  const fingerprint = `${SEED_NAMESPACE}:trade:${dateStr}:${String(seqOnDay).padStart(2, "0")}`
  const id = deterministicUuid(`trade:${fingerprint}`)

  return {
    id,
    accountKey,
    account_id: accountMeta.id,
    trade_date: dateStr,
    ticker,
    direction,
    contracts,
    entry_price: entryPrice,
    exit_price: exitPrice,
    entry_time: entryTime,
    exit_time: exitTime,
    points,
    pnl,
    session: sessionForHour(hour),
    duration_seconds: durationSeconds,
    duration_text: formatDuration(durationSeconds),
    strategy: strategyMeta.name,
    notes,
    timeframe: pick(rng, TIMEFRAMES),
    rr,
    max_rr_reached,
    realized_rr,
    confidence,
    emotion,
    exit_emotion: exitEmotion,
    execution_rating: executionRating,
    followed_plan: followedPlan,
    market_condition: pick(rng, MARKET_CONDITIONS),
    news_event: rng() < 0.07,
    mistake_type: mistakeType,
    trade_type: pick(rng, TRADE_TYPES),
    psychology_notes: psychologyNotes,
    top_confluences: pick(rng, CONFLUENCES),
    import_fingerprint: fingerprint,
    period,
    is_public: false,
    first_published_at: null,
    public_description: null,
    trade_mode: accountMeta.tradeMode,
    account_name: accountMeta.name,
    account_size: accountMeta.size,
    account_type: accountMeta.category,
    account_category: accountMeta.category,
    mode: accountMeta.tradeMode,
  }
}

function generateCheckIn(rng, dateStr, dayTrades, period) {
  const id = deterministicUuid(`checkin:${dateStr}`)
  const dayPnl = dayTrades.reduce((s, t) => s + t.pnl, 0)
  const rated = dayTrades.filter((t) => t.execution_rating != null)
  const avgExec = rated.length
    ? rated.reduce((s, t) => s + t.execution_rating, 0) / rated.length
    : 3

  const sleepHours = round2(6 + rng() * 2.4)
  const stress = clamp(Math.round(2.5 + rng() * 2 - (dayPnl > 0 ? 0.45 : 0)), 1, 5)
  const noteVariants = [
    `[${SEED_NAMESPACE}] Solid sleep; pre-market levels marked and plan reviewed.`,
    `[${SEED_NAMESPACE}] Short night — keeping size smaller until focus improves.`,
    `[${SEED_NAMESPACE}] Routine morning; coffee and checklist before the open.`,
    `[${SEED_NAMESPACE}] Calm start; goal is quality over quantity today.`,
  ]

  return {
    id,
    check_in_date: dateStr,
    sleep_hours: sleepHours,
    sleep_quality: clamp(Math.round(2 + rng() * 2.5), 1, 5),
    morning_rating: clamp(Math.round(2 + rng() * 2.5), 1, 5),
    stress_level: stress,
    energy_level: clamp(Math.round(2 + rng() * 2.5), 1, 5),
    focus_level: clamp(Math.round(2 + rng() * 2.5 - (avgExec < 3 ? 0.5 : 0)), 1, 5),
    notes: pick(rng, noteVariants),
  }
}

function buildDataset() {
  const rng = mulberry32(hashSeedToInt(PRNG_SEED))
  const trades = []
  const checkIns = []
  const activeDays = []
  let dayIndex = 0
  let lossStreak = 0
  let winStreak = 0

  for (let d = parseDate(START_DATE); d <= parseDate(END_DATE); d = addDays(d, 1)) {
    if (!isWeekday(d)) continue
    const dateStr = formatDate(d)
    const period = periodForDate(dateStr)
    const month = d.getUTCMonth()
    if (month === 7 && d.getUTCDate() >= 22 && d.getUTCDate() <= 24 && rng() < 0.35) continue

    let tradeProb = period === "early" ? 0.82 : period === "middle" ? 0.86 : 0.8
    if (rng() > tradeProb) continue

    activeDays.push(dateStr)
    const numTrades = 1 + Math.floor(rng() * (period === "early" ? 4.5 : 3.8))

    let streakWinBias = 0
    if (winStreak >= 4) streakWinBias = 0.06
    if (lossStreak >= 3) streakWinBias = -0.08

    const dayTrades = []
    for (let i = 0; i < numTrades; i++) {
      const t = generateTrade(rng, {
        dateStr,
        period,
        accountKey: pickAccount(rng),
        seqOnDay: i + 1,
        dayIndex,
        streakWinBias,
      })
      dayTrades.push(t)
      if (t.pnl >= 1.5) {
        winStreak++
        lossStreak = 0
      } else if (t.pnl <= -1.5) {
        lossStreak++
        winStreak = 0
      }
    }
    trades.push(...dayTrades)

    if (rng() < 0.72) {
      checkIns.push(generateCheckIn(rng, dateStr, dayTrades, period))
    }
    dayIndex++
  }

  let pad = 0
  while (trades.length < TARGET_TRADES && pad < 200) {
    pad++
    const rng2 = mulberry32(hashSeedToInt(`${PRNG_SEED}:pad:${pad}`))
    const dateStr = activeDays[Math.floor(rng2() * activeDays.length)] ?? START_DATE
    trades.push(
      generateTrade(rng2, {
        dateStr,
        period: periodForDate(dateStr),
        accountKey: pickAccount(rng2),
        seqOnDay: 20 + pad,
        dayIndex: 200 + pad,
        streakWinBias: 0,
      })
    )
  }
  while (trades.length > TARGET_TRADES_MAX) trades.pop()

  const tradingDays = [...new Set(trades.map((t) => t.trade_date))].sort()
  for (const dateStr of tradingDays) {
    if (checkIns.some((c) => c.check_in_date === dateStr)) continue
    if (checkIns.length >= Math.ceil(tradingDays.length * 0.85)) break
    const dayTrades = trades.filter((t) => t.trade_date === dateStr)
    checkIns.push(
      generateCheckIn(
        mulberry32(hashSeedToInt(`${PRNG_SEED}:ci:${dateStr}`)),
        dateStr,
        dayTrades,
        periodForDate(dateStr)
      )
    )
  }

  const sorted = [...trades].sort(
    (a, b) => a.trade_date.localeCompare(b.trade_date) || a.import_fingerprint.localeCompare(b.import_fingerprint)
  )
  const publicCount =
    PUBLIC_TRADES_MIN + Math.floor(rng() * (PUBLIC_TRADES_MAX - PUBLIC_TRADES_MIN + 1))
  const publicCandidates = sorted
    .filter((t) => t.pnl >= 12)
    .sort((a, b) => b.pnl - a.pnl || a.trade_date.localeCompare(b.trade_date))
  const feedPosts = []
  const usedDates = new Set()
  for (let i = 0; feedPosts.length < publicCount && i < publicCandidates.length; i++) {
    const t = publicCandidates[i]
    if (usedDates.has(t.trade_date) && publicCandidates.length > publicCount * 2) continue
    usedDates.add(t.trade_date)
    t.is_public = true
    t.first_published_at = t.entry_time
    t.public_description = `[${SEED_NAMESPACE}] Shared ${t.ticker} ${t.direction.toLowerCase()} — ${t.strategy}.`
    feedPosts.push({
      id: deterministicUuid(`feed-post:${t.id}`),
      trade_id: t.id,
      pnl: t.pnl,
      rr: t.rr,
      created_at: t.first_published_at,
      caption: t.public_description,
    })
  }
  if (feedPosts.length < PUBLIC_TRADES_MIN) {
    for (const t of sorted) {
      if (feedPosts.length >= PUBLIC_TRADES_MIN) break
      if (t.is_public || t.pnl < 5) continue
      t.is_public = true
      t.first_published_at = t.entry_time
      t.public_description = `[${SEED_NAMESPACE}] Shared ${t.ticker} ${t.direction.toLowerCase()} — ${t.strategy}.`
      feedPosts.push({
        id: deterministicUuid(`feed-post:${t.id}`),
        trade_id: t.id,
        pnl: t.pnl,
        rr: t.rr,
        created_at: t.first_published_at,
        caption: t.public_description,
      })
    }
  }

  const achievements = generateAchievements(trades)
  const profilePosts = generateProfilePosts()

  return { trades, checkIns, achievements, profilePosts, feedPosts }
}

function sumPnlForAccount(trades, accountId) {
  return round2(
    trades.filter((t) => t.account_id === accountId).reduce((s, t) => s + t.pnl, 0)
  )
}

function generateAchievements(trades) {
  const ach = []
  const add = (key, row) =>
    ach.push({
      ...row,
      id: deterministicUuid(`achievement:${key}`),
      metadata: { seed: SEED_NAMESPACE, key },
    })

  const junePnl = trades
    .filter((t) => t.trade_date.startsWith("2026-06"))
    .reduce((s, t) => s + t.pnl, 0)

  add("milestone:first-green-month", {
    achievement_type: "milestone",
    category: "milestones",
    title: "First Green Month",
    description: "Finished June net positive across journal trades.",
    achieved_at: "2026-07-01T14:00:00-04:00",
    value_numeric: Math.max(400, Math.round(junePnl)),
    value_text: null,
    account_id: null,
    is_public: true,
    is_featured: false,
    sort_order: 1,
  })

  add("passed_eval", {
    achievement_type: "passed_eval",
    category: "passed_evals",
    title: "Passed Evaluation",
    description: "Met evaluation objectives on the Apex 50K evaluation account.",
    achieved_at: "2026-07-18T11:00:00-04:00",
    value_numeric: null,
    value_text: "50K Eval",
    account_id: ACCOUNT_EVAL_ID,
    is_public: true,
    is_featured: true,
    sort_order: 2,
  })

  add("milestone:discipline", {
    achievement_type: "milestone",
    category: "milestones",
    title: "Discipline Streak",
    description: "Twelve sessions at or above 4/5 execution rating.",
    achieved_at: "2026-09-05T09:00:00-04:00",
    value_numeric: 12,
    value_text: "sessions",
    account_id: null,
    is_public: false,
    is_featured: false,
    sort_order: 3,
  })

  return ach
}

function generateProfilePosts() {
  return [
    {
      id: deterministicUuid("profile-post:1"),
      content: `[${SEED_NAMESPACE}] Guest showcase — journaling check-ins changed how I prep for the NY open.`,
      created_at: "2026-06-12T18:00:00-04:00",
    },
    {
      id: deterministicUuid("profile-post:2"),
      content: `[${SEED_NAMESPACE}] Passed eval and moved to funded — fewer trades, clearer plans.`,
      created_at: "2026-07-19T12:00:00-04:00",
    },
  ]
}

function generatePayoutPlan(trades) {
  const fundedPnl = sumPnlForAccount(trades, ACCOUNT_FUNDED_ID)
  const livePnl = sumPnlForAccount(trades, ACCOUNT_LIVE_ID)
  const startBalance = 50000

  const cycles = [
    {
      id: deterministicUuid("payout-cycle:1"),
      account_id: ACCOUNT_FUNDED_ID,
      payout_amount: 950,
      payout_date: "2026-08-08",
      balance_before: round2(startBalance + fundedPnl * 0.35),
      balance_after: round2(startBalance + fundedPnl * 0.35 - 950),
      cycle_number: 1,
    },
    {
      id: deterministicUuid("payout-cycle:2"),
      account_id: ACCOUNT_FUNDED_ID,
      payout_amount: 1200,
      payout_date: "2026-09-12",
      balance_before: round2(startBalance + fundedPnl * 0.62),
      balance_after: round2(startBalance + fundedPnl * 0.62 - 1200),
      cycle_number: 2,
    },
    {
      id: deterministicUuid("payout-cycle:3"),
      account_id: ACCOUNT_FUNDED_ID,
      payout_amount: 1350,
      payout_date: "2026-10-17",
      balance_before: round2(startBalance + fundedPnl * 0.88),
      balance_after: round2(startBalance + fundedPnl * 0.88 - 1350),
      cycle_number: 3,
    },
  ]

  const liveEntries = [
    {
      id: deterministicUuid("payout-entry:1"),
      account_id: ACCOUNT_LIVE_ID,
      amount: 480,
      payout_date: "2026-08-22",
      note: `[${SEED_NAMESPACE}:payouts] Live MNQ profits — partial withdraw.`,
    },
    {
      id: deterministicUuid("payout-entry:2"),
      account_id: ACCOUNT_LIVE_ID,
      amount: 620,
      payout_date: "2026-10-03",
      note: `[${SEED_NAMESPACE}:payouts] Live account withdrawal after green month.`,
    },
  ]

  const payoutAchievements = [
    {
      id: deterministicUuid("achievement:prop-payout-950"),
      achievement_type: "prop_firm_payout",
      category: "prop_firm_payouts",
      title: "Prop Firm Payout",
      description: "Funded account payout after meeting firm rules.",
      achieved_at: "2026-08-08T16:00:00-04:00",
      value_numeric: 950,
      account_id: ACCOUNT_FUNDED_ID,
      is_public: true,
      is_featured: true,
      sort_order: 10,
      metadata: { seed: SEED_NAMESPACE, key: "prop_payout_950", cycle_id: cycles[0].id },
    },
    {
      id: deterministicUuid("achievement:prop-payout-1200"),
      achievement_type: "prop_firm_payout",
      category: "prop_firm_payouts",
      title: "Prop Firm Payout",
      description: "Second funded payout — consistency rule met.",
      achieved_at: "2026-09-12T16:00:00-04:00",
      value_numeric: 1200,
      account_id: ACCOUNT_FUNDED_ID,
      is_public: true,
      is_featured: false,
      sort_order: 11,
      metadata: { seed: SEED_NAMESPACE, key: "prop_payout_1200", cycle_id: cycles[1].id },
    },
    {
      id: deterministicUuid("achievement:prop-payout-1350"),
      achievement_type: "prop_firm_payout",
      category: "prop_firm_payouts",
      title: "Prop Firm Payout",
      description: "Third funded payout of the showcase period.",
      achieved_at: "2026-10-17T16:00:00-04:00",
      value_numeric: 1350,
      account_id: ACCOUNT_FUNDED_ID,
      is_public: true,
      is_featured: false,
      sort_order: 12,
      metadata: { seed: SEED_NAMESPACE, key: "prop_payout_1350", cycle_id: cycles[2].id },
    },
    {
      id: deterministicUuid("achievement:live-payout-480"),
      achievement_type: "live_trading_payout",
      category: "live_trading_payouts",
      title: "Live Trading Payout",
      description: "Withdrew live account profits to bank.",
      achieved_at: "2026-08-22T12:00:00-04:00",
      value_numeric: 480,
      account_id: ACCOUNT_LIVE_ID,
      is_public: false,
      is_featured: false,
      sort_order: 13,
      metadata: { seed: SEED_NAMESPACE, key: "live_payout_480", ledger_id: liveEntries[0].id },
    },
    {
      id: deterministicUuid("achievement:live-payout-620"),
      achievement_type: "live_trading_payout",
      category: "live_trading_payouts",
      title: "Live Trading Payout",
      description: "Second live withdrawal of the showcase period.",
      achieved_at: "2026-10-03T12:00:00-04:00",
      value_numeric: 620,
      account_id: ACCOUNT_LIVE_ID,
      is_public: false,
      is_featured: false,
      sort_order: 14,
      metadata: { seed: SEED_NAMESPACE, key: "live_payout_620", ledger_id: liveEntries[1].id },
    },
  ]

  return { cycles, liveEntries, payoutAchievements, fundedPnl, livePnl }
}

function computeStats(trades, checkIns) {
  const wins = trades.filter((t) => t.pnl >= 1.5).length
  const losses = trades.filter((t) => t.pnl <= -1.5).length
  const totalPnl = round2(trades.reduce((s, t) => s + t.pnl, 0))
  const winRate = wins / Math.max(1, wins + losses)
  const psychFull = trades.filter(
    (t) =>
      t.emotion &&
      t.confidence != null &&
      t.execution_rating != null &&
      t.followed_plan != null
  ).length

  let running = 0
  let peak = 0
  let maxDd = 0
  const chronological = [...trades].sort((a, b) => a.entry_time.localeCompare(b.entry_time))
  for (const t of chronological) {
    running = round2(running + t.pnl)
    if (running > peak) peak = running
    maxDd = Math.max(maxDd, peak - running)
  }

  const rrPaired = trades.filter(
    (t) => t.rr != null && t.max_rr_reached != null && Math.abs(Number(t.rr)) > 0
  ).length

  return {
    tradeCount: trades.length,
    checkInCount: checkIns.length,
    winRate,
    totalPnl,
    maxDrawdown: round2(maxDd),
    psychCoverage: psychFull / trades.length,
    rrPairedCoverage: rrPaired / trades.length,
    publicTrades: trades.filter((t) => t.is_public).length,
    feedPosts: trades.filter((t) => t.is_public).length,
    firstDate: [...new Set(trades.map((t) => t.trade_date))].sort()[0],
    lastDate: [...new Set(trades.map((t) => t.trade_date))].sort().pop(),
  }
}

function validateDataset(trades, checkIns, stats) {
  const errors = []
  if (stats.tradeCount < TARGET_TRADES_MIN || stats.tradeCount > TARGET_TRADES_MAX) {
    errors.push(`Trade count ${stats.tradeCount} outside ${TARGET_TRADES_MIN}-${TARGET_TRADES_MAX}`)
  }
  if (stats.winRate < TARGET_WIN_RATE_MIN || stats.winRate > TARGET_WIN_RATE_MAX) {
    errors.push(`Win rate ${(stats.winRate * 100).toFixed(1)}% out of band`)
  }
  if (stats.psychCoverage < PSYCH_COVERAGE_TARGET - 0.04) {
    errors.push(`Psychology coverage ${(stats.psychCoverage * 100).toFixed(1)}% too low`)
  }
  if (stats.publicTrades < PUBLIC_TRADES_MIN) {
    errors.push(`Public trades ${stats.publicTrades} below minimum ${PUBLIC_TRADES_MIN}`)
  }
  if (stats.maxDrawdown < 200) errors.push(`Max drawdown ${stats.maxDrawdown} too small`)
  if (stats.totalPnl <= 0) errors.push("Total P&L must be positive")

  const fps = new Set()
  for (const t of trades) {
    if (fps.has(t.import_fingerprint)) errors.push(`Duplicate fingerprint ${t.import_fingerprint}`)
    fps.add(t.import_fingerprint)
    if (t.trade_date < START_DATE || t.trade_date > END_DATE) {
      errors.push(`Date out of range ${t.trade_date}`)
    }
    const vp = computePoints(t.direction, t.entry_price, t.exit_price)
    if (Math.abs(vp - t.points) > 0.03) errors.push(`Points mismatch ${t.import_fingerprint}`)
    const pnl = computePnl(t.ticker, t.contracts, t.points)
    if (Math.abs(pnl - t.pnl) > 0.03) errors.push(`PnL mismatch ${t.import_fingerprint}`)
    if (t.emotion && !EMOTIONS.includes(t.emotion)) errors.push(`Bad emotion ${t.id}`)
  }

  if (errors.length) throw new Error(`Validation failed:\n- ${errors.join("\n- ")}`)
}

function chunk(arr, size) {
  const out = []
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size))
  return out
}

function tradeTempRowSql(t) {
  return `(${sqlStr(t.id)}::uuid, ${sqlStr(t.account_id)}::uuid, ${sqlStr(t.trade_date)}::date, ${sqlStr(t.ticker)}, ${sqlStr(t.direction)}, ${sqlNum(t.contracts)}, ${sqlNum(t.entry_price)}, ${sqlNum(t.exit_price)}, ${sqlNum(t.points)}, ${sqlNum(t.pnl)}, ${sqlStr(t.entry_time)}::timestamptz, ${sqlStr(t.exit_time)}::timestamptz, ${sqlStr(t.session)}, ${sqlNum(t.duration_seconds)}, ${sqlStr(t.duration_text)}, ${sqlStr(t.strategy)}, ${sqlStr(t.notes)}, ${sqlStr(t.timeframe)}, ${sqlNum(t.rr)}, ${sqlNum(t.max_rr_reached)}, ${sqlNum(t.realized_rr)}, ${t.confidence != null ? sqlNum(t.confidence) : "null"}, ${t.emotion ? sqlStr(t.emotion) : "null"}, ${t.exit_emotion ? sqlStr(t.exit_emotion) : "null"}, ${t.execution_rating != null ? sqlNum(t.execution_rating) : "null"}, ${t.followed_plan == null ? "null" : sqlBool(t.followed_plan)}, ${sqlStr(t.market_condition)}, ${sqlBool(t.news_event)}, ${t.mistake_type ? sqlStr(t.mistake_type) : "null"}, ${sqlStr(t.trade_type)}, ${t.psychology_notes ? sqlStr(t.psychology_notes) : "null"}, ${t.top_confluences ? sqlStr(t.top_confluences) : "null"}, ${sqlStr(t.import_fingerprint)}, ${sqlBool(Boolean(t.is_public))}, ${t.first_published_at ? sqlStr(t.first_published_at) + "::timestamptz" : "null"}, ${t.public_description ? sqlStr(t.public_description) : "null"})`
}

function emitTradesSql(dataset, stats) {
  const { trades, checkIns, achievements, profilePosts, feedPosts } = dataset
  const tradeInserts = chunk(trades, 20)
    .map(
      (rows) =>
        `INSERT INTO _showcase_demo_v1_trades VALUES\n${rows.map(tradeTempRowSql).join(",\n")};`
    )
    .join("\n\n")

  const checkinSql = checkIns
    .map(
      (c) =>
        `(${sqlStr(c.id)}::uuid, ${sqlStr(c.check_in_date)}::date, ${sqlNum(c.sleep_hours)}, ${sqlNum(c.sleep_quality)}, ${sqlNum(c.morning_rating)}, ${sqlNum(c.stress_level)}, ${sqlNum(c.energy_level)}, ${sqlNum(c.focus_level)}, ${sqlStr(c.notes)})`
    )
    .join(",\n")

  const achSql = achievements
    .map(
      (a) =>
        `(${sqlStr(a.id)}::uuid, ${sqlStr(a.achievement_type)}, ${sqlStr(a.category)}, ${sqlStr(a.title)}, ${sqlStr(a.description)}, ${sqlStr(a.achieved_at)}::timestamptz, ${a.value_numeric != null ? sqlNum(a.value_numeric) : "null"}, ${a.value_text ? sqlStr(a.value_text) : "null"}, ${a.account_id ? sqlStr(a.account_id) + "::uuid" : "null"}, ${sqlBool(a.is_public)}, ${sqlBool(a.is_featured)}, ${sqlNum(a.sort_order)}, ${sqlStr(JSON.stringify(a.metadata))}::jsonb)`
    )
    .join(",\n")

  const profilePostSql = profilePosts
    .map(
      (p) =>
        `(${sqlStr(p.id)}::uuid, ${sqlStr(p.content)}, ${sqlStr(p.created_at)}::timestamptz)`
    )
    .join(",\n")

  const feedPostSql = feedPosts
    .map(
      (p) =>
        `(${sqlStr(p.id)}::uuid, ${sqlStr(p.trade_id)}::uuid, ${sqlNum(p.pnl)}, ${sqlNum(p.rr)}, ${sqlStr(p.caption)}, ${sqlStr(p.created_at)}::timestamptz)`
    )
    .join(",\n")

  return `-- =============================================================================
-- TradeTraxs Guest Showcase demo seed — TRADES (GENERATED)
-- Generator: scripts/generate-showcase-demo-seed.mjs v${GENERATOR_VERSION}
-- Namespace: ${SEED_NAMESPACE}
-- Target user: ${SHOWCASE_USER_ID} (${SHOWCASE_EMAIL})
-- Window: ${START_DATE} .. ${END_DATE}
-- Pre-apply stats: trades=${stats.tradeCount}, check-ins=${stats.checkInCount}, win%=${(stats.winRate * 100).toFixed(1)}, pnl=${stats.totalPnl}, maxDD=${stats.maxDrawdown}, psych=${(stats.psychCoverage * 100).toFixed(1)}%, rrPaired=${(stats.rrPairedCoverage * 100).toFixed(1)}%
--
-- MANUAL RUN ONLY (Supabase SQL editor, postgres). Review then apply.
-- Run payouts file AFTER this: seed-showcase-demo-v1-payouts.sql
-- Then run: showcase-demo-v1-validation.sql (read-only)
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _showcase_demo_v1_trades (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  trade_date date NOT NULL,
  ticker text,
  direction text,
  contracts int,
  entry_price numeric,
  exit_price numeric,
  points numeric,
  pnl numeric,
  entry_time timestamptz,
  exit_time timestamptz,
  session text,
  duration_seconds int,
  duration_text text,
  strategy text,
  notes text,
  timeframe text,
  rr numeric,
  max_rr_reached numeric,
  realized_rr numeric,
  confidence int,
  emotion text,
  exit_emotion text,
  execution_rating int,
  followed_plan boolean,
  market_condition text,
  news_event boolean,
  mistake_type text,
  trade_type text,
  psychology_notes text,
  top_confluences text,
  import_fingerprint text NOT NULL,
  is_public boolean NOT NULL DEFAULT false,
  first_published_at timestamptz,
  public_description text
) ON COMMIT DROP;

CREATE TEMP TABLE _showcase_demo_v1_checkins (
  id uuid PRIMARY KEY,
  check_in_date date NOT NULL,
  sleep_hours numeric,
  sleep_quality int,
  morning_rating int,
  stress_level int,
  energy_level int,
  focus_level int,
  notes text
) ON COMMIT DROP;

CREATE TEMP TABLE _showcase_demo_v1_achievements (
  id uuid PRIMARY KEY,
  achievement_type text NOT NULL,
  category text NOT NULL,
  title text NOT NULL,
  description text,
  achieved_at timestamptz NOT NULL,
  value_numeric numeric,
  value_text text,
  account_id uuid,
  is_public boolean,
  is_featured boolean,
  sort_order int,
  metadata jsonb NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE _showcase_demo_v1_profile_posts (
  id uuid PRIMARY KEY,
  content text NOT NULL,
  created_at timestamptz NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE _showcase_demo_v1_feed_posts (
  id uuid PRIMARY KEY,
  trade_id uuid NOT NULL,
  pnl numeric,
  rr numeric,
  caption text,
  created_at timestamptz NOT NULL
) ON COMMIT DROP;

${tradeInserts}

INSERT INTO _showcase_demo_v1_checkins VALUES
${checkinSql};

INSERT INTO _showcase_demo_v1_achievements VALUES
${achSql};

INSERT INTO _showcase_demo_v1_profile_posts VALUES
${profilePostSql};

INSERT INTO _showcase_demo_v1_feed_posts VALUES
${feedPostSql};

DO $$
DECLARE
  target_user_id uuid := '${SHOWCASE_USER_ID}'::uuid;
  expected_email text := '${SHOWCASE_EMAIL}';
  auth_email text;
  v_eval uuid := '${ACCOUNT_EVAL_ID}'::uuid;
  v_funded uuid := '${ACCOUNT_FUNDED_ID}'::uuid;
  v_live uuid := '${ACCOUNT_LIVE_ID}'::uuid;
  v_sim uuid := '${ACCOUNT_SIM_ID}'::uuid;
BEGIN
  SELECT u.email INTO auth_email FROM auth.users u WHERE u.id = target_user_id;
  IF auth_email IS NULL THEN
    RAISE EXCEPTION 'auth.users has no row for showcase user %', target_user_id;
  END IF;
  IF lower(trim(auth_email)) <> lower(trim(expected_email)) THEN
    RAISE EXCEPTION 'Email mismatch. Expected % got %', expected_email, auth_email;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = target_user_id) THEN
    RAISE EXCEPTION 'profiles.id missing for showcase user';
  END IF;

  INSERT INTO public.accounts (
    id, user_id, name, category, mode, account_size, can_add_trades, is_active,
    show_in_account_dropdowns, profit_target, max_drawdown, daily_drawdown,
    drawdown_type, winning_day_threshold, payout_drawdown_behavior, note
  ) VALUES
  (v_eval, target_user_id, 'Apex 50K Evaluation', 'Prop Firm', 'Eval', '50000', true, true,
    true, 3000, 2500, 1200, 'end_of_day_trailing', 150,
    null, '[${SEED_NAMESPACE}] Showcase evaluation account'),
  (v_funded, target_user_id, 'Apex 50K Funded', 'Prop Firm', 'Funded', '50000', true, true,
    true, null, 2500, 1200, 'end_of_day_trailing', 150,
    'balance_based', '[${SEED_NAMESPACE}] Showcase funded account'),
  (v_live, target_user_id, 'Personal Futures', 'Personal', 'Live', '25000', true, true,
    true, null, null, null, null, null,
    null, '[${SEED_NAMESPACE}] Showcase live account'),
  (v_sim, target_user_id, 'Replay Simulator', 'Personal', 'Sim', null, true, true,
    true, null, null, null, null, null,
    null, '[${SEED_NAMESPACE}] Showcase simulation account')
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    note = EXCLUDED.note
  WHERE public.accounts.user_id = target_user_id AND public.accounts.id = EXCLUDED.id;

  INSERT INTO public.trades (
    id, user_id, account_id, account_name, account_size, account_type, account_category,
    mode, trade_mode, ticker, direction, contracts, entry_price, exit_price,
    entry_time, exit_time, trade_date, date, pnl, rr, max_rr_reached, realized_rr, points,
    session, strategy, notes, timeframe, news_event, confidence, emotion, followed_plan,
    market_condition, psychology_notes, exit_emotion, execution_rating,
    duration_seconds, duration_text, is_public, public_description, first_published_at,
    image_display_mode, reviewed, is_initial_import, import_source, import_fingerprint, created_at,
    mistake_type, trade_type, top_confluences
  )
  SELECT
    s.id, target_user_id, s.account_id, a.name, a.account_size, a.category, a.category,
    a.mode, a.mode, s.ticker, s.direction, s.contracts, s.entry_price, s.exit_price,
    s.entry_time, s.exit_time, s.trade_date, s.trade_date, s.pnl, s.rr, s.max_rr_reached, s.realized_rr, s.points,
    s.session, s.strategy, s.notes, s.timeframe, s.news_event, s.confidence, s.emotion, s.followed_plan,
    s.market_condition, s.psychology_notes, s.exit_emotion, s.execution_rating,
    s.duration_seconds, s.duration_text, s.is_public, coalesce(s.public_description, ''), s.first_published_at,
    'fit', true, false, 'manual', s.import_fingerprint, s.entry_time,
    s.mistake_type, s.trade_type, s.top_confluences
  FROM _showcase_demo_v1_trades s
  JOIN (
    VALUES
      (v_eval, 'Apex 50K Evaluation', '50000', 'Prop Firm', 'Eval'),
      (v_funded, 'Apex 50K Funded', '50000', 'Prop Firm', 'Funded'),
      (v_live, 'Personal Futures', '25000', 'Personal', 'Live'),
      (v_sim, 'Replay Simulator', null, 'Personal', 'Sim')
  ) AS a(id, name, account_size, category, mode) ON a.id = s.account_id
  WHERE NOT EXISTS (
    SELECT 1 FROM public.trades t
    WHERE t.user_id = target_user_id AND t.import_fingerprint = s.import_fingerprint
  );

  INSERT INTO public.trader_daily_check_ins (
    id, user_id, check_in_date, sleep_hours, sleep_quality, morning_rating,
    stress_level, energy_level, focus_level, notes
  )
  SELECT c.id, target_user_id, c.check_in_date, c.sleep_hours, c.sleep_quality, c.morning_rating,
    c.stress_level, c.energy_level, c.focus_level, c.notes
  FROM _showcase_demo_v1_checkins c
  WHERE NOT EXISTS (
    SELECT 1 FROM public.trader_daily_check_ins x
    WHERE x.user_id = target_user_id AND x.check_in_date = c.check_in_date
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.trader_daily_check_ins x
    WHERE x.user_id = target_user_id AND x.check_in_date = c.check_in_date
      AND coalesce(x.notes, '') NOT LIKE '[${SEED_NAMESPACE}]%'
  );

  INSERT INTO public.achievements (
    id, user_id, achievement_type, category, title, description, achieved_at,
    value_numeric, value_text, account_id, is_public, is_featured, sort_order, metadata
  )
  SELECT a.id, target_user_id, a.achievement_type, a.category, a.title, a.description, a.achieved_at,
    a.value_numeric, a.value_text, a.account_id, a.is_public, a.is_featured, a.sort_order, a.metadata
  FROM _showcase_demo_v1_achievements a
  WHERE NOT EXISTS (
    SELECT 1 FROM public.achievements x WHERE x.id = a.id AND x.user_id = target_user_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.achievements x
    WHERE x.user_id = target_user_id AND x.metadata->>'seed' = '${SEED_NAMESPACE}'
      AND x.metadata->>'key' = a.metadata->>'key'
  );

  INSERT INTO public.profile_posts (id, user_id, content, created_at, image_url)
  SELECT p.id, target_user_id, p.content, p.created_at, null
  FROM _showcase_demo_v1_profile_posts p
  WHERE NOT EXISTS (SELECT 1 FROM public.profile_posts x WHERE x.id = p.id);

  INSERT INTO public.posts (id, user_id, trade_id, pnl, rr, caption, created_at, image_url)
  SELECT f.id, target_user_id, f.trade_id, f.pnl, f.rr, f.caption, f.created_at, null
  FROM _showcase_demo_v1_feed_posts f
  WHERE EXISTS (
    SELECT 1 FROM public.trades t
    WHERE t.id = f.trade_id AND t.user_id = target_user_id
  )
  AND NOT EXISTS (SELECT 1 FROM public.posts x WHERE x.id = f.id);

  IF (SELECT count(*) FROM public.trades t WHERE t.user_id = target_user_id AND t.import_fingerprint LIKE '${SEED_NAMESPACE}:%') < ${TARGET_TRADES_MIN} THEN
    RAISE EXCEPTION 'Showcase demo trade count below minimum after apply (includes prior runs).';
  END IF;
END $$;

COMMIT;

-- ROLLBACK (separate txn): delete only ${SEED_NAMESPACE} rows — see showcase-demo-v1-validation.sql footer.
`
}

function emitPayoutsSql(payoutPlan) {
  const { cycles, liveEntries, payoutAchievements } = payoutPlan
  const cycleRows = cycles
    .map(
      (c) =>
        `(${sqlStr(c.id)}::uuid, ${sqlStr(c.account_id)}::uuid, ${sqlNum(c.payout_amount)}, ${sqlStr(c.payout_date)}::date, ${sqlNum(c.balance_before)}, ${sqlNum(c.balance_after)}, ${sqlNum(c.cycle_number)}, ${sqlStr(`[${SEED_NAMESPACE}:payouts] Funded payout cycle ${c.cycle_number}.`)})`
    )
    .join(",\n")

  const entryRows = liveEntries
    .map(
      (e) =>
        `(${sqlStr(e.id)}::uuid, ${sqlStr(e.account_id)}::uuid, ${sqlNum(e.amount)}, ${sqlStr(e.payout_date)}::date, ${sqlStr(e.note)})`
    )
    .join(",\n")

  const achRows = payoutAchievements
    .map(
      (a) =>
        `(${sqlStr(a.id)}::uuid, ${sqlStr(a.achievement_type)}, ${sqlStr(a.category)}, ${sqlStr(a.title)}, ${sqlStr(a.description)}, ${sqlStr(a.achieved_at)}::timestamptz, ${sqlNum(a.value_numeric)}, ${a.account_id ? sqlStr(a.account_id) + "::uuid" : "null"}, ${sqlBool(a.is_public)}, ${sqlBool(a.is_featured)}, ${sqlNum(a.sort_order)}, ${sqlStr(JSON.stringify(a.metadata))}::jsonb)`
    )
    .join(",\n")

  return `-- =============================================================================
-- TradeTraxs Guest Showcase demo seed — PAYOUTS (GENERATED)
-- Namespace: ${SEED_NAMESPACE}
-- Target: ${SHOWCASE_USER_ID} (${SHOWCASE_EMAIL})
-- Run AFTER seed-showcase-demo-v1-trades.sql
-- Funded: 3 completed account_payout_cycles (not ledger entries)
-- Live: 2 account_payout_entries + matching live_trading_payout achievements
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _showcase_demo_v1_cycles (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  payout_amount numeric NOT NULL,
  payout_date date NOT NULL,
  balance_before numeric NOT NULL,
  balance_after numeric NOT NULL,
  cycle_number int NOT NULL,
  note text NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE _showcase_demo_v1_ledger (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  amount numeric NOT NULL,
  payout_date date NOT NULL,
  note text NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE _showcase_demo_v1_payout_ach (
  id uuid PRIMARY KEY,
  achievement_type text NOT NULL,
  category text NOT NULL,
  title text NOT NULL,
  description text,
  achieved_at timestamptz NOT NULL,
  value_numeric numeric,
  account_id uuid,
  is_public boolean NOT NULL,
  is_featured boolean NOT NULL,
  sort_order int NOT NULL,
  metadata jsonb NOT NULL
) ON COMMIT DROP;

INSERT INTO _showcase_demo_v1_cycles VALUES
${cycleRows};

INSERT INTO _showcase_demo_v1_ledger VALUES
${entryRows};

INSERT INTO _showcase_demo_v1_payout_ach VALUES
${achRows};

DO $$
DECLARE
  target_user_id uuid := '${SHOWCASE_USER_ID}'::uuid;
  expected_email text := '${SHOWCASE_EMAIL}';
  auth_email text;
  v_funded uuid := '${ACCOUNT_FUNDED_ID}'::uuid;
  v_live uuid := '${ACCOUNT_LIVE_ID}'::uuid;
BEGIN
  SELECT u.email INTO auth_email FROM auth.users u WHERE u.id = target_user_id;
  IF lower(trim(auth_email)) <> lower(trim(expected_email)) THEN
    RAISE EXCEPTION 'Email mismatch for showcase payouts seed.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = v_funded AND a.user_id = target_user_id) THEN
    RAISE EXCEPTION 'Funded showcase account missing — run trades seed first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = v_live AND a.user_id = target_user_id) THEN
    RAISE EXCEPTION 'Live showcase account missing — run trades seed first.';
  END IF;

  INSERT INTO public.account_payout_cycles (
    id, user_id, account_id, started_at, ended_at, cycle_start_balance,
    payout_amount, balance_before_payout, balance_after_payout,
    drawdown_behavior, cycle_number, note
  )
  SELECT
    c.id, target_user_id, c.account_id,
    (c.payout_date::text || 'T09:00:00-04:00')::timestamptz,
    (c.payout_date::text || 'T16:30:00-04:00')::timestamptz,
    c.balance_before,
    c.payout_amount, c.balance_before, c.balance_after,
    'balance_based', c.cycle_number, c.note
  FROM _showcase_demo_v1_cycles c
  WHERE NOT EXISTS (SELECT 1 FROM public.account_payout_cycles x WHERE x.id = c.id);

  INSERT INTO public.account_payout_entries (id, account_id, user_id, amount, payout_date, note)
  SELECT e.id, e.account_id, target_user_id, e.amount, e.payout_date, e.note
  FROM _showcase_demo_v1_ledger e
  WHERE NOT EXISTS (SELECT 1 FROM public.account_payout_entries x WHERE x.id = e.id);

  INSERT INTO public.achievements (
    id, user_id, achievement_type, category, title, description, achieved_at,
    value_numeric, value_text, account_id, is_public, is_featured, sort_order, metadata
  )
  SELECT
    a.id, target_user_id, a.achievement_type, a.category, a.title, a.description, a.achieved_at,
    a.value_numeric, null, a.account_id, a.is_public, a.is_featured, a.sort_order, a.metadata
  FROM _showcase_demo_v1_payout_ach a
  WHERE NOT EXISTS (SELECT 1 FROM public.achievements x WHERE x.id = a.id);

END $$;

COMMIT;
`
}

function emitValidationSql(stats, payoutPlan) {
  return `-- =============================================================================
-- Showcase demo v1 — VALIDATION & ROLLBACK QUERIES (read-only section)
-- Target: ${SHOWCASE_USER_ID} (${SHOWCASE_EMAIL})
-- Namespace: ${SEED_NAMESPACE}
-- Generator pre-apply stats: ${JSON.stringify(stats, null, 2)}
-- Payout plan funded PnL=${payoutPlan.fundedPnl} live PnL=${payoutPlan.livePnl}
-- Deterministic accounts:
--   eval:   ${ACCOUNT_EVAL_ID}
--   funded: ${ACCOUNT_FUNDED_ID}
--   live:   ${ACCOUNT_LIVE_ID}
--   sim:    ${ACCOUNT_SIM_ID}
-- =============================================================================

-- 1) Identity guard (must return 1 row, email tradetraxsdemo@gmail.com)
SELECT id, email FROM auth.users WHERE id = '${SHOWCASE_USER_ID}'::uuid;

-- 2) Trade counts & date window (demo rows only)
SELECT
  count(*) AS demo_trades,
  min(trade_date) AS min_date,
  max(trade_date) AS max_date,
  round(sum(pnl)::numeric, 2) AS demo_pnl
FROM public.trades
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid
  AND import_fingerprint LIKE '${SEED_NAMESPACE}:%';

-- 3) Non-demo trades preserved (compare before/after apply)
SELECT count(*) AS non_demo_trades
FROM public.trades
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid
  AND (import_fingerprint IS NULL OR import_fingerprint NOT LIKE '${SEED_NAMESPACE}:%');

-- 4) R:R coverage
SELECT
  count(*) FILTER (WHERE rr IS NOT NULL AND max_rr_reached IS NOT NULL) AS rr_paired,
  count(*) FILTER (WHERE realized_rr IS NOT NULL) AS with_realized_rr,
  count(*) AS total_demo
FROM public.trades
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid
  AND import_fingerprint LIKE '${SEED_NAMESPACE}:%';

-- 5) Psychology coverage
SELECT
  round(100.0 * count(*) FILTER (
    WHERE emotion IS NOT NULL AND confidence IS NOT NULL AND execution_rating IS NOT NULL
  ) / nullif(count(*), 0), 1) AS psych_pct
FROM public.trades
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid
  AND import_fingerprint LIKE '${SEED_NAMESPACE}:%';

-- 6) Strategy distribution
SELECT strategy, count(*) AS n, round(sum(pnl)::numeric, 2) AS pnl
FROM public.trades
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid
  AND import_fingerprint LIKE '${SEED_NAMESPACE}:%'
GROUP BY strategy
ORDER BY n DESC;

-- 7) Account mix
SELECT account_id, mode, count(*) AS n, round(sum(pnl)::numeric, 2) AS pnl
FROM public.trades
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid
  AND import_fingerprint LIKE '${SEED_NAMESPACE}:%'
GROUP BY account_id, mode;

-- 8) Payouts (no double-count: funded = cycles, live = ledger)
SELECT 'cycles' AS kind, count(*), round(sum(payout_amount)::numeric, 2) AS total
FROM public.account_payout_cycles
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND note LIKE '[${SEED_NAMESPACE}:payouts]%'
UNION ALL
SELECT 'live_ledger', count(*), round(sum(amount)::numeric, 2)
FROM public.account_payout_entries
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND note LIKE '[${SEED_NAMESPACE}:payouts]%';

-- 9) Achievements tagged with seed
SELECT achievement_type, count(*), round(sum(coalesce(value_numeric, 0))::numeric, 2)
FROM public.achievements
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND metadata->>'seed' = '${SEED_NAMESPACE}'
GROUP BY achievement_type;

-- 10) Public feed posts linked to demo trades
SELECT count(*) FROM public.posts p
JOIN public.trades t ON t.id = p.trade_id
WHERE p.user_id = '${SHOWCASE_USER_ID}'::uuid AND t.import_fingerprint LIKE '${SEED_NAMESPACE}:%';

-- 11) Daily check-ins (demo-tagged notes)
SELECT count(*) AS demo_checkins
FROM public.trader_daily_check_ins
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND notes LIKE '[${SEED_NAMESPACE}]%';

-- 12) Duplicate fingerprint guard (expect 0 rows)
SELECT import_fingerprint, count(*)
FROM public.trades
WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND import_fingerprint LIKE '${SEED_NAMESPACE}:%'
GROUP BY import_fingerprint
HAVING count(*) > 1;

-- =============================================================================
-- OPTIONAL ROLLBACK — separate transaction; removes ONLY ${SEED_NAMESPACE} data
-- =============================================================================
-- BEGIN;
-- DELETE FROM public.posts WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND id IN (
--   SELECT p.id FROM public.posts p JOIN public.trades t ON t.id = p.trade_id
--   WHERE t.import_fingerprint LIKE '${SEED_NAMESPACE}:%'
-- );
-- DELETE FROM public.trade_ai_messages m USING public.trades t
--   WHERE m.trade_id = t.id AND t.user_id = '${SHOWCASE_USER_ID}'::uuid AND t.import_fingerprint LIKE '${SEED_NAMESPACE}:%';
-- DELETE FROM public.profile_posts WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND content LIKE '[${SEED_NAMESPACE}]%';
-- DELETE FROM public.achievements WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND metadata->>'seed' = '${SEED_NAMESPACE}';
-- DELETE FROM public.account_payout_entries WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND note LIKE '[${SEED_NAMESPACE}:payouts]%';
-- DELETE FROM public.account_payout_cycles WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND note LIKE '[${SEED_NAMESPACE}:payouts]%';
-- DELETE FROM public.trader_daily_check_ins WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND notes LIKE '[${SEED_NAMESPACE}]%';
-- DELETE FROM public.trades WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND import_fingerprint LIKE '${SEED_NAMESPACE}:%';
-- DELETE FROM public.accounts WHERE user_id = '${SHOWCASE_USER_ID}'::uuid AND note LIKE '[${SEED_NAMESPACE}]%';
-- COMMIT;
`
}

function main() {
  const dataset = buildDataset()
  const stats = computeStats(dataset.trades, dataset.checkIns)
  validateDataset(dataset.trades, dataset.checkIns, stats)
  const payoutPlan = generatePayoutPlan(dataset.trades)

  writeFileSync(OUT_TRADES_SQL, emitTradesSql(dataset, stats), "utf8")
  writeFileSync(OUT_PAYOUTS_SQL, emitPayoutsSql(payoutPlan), "utf8")
  writeFileSync(OUT_VALIDATION_SQL, emitValidationSql(stats, payoutPlan), "utf8")

  console.log("Generated:")
  console.log(" ", OUT_TRADES_SQL)
  console.log(" ", OUT_PAYOUTS_SQL)
  console.log(" ", OUT_VALIDATION_SQL)
  console.log(JSON.stringify({ ...stats, payoutPlan: { fundedPnl: payoutPlan.fundedPnl, livePnl: payoutPlan.livePnl } }, null, 2))
}

main()
