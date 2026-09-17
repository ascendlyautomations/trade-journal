#!/usr/bin/env node
/**
 * Deterministic App Review demo seed generator (V2).
 * Writes scripts/seed-app-review-trading-history-v2.sql — does NOT connect to Supabase.
 *
 * Usage: node scripts/generate-app-review-seed.mjs
 */

import { createHash } from "node:crypto"
import { writeFileSync } from "node:fs"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const OUT_SQL = resolve(__dirname, "seed-app-review-trading-history-v2.sql")

const SEED_NAMESPACE = "app_review_seed:v2"
const GENERATOR_VERSION = "2.0.0"
const PRNG_SEED = `${SEED_NAMESPACE}:generator:2025-10-01:2026-09-12`

const START_DATE = "2025-10-01"
const END_DATE = "2026-09-12"
const TARGET_TRADES_MIN = 380
const TARGET_TRADES_MAX = 430
const TARGET_WIN_RATE_MIN = 0.57
const TARGET_WIN_RATE_MAX = 0.61
const CHECKIN_MIN = 140
const CHECKIN_MAX = 160
const PUBLIC_TRADES_MIN = 8
const PUBLIC_TRADES_MAX = 12

const ACCOUNT_LIVE_ID = deterministicUuid("account:live")
const ACCOUNT_EVAL_ID = deterministicUuid("account:eval")

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
  "Opening Range Breakout",
  "Liquidity Sweep",
  "VWAP Reclaim",
  "Trend Pullback",
  "Support / Resistance",
  "Breakout Retest",
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

// --- PRNG (mulberry32) ---
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
  const d = parseDate(dateStr)
  const t = d.getTime()
  if (t < parseDate("2026-01-01").getTime()) return "early"
  if (t < parseDate("2026-07-01").getTime()) return "middle"
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

const NOTE_FRAGMENTS = {
  thesis: [
    "Waited for confirmation at the level before sizing in.",
    "Opening range was clean; thesis was continuation after the sweep.",
    "VWAP reclaim lined up with prior day high — took the retest.",
    "Pullback to 9 EMA in a strong trend; planned partial at VWAP.",
    "Liquidity run below overnight low; looked for reversal back into value.",
    "Breakout retest held; wanted to see acceptance before entry.",
    "Support held twice on 5m; entered on the third touch with defined risk.",
    "News spike faded into the close — smaller size given volatility.",
    "Choppy mid-day range; only interested in edges at the extremes.",
    "Trend day — focused on pullbacks rather than chasing extensions.",
  ],
  execution: [
    "Execution was patient; stop stayed at invalidation.",
    "Entered a bit early before the candle closed — noted for review.",
    "Respected the stop when structure broke down.",
    "Moved stop too quickly out of fear — turned a scratch into a loss.",
    "Took profit early despite plan saying hold to target.",
    "Held the winner according to plan; partial made the day.",
    "Poor fill on entry but managed the trade OK afterward.",
    "Good execution despite the loss — process over outcome.",
    "Hesitated on entry and missed the best price; still took the setup.",
    "Reduced size after yesterday's drawdown — good risk control.",
  ],
  psychology: [
    "Felt FOMO after missing the first move; kept size small on the chase.",
    "Revenge urge after the first loss; stopped after two trades.",
    "Overconfidence after the morning win; tightened rules for the afternoon.",
    "Stayed calm after a red open; waited for A+ only.",
    "Frustration crept in mid-session; stepped away for ten minutes.",
    "Focused pre-market routine helped — checklist completed.",
    "Traded outside plan on the last trade; journal flag for coach.",
    "Emotional day but stopped at daily loss limit — progress.",
    "Confidence was high but respected that the level could fail.",
    "Anxious about economic release; sat out until after the print.",
  ],
  outcome: [
    "Net green for the day despite one sloppy trade.",
    "Small red day; no major rule breaks.",
    "Scratch-heavy session — fees ate the edge.",
    "Best trade aligned with my A+ setup list.",
    "Worst trade was clearly impulsive — tag for psychology review.",
    "Stopped trading after hitting daily objective.",
    "Gave back morning gains by overtrading lunch hour.",
    "Closed the platform after max loss — discipline win.",
  ],
}

function composeNote(rng, period, hadMistake) {
  const parts = []
  parts.push(pick(rng, NOTE_FRAGMENTS.thesis))
  parts.push(pick(rng, NOTE_FRAGMENTS.execution))
  if (rng() < (period === "early" ? 0.55 : period === "middle" ? 0.45 : 0.35)) {
    parts.push(pick(rng, NOTE_FRAGMENTS.psychology))
  }
  if (hadMistake || rng() < 0.3) parts.push(pick(rng, NOTE_FRAGMENTS.outcome))
  const joined = parts.slice(0, 2 + Math.floor(rng() * 2)).join(" ")
  return joined.length > 480 ? joined.slice(0, 477) + "..." : joined
}

function composePsychNote(rng, emotion, mistake) {
  const lines = [
    `Pre-trade felt ${emotion.toLowerCase()}.`,
    mistake ? `Primary mistake today: ${mistake.toLowerCase()}.` : "No major mistake tag — review execution anyway.",
    pick(rng, [
      "Will re-read plan before tomorrow's open.",
      "Need to respect max trades per day rule.",
      "Sleep and prep matter — keep morning routine.",
      "Good reminder that edge is in selectivity not volume.",
      "Coach note: pause after consecutive losses.",
    ]),
  ]
  return lines.join(" ")
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

function generateTrade(rng, ctx) {
  const { dateStr, period, account, seqOnDay, dayIndex } = ctx
  let ticker =
    rng() < (period === "recent" ? 0.88 : 0.82) ? "MNQ" : "NQ"
  const direction = rng() < 0.52 ? "Long" : "Short"

  let contracts =
    ticker === "NQ"
      ? 1
      : pickWeighted(rng, [
          { weight: period === "early" ? 2 : 1, value: 1 },
          { weight: period === "early" ? 4 : 3, value: 2 },
          { weight: period === "early" ? 2 : 1, value: 3 },
        ])

  const sessionRoll = rng()
  let hour
  if (sessionRoll < 0.82) hour = 9 + Math.floor(rng() * 7)
  else if (sessionRoll < 0.94) hour = 3 + Math.floor(rng() * 5)
  else hour = 18 + Math.floor(rng() * 4)
  const minute = pick(rng, [5, 12, 18, 22, 35, 42, 48, 55])
  const entryTime = buildTimestamp(dateStr, hour, minute)

  const holdMinutes = pickWeighted(rng, [
    { weight: period === "early" ? 2 : 1, value: 4 + Math.floor(rng() * 8) },
    { weight: 3, value: 12 + Math.floor(rng() * 25) },
    { weight: 2, value: 35 + Math.floor(rng() * 40) },
    { weight: 1, value: 60 + Math.floor(rng() * 45) },
  ])
  const exitDate = addDays(parseDate(dateStr), 0)
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
  const exitTime = buildTimestamp(formatDate(exitDate), exitHour, exitMinute)
  const durationSeconds = holdMinutes * 60

  const priceDrift =
    (dayIndex / 220) * 350 + (rng() - 0.5) * 40
  const base = INSTRUMENTS[ticker].priceBase + priceDrift

  const winBias =
    period === "early"
      ? 0.57
      : period === "middle"
        ? 0.6
        : 0.62
  const isScratch = rng() < 0.03
  const isWin = !isScratch && rng() < winBias
  const isLoss = !isScratch && !isWin

  let points
  if (isScratch) {
    points = 0
  } else if (isWin) {
    const mag = pickWeighted(rng, [
      { weight: 3, value: 4 + rng() * 8 },
      { weight: 2, value: 10 + rng() * 12 },
      { weight: 1, value: 22 + rng() * 18 },
    ])
    points = round2(mag)
  } else {
    const mag = pickWeighted(rng, [
      { weight: 3, value: -(4 + rng() * 8) },
      { weight: 2, value: -(10 + rng() * 10) },
      { weight: 1, value: -(18 + rng() * 14) },
    ])
    points = round2(mag)
  }

  const absPoints = Math.abs(points)
  const tick = 0.25
  const priceMove = absPoints
  let entryPrice = round2(base + (rng() - 0.5) * 20)
  entryPrice = round2(Math.round(entryPrice / tick) * tick)
  let exitPrice
  if (direction === "Long") {
    exitPrice = round2(entryPrice + (points >= 0 ? priceMove : -priceMove))
  } else {
    exitPrice = round2(entryPrice - (points >= 0 ? priceMove : -priceMove))
  }

  const verifiedPoints = computePoints(direction, entryPrice, exitPrice)
  if (Math.abs(verifiedPoints - points) > 0.01) {
    points = verifiedPoints
  }

  let pnl = computePnl(ticker, contracts, points)

  if (isScratch) {
    ticker = "MNQ"
    contracts = 1
    points = 0.51
    entryPrice = round2(base)
    exitPrice = round2(entryPrice + (direction === "Long" ? points : -points))
    points = computePoints(direction, entryPrice, exitPrice)
    pnl = computePnl("MNQ", 1, points)
  }

  const executionBase =
    period === "early" ? 2.4 : period === "middle" ? 3.1 : 3.7
  let executionRating = clamp(
    Math.round(executionBase + (rng() - 0.4) * 2.2),
    1,
    5
  )
  if (isLoss && rng() < (period === "early" ? 0.45 : 0.25)) executionRating = clamp(executionRating - 1, 1, 5)
  if (isWin && rng() < 0.2) executionRating = clamp(executionRating - 1, 1, 5)

  const confidence = clamp(Math.round(2 + rng() * 3 + (period === "recent" ? 0.4 : 0)), 1, 5)

  let emotion = pick(rng, EMOTIONS)
  if (period === "early" && rng() < 0.35) emotion = pick(rng, ["FOMO", "Frustrated", "Overconfident", "Fearful"])
  if (period === "recent" && rng() < 0.4) emotion = pick(rng, ["Calm", "Focused", "Confident"])

  let exitEmotion = pick(rng, EMOTIONS)
  if (isLoss && rng() < 0.5) exitEmotion = pick(rng, ["Frustrated", "Hesitant", "Fearful"])
  if (isWin && rng() < 0.45) exitEmotion = pick(rng, ["Confident", "Calm", "Focused"])

  const followedPlan =
    rng() <
    (period === "early" ? 0.62 : period === "middle" ? 0.74 : 0.83)

  let mistakeType = null
  if ((isLoss || !followedPlan) && rng() < (period === "early" ? 0.42 : period === "middle" ? 0.28 : 0.18)) {
    mistakeType = pick(rng, MISTAKES)
    if (executionRating > 3 && rng() < 0.5) executionRating -= 1
  }

  const strategy =
    period === "recent" && rng() < 0.45
      ? pick(rng, ["VWAP Reclaim", "Trend Pullback", "Breakout Retest"])
      : pick(rng, STRATEGIES)

  const psychologyNotes =
    rng() < (period === "early" ? 0.62 : 0.68) ? composePsychNote(rng, emotion, mistakeType) : null

  const notes = composeNote(rng, period, Boolean(mistakeType))
  const rr = round2(Math.abs(points) / (4 + rng() * 6) * (points >= 0 ? 1 : -1))

  const fingerprint = `${SEED_NAMESPACE}:trade:${dateStr}:${String(seqOnDay).padStart(2, "0")}`
  const id = deterministicUuid(`trade:${fingerprint}`)

  return {
    id,
    accountKey: account,
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
    strategy,
    notes,
    timeframe: pick(rng, TIMEFRAMES),
    rr,
    confidence,
    emotion,
    exit_emotion: exitEmotion,
    execution_rating: executionRating,
    followed_plan: followedPlan,
    market_condition: pick(rng, MARKET_CONDITIONS),
    news_event: rng() < 0.06,
    mistake_type: mistakeType,
    trade_type: pick(rng, TRADE_TYPES),
    psychology_notes: psychologyNotes,
    top_confluences: pick(rng, CONFLUENCES),
    import_fingerprint: fingerprint,
    period,
  }
}

function generateCheckIn(rng, dateStr, dayTrades, period) {
  const id = deterministicUuid(`checkin:${dateStr}`)
  const dayPnl = dayTrades.reduce((s, t) => s + t.pnl, 0)
  const avgExec =
    dayTrades.reduce((s, t) => s + t.execution_rating, 0) / dayTrades.length

  let sleepHours = round2(6 + rng() * 2.5)
  if (period === "early" && rng() < 0.2) sleepHours = round2(4.5 + rng() * 2)

  let stress = 3
  if (period === "early") stress = clamp(Math.round(2 + rng() * 2.2 - (dayPnl > 0 ? 0.3 : 0)), 1, 5)
  else if (period === "middle") stress = clamp(Math.round(2.5 + rng() * 1.8 - (dayPnl > 0 ? 0.4 : 0)), 1, 5)
  else stress = clamp(Math.round(3.2 + rng() * 1.6 - (dayPnl > 0 ? 0.5 : 0)), 1, 5)

  const sleepQuality = clamp(Math.round(2 + rng() * 2 + (sleepHours >= 7 ? 0.6 : -0.4)), 1, 5)
  const morningRating = clamp(Math.round(2 + rng() * 2.5), 1, 5)
  let energy = clamp(Math.round(2 + rng() * 2 + (sleepHours >= 7 ? 0.5 : -0.5)), 1, 5)
  let focus = clamp(Math.round(2 + rng() * 2.5 - (avgExec < 3 ? 0.6 : 0)), 1, 5)

  const noteVariants = [
    `[${SEED_NAMESPACE}] Solid sleep; pre-market levels marked and plan reviewed.`,
    `[${SEED_NAMESPACE}] Short night — keeping size smaller until focus improves.`,
    `[${SEED_NAMESPACE}] Routine morning; coffee and checklist before the open.`,
    `[${SEED_NAMESPACE}] Feeling tense about the week; breathing exercise helped.`,
    `[${SEED_NAMESPACE}] Calm start; goal is quality over quantity today.`,
    `[${SEED_NAMESPACE}] Distracted morning; delayed start until first A+ setup.`,
    `[${SEED_NAMESPACE}] Good energy; reminded myself of daily loss limit.`,
    `[${SEED_NAMESPACE}] Meh sleep but showing up anyway — rules tight today.`,
  ]
  const notes = pick(rng, noteVariants)

  return {
    id,
    check_in_date: dateStr,
    sleep_hours: sleepHours,
    sleep_quality: sleepQuality,
    morning_rating: morningRating,
    stress_level: stress,
    energy_level: energy,
    focus_level: focus,
    notes,
  }
}

function generateAchievements(trades) {
  const ach = []
  const add = (key, row) => ach.push({ ...row, id: deterministicUuid(`achievement:${key}`), metadata: { seed: SEED_NAMESPACE, key } })

  const octPnl = trades.filter((t) => t.trade_date.startsWith("2025-10")).reduce((s, t) => s + t.pnl, 0)
  add("milestone:first-green-month", {
    achievement_type: "milestone",
    category: "milestones",
    title: "First Green Month",
    description: "Finished October 2025 net positive across journal trades.",
    achieved_at: "2025-11-01T14:00:00-04:00",
    value_numeric: Math.max(500, Math.round(octPnl)),
    value_text: null,
    account_id: null,
    is_public: true,
    is_featured: false,
    sort_order: 1,
  })

  add("milestone:consistency", {
    achievement_type: "milestone",
    category: "milestones",
    title: "Consistency Milestone",
    description: "Ten consecutive trading days following the daily plan.",
    achieved_at: "2026-03-18T16:30:00-04:00",
    value_numeric: 10,
    value_text: "10 days",
    account_id: null,
    is_public: true,
    is_featured: false,
    sort_order: 2,
  })

  add("passed_eval", {
    achievement_type: "passed_eval",
    category: "passed_evals",
    title: "Passed Evaluation",
    description: "Met evaluation objectives on the Evaluation Account.",
    achieved_at: "2026-05-22T11:00:00-04:00",
    value_numeric: null,
    value_text: "50K Eval",
    account_id: ACCOUNT_EVAL_ID,
    is_public: true,
    is_featured: true,
    sort_order: 3,
  })

  add("milestone:personal-best", {
    achievement_type: "milestone",
    category: "milestones",
    title: "Personal Best Week",
    description: "Largest net profitable week in the journal.",
    achieved_at: "2026-08-08T17:00:00-04:00",
    value_numeric: 820,
    value_text: null,
    account_id: ACCOUNT_LIVE_ID,
    is_public: false,
    is_featured: false,
    sort_order: 4,
  })

  add("milestone:discipline", {
    achievement_type: "milestone",
    category: "milestones",
    title: "Discipline Streak",
    description: "Fifteen sessions ending at or above 4/5 execution rating.",
    achieved_at: "2026-09-01T09:00:00-04:00",
    value_numeric: 15,
    value_text: "sessions",
    account_id: null,
    is_public: false,
    is_featured: false,
    sort_order: 5,
  })

  return ach
}

function generateProfilePosts() {
  return [
    {
      id: deterministicUuid("post:1"),
      content: `[${SEED_NAMESPACE}] Sharing that journaling daily check-ins changed how I prep for the open. Not every day is green — the process is the point.`,
      created_at: "2026-02-14T18:00:00-05:00",
    },
    {
      id: deterministicUuid("post:2"),
      content: `[${SEED_NAMESPACE}] Passed my eval after tightening rules on revenge trades. Grateful for the psychology reports surfacing patterns I ignored.`,
      created_at: "2026-05-23T12:00:00-04:00",
    },
    {
      id: deterministicUuid("post:3"),
      content: `[${SEED_NAMESPACE}] Summer goal: fewer trades, clearer plans. Execution ratings trending up — still work to do.`,
      created_at: "2026-07-20T20:00:00-04:00",
    },
  ]
}

function buildDataset() {
  const rng = mulberry32(hashSeedToInt(PRNG_SEED))
  const trades = []
  const checkIns = []
  const activeDays = []

  let dayIndex = 0
  for (let d = parseDate(START_DATE); d <= parseDate(END_DATE); d = addDays(d, 1)) {
    if (!isWeekday(d)) continue
    const dateStr = formatDate(d)
    const period = periodForDate(dateStr)
    const month = d.getUTCMonth()
    const isHolidaySkip =
      (month === 11 && d.getUTCDate() >= 24 && d.getUTCDate() <= 31) ||
      (month === 6 && d.getUTCDate() >= 1 && d.getUTCDate() <= 7 && rng() < 0.5)

    let tradeProb =
      period === "early" ? 0.78 : period === "middle" ? 0.72 : 0.68
    if (isHolidaySkip) tradeProb *= 0.35

    if (rng() > tradeProb) continue

    activeDays.push(dateStr)
    const numTrades =
      period === "early"
        ? 2 + Math.floor(rng() * 3.5)
        : period === "middle"
          ? 1 + Math.floor(rng() * 3.2)
          : 1 + Math.floor(rng() * 2.5)

    const dayTrades = []
    for (let i = 0; i < numTrades; i++) {
      const account = rng() < 0.75 ? "live" : "eval"
      dayTrades.push(
        generateTrade(rng, {
          dateStr,
          period,
          account,
          seqOnDay: i + 1,
          dayIndex,
        })
      )
    }
    trades.push(...dayTrades)

    if (rng() < 0.9) {
      checkIns.push(generateCheckIn(rng, dateStr, dayTrades, period))
    }
    dayIndex++
  }

  // Trim or extend to trade band
  let attempts = 0
  while (trades.length < TARGET_TRADES_MIN && attempts < 50) {
    attempts++
    const rng2 = mulberry32(hashSeedToInt(`${PRNG_SEED}:pad:${attempts}`))
    const pickDay = activeDays[Math.floor(rng2() * activeDays.length)] || START_DATE
    const period = periodForDate(pickDay)
    trades.push(
      generateTrade(rng2, {
        dateStr: pickDay,
        period,
        account: rng2() < 0.75 ? "live" : "eval",
        seqOnDay: 9 + attempts,
        dayIndex: 100 + attempts,
      })
    )
  }

  while (trades.length > TARGET_TRADES_MAX) {
    trades.pop()
  }

  const tradingDays = [...new Set(trades.map((t) => t.trade_date))].sort()
  let ci = 0
  while (checkIns.length < CHECKIN_MIN && ci < tradingDays.length) {
    const dateStr = tradingDays[ci++]
    if (checkIns.some((c) => c.check_in_date === dateStr)) continue
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
  while (checkIns.length > CHECKIN_MAX) checkIns.pop()

  // Public trades spread across timeline
  const sorted = [...trades].sort((a, b) => a.trade_date.localeCompare(b.trade_date) || a.import_fingerprint.localeCompare(b.import_fingerprint))
  const publicCount = PUBLIC_TRADES_MIN + Math.floor(rng() * (PUBLIC_TRADES_MAX - PUBLIC_TRADES_MIN + 1))
  const step = Math.max(1, Math.floor(sorted.length / publicCount))
  for (let i = 0; i < sorted.length && i / step < publicCount; i += step) {
    sorted[i].is_public = true
    sorted[i].first_published_at = sorted[i].entry_time
  }

  const achievements = generateAchievements(trades)
  const profilePosts = generateProfilePosts()

  return { trades, checkIns, achievements, profilePosts, activeDays: [...new Set(trades.map((t) => t.trade_date))].sort() }
}

function computeStats(trades, checkIns) {
  const scratches = trades.filter((t) => Math.abs(t.pnl) < 1.5).length
  const wins = trades.filter((t) => t.pnl >= 1.5).length
  const losses = trades.filter((t) => t.pnl <= -1.5).length
  const totalPnl = round2(trades.reduce((s, t) => s + t.pnl, 0))
  const winRate = wins / Math.max(1, wins + losses)
  const grossWins = trades.filter((t) => t.pnl > 0).reduce((s, t) => s + t.pnl, 0)
  const grossLosses = Math.abs(trades.filter((t) => t.pnl < 0).reduce((s, t) => s + t.pnl, 0))
  const profitFactor = grossLosses > 0 ? round2(grossWins / grossLosses) : null
  const avgWin = wins ? round2(grossWins / wins) : 0
  const avgLoss = losses ? round2(-grossLosses / losses) : 0

  let running = 0
  let peak = 0
  let maxDd = 0
  const chronological = [...trades].sort((a, b) => a.entry_time.localeCompare(b.entry_time))
  for (const t of chronological) {
    running = round2(running + t.pnl)
    if (running > peak) peak = running
    const dd = peak - running
    if (dd > maxDd) maxDd = dd
  }

  const earlyTrades = trades.filter((t) => periodForDate(t.trade_date) === "early")
  const recentTrades = trades.filter((t) => periodForDate(t.trade_date) === "recent")
  const earlyCheckins = checkIns.filter((c) => periodForDate(c.check_in_date) === "early")
  const recentCheckins = checkIns.filter((c) => periodForDate(c.check_in_date) === "recent")

  const avg = (arr, fn) => (arr.length ? arr.reduce((s, x) => s + fn(x), 0) / arr.length : 0)

  return {
    tradeCount: trades.length,
    activeDays: new Set(trades.map((t) => t.trade_date)).size,
    checkInCount: checkIns.length,
    mnq: trades.filter((t) => t.ticker === "MNQ").length,
    nq: trades.filter((t) => t.ticker === "NQ").length,
    long: trades.filter((t) => t.direction === "Long").length,
    short: trades.filter((t) => t.direction === "Short").length,
    wins,
    losses,
    scratches,
    winRate,
    totalPnl,
    profitFactor,
    avgWin,
    avgLoss,
    maxDrawdown: round2(maxDd),
    avgExecution: round2(avg(trades, (t) => t.execution_rating)),
    followedPlanPct: round2(100 * (trades.filter((t) => t.followed_plan).length / trades.length)),
    avgStressEarly: round2(avg(earlyCheckins, (c) => c.stress_level)),
    avgStressRecent: round2(avg(recentCheckins, (c) => c.stress_level)),
    avgExecEarly: round2(avg(earlyTrades, (t) => t.execution_rating)),
    avgExecRecent: round2(avg(recentTrades, (t) => t.execution_rating)),
    publicTrades: trades.filter((t) => t.is_public).length,
    firstDate: sortedDates(trades)[0],
    lastDate: sortedDates(trades)[sortedDates(trades).length - 1],
  }
}

function sortedDates(trades) {
  return [...new Set(trades.map((t) => t.trade_date))].sort()
}

function validateDataset(trades, checkIns, stats) {
  const errors = []
  if (stats.tradeCount < TARGET_TRADES_MIN || stats.tradeCount > TARGET_TRADES_MAX) {
    errors.push(`Trade count ${stats.tradeCount} outside ${TARGET_TRADES_MIN}-${TARGET_TRADES_MAX}`)
  }
  if (stats.winRate < TARGET_WIN_RATE_MIN || stats.winRate > TARGET_WIN_RATE_MAX) {
    errors.push(`Win rate ${(stats.winRate * 100).toFixed(1)}% outside target band`)
  }
  if (stats.checkInCount < CHECKIN_MIN || stats.checkInCount > CHECKIN_MAX) {
    errors.push(`Check-in count ${stats.checkInCount} outside ${CHECKIN_MIN}-${CHECKIN_MAX}`)
  }
  if (stats.maxDrawdown < 350) {
    errors.push(`Max drawdown ${stats.maxDrawdown} too small — need realistic drawdown`)
  }
  if (stats.totalPnl <= 0) {
    errors.push("Total P&L must be positive")
  }
  if (stats.avgStressRecent <= stats.avgStressEarly + 0.25) {
    errors.push(
      `Recent stress (${stats.avgStressRecent}) should be calmer (higher) than early (${stats.avgStressEarly})`
    )
  }
  if (stats.avgExecRecent <= stats.avgExecEarly + 0.15) {
    errors.push(
      `Recent execution (${stats.avgExecRecent}) should exceed early (${stats.avgExecEarly})`
    )
  }

  const fps = new Set()
  for (const t of trades) {
    if (fps.has(t.import_fingerprint)) errors.push(`Duplicate fingerprint ${t.import_fingerprint}`)
    fps.add(t.import_fingerprint)
    if (t.trade_date < START_DATE || t.trade_date > END_DATE) errors.push(`Trade date out of range: ${t.trade_date}`)
    const vp = computePoints(t.direction, t.entry_price, t.exit_price)
    if (Math.abs(vp - t.points) > 0.02) errors.push(`Points mismatch ${t.import_fingerprint}`)
    const pnl = computePnl(t.ticker, t.contracts, t.points)
    if (Math.abs(pnl - t.pnl) > 0.02) errors.push(`PnL mismatch ${t.import_fingerprint}`)
    if (t.execution_rating < 1 || t.execution_rating > 5) errors.push(`Bad execution rating ${t.id}`)
    if (t.confidence < 1 || t.confidence > 5) errors.push(`Bad confidence ${t.id}`)
    if (t.duration_seconds < 60) errors.push(`Duration too short ${t.import_fingerprint}`)
    if (!EMOTIONS.includes(t.emotion) || !EMOTIONS.includes(t.exit_emotion)) {
      errors.push(`Invalid emotion ${t.import_fingerprint}`)
    }
  }

  for (const c of checkIns) {
    if (c.stress_level < 1 || c.stress_level > 5) errors.push(`Bad stress ${c.check_in_date}`)
  }

  const liveShare = trades.filter((t) => t.accountKey === "live").length / trades.length
  if (liveShare < 0.7 || liveShare > 0.8) {
    errors.push(`Live account share ${(liveShare * 100).toFixed(1)}% outside ~75%`)
  }

  if (errors.length) throw new Error(`Generator validation failed:\n- ${errors.join("\n- ")}`)
}

function chunk(arr, size) {
  const out = []
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size))
  return out
}

function tradeRowSql(t, liveMeta, evalMeta) {
  const acct = t.accountKey === "live" ? liveMeta : evalMeta
  return `(${sqlStr(t.id)}::uuid, ${sqlStr(acct.id)}::uuid, ${sqlStr(t.trade_date)}::date, ${sqlStr(t.ticker)}, ${sqlStr(t.direction)}, ${sqlNum(t.contracts)}, ${sqlNum(t.entry_price)}, ${sqlNum(t.exit_price)}, ${sqlNum(t.points)}, ${sqlNum(t.pnl)}, ${sqlStr(t.entry_time)}::timestamptz, ${sqlStr(t.exit_time)}::timestamptz, ${sqlStr(t.session)}, ${sqlNum(t.duration_seconds)}, ${sqlStr(t.duration_text)}, ${sqlStr(t.strategy)}, ${sqlStr(t.notes)}, ${sqlStr(t.timeframe)}, ${sqlNum(t.rr)}, ${sqlNum(t.confidence)}, ${sqlStr(t.emotion)}, ${sqlStr(t.exit_emotion)}, ${sqlNum(t.execution_rating)}, ${sqlBool(t.followed_plan)}, ${sqlStr(t.market_condition)}, ${sqlBool(t.news_event)}, ${t.mistake_type ? sqlStr(t.mistake_type) : "null"}, ${sqlStr(t.trade_type)}, ${t.psychology_notes ? sqlStr(t.psychology_notes) : "null"}, ${t.top_confluences ? sqlStr(t.top_confluences) : "null"}, ${sqlStr(t.import_fingerprint)}, ${sqlBool(Boolean(t.is_public))}, ${t.first_published_at ? sqlStr(t.first_published_at) + "::timestamptz" : "null"})`
}

function emitSql({ trades, checkIns, achievements, profilePosts }, stats) {
  const liveMeta = { id: ACCOUNT_LIVE_ID, name: "Apple Review Futures", category: "Personal", mode: "Live", size: null }
  const evalMeta = {
    id: ACCOUNT_EVAL_ID,
    name: "Evaluation Account",
    category: "Prop Firm",
    mode: "Eval",
    size: "50000",
  }

  const tradeCols = chunk(trades, 25)
    .map(
      (rows) =>
        `INSERT INTO _app_review_v2_trades VALUES\n${rows.map((t) => tradeRowSql(t, liveMeta, evalMeta)).join(",\n")};`
    )
    .join("\n\n")

  const checkinValues = checkIns
    .map(
      (c) =>
        `(${sqlStr(c.id)}::uuid, ${sqlStr(c.check_in_date)}::date, ${sqlNum(c.sleep_hours)}, ${sqlNum(c.sleep_quality)}, ${sqlNum(c.morning_rating)}, ${sqlNum(c.stress_level)}, ${sqlNum(c.energy_level)}, ${sqlNum(c.focus_level)}, ${sqlStr(c.notes)})`
    )
    .join(",\n")

  const achValues = achievements
    .map(
      (a) =>
        `(${sqlStr(a.id)}::uuid, ${sqlStr(a.achievement_type)}, ${sqlStr(a.category)}, ${sqlStr(a.title)}, ${a.description ? sqlStr(a.description) : "null"}, ${sqlStr(a.achieved_at)}::timestamptz, ${a.value_numeric != null ? sqlNum(a.value_numeric) : "null"}, ${a.value_text ? sqlStr(a.value_text) : "null"}, ${a.account_id ? sqlStr(a.account_id) + "::uuid" : "null"}, ${sqlBool(a.is_public)}, ${sqlBool(a.is_featured)}, ${sqlNum(a.sort_order)}, ${sqlStr(JSON.stringify(a.metadata))}::jsonb)`
    )
    .join(",\n")

  const postValues = profilePosts
    .map(
      (p) =>
        `(${sqlStr(p.id)}::uuid, ${sqlStr(p.content)}, ${sqlStr(p.created_at)}::timestamptz)`
    )
    .join(",\n")

  const sql = `-- =============================================================================
-- TradeTraxs App Store Review demo seed V2 (GENERATED — DO NOT EDIT BY HAND)
-- Generator: scripts/generate-app-review-seed.mjs v${GENERATOR_VERSION}
-- Namespace: ${SEED_NAMESPACE}
-- Window: ${START_DATE} .. ${END_DATE}
-- Generated stats (pre-apply): trades=${stats.tradeCount}, check-ins=${stats.checkInCount}, win%=${(stats.winRate * 100).toFixed(1)}, pnl=${stats.totalPnl}, maxDD=${stats.maxDrawdown}
--
-- BEFORE RUNNING IN SUPABASE (service role SQL editor):
--   1) Replace __TARGET_USER_ID__ with the dedicated review profiles.id (UUID).
--   2) Replace __EXPECTED_REVIEW_EMAIL__ with the exact auth.users email for that id.
--   3) Confirm review profile has Pro entitlement if seeding TWO manual accounts.
--   4) Inspect this file; then run in a single transaction.
--
-- DO NOT commit credentials to git.
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _app_review_v2_trades (
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
  first_published_at timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE _app_review_v2_checkins (
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

CREATE TEMP TABLE _app_review_v2_achievements (
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

CREATE TEMP TABLE _app_review_v2_profile_posts (
  id uuid PRIMARY KEY,
  content text NOT NULL,
  created_at timestamptz NOT NULL
) ON COMMIT DROP;

${tradeCols}

INSERT INTO _app_review_v2_checkins VALUES
${checkinValues};

INSERT INTO _app_review_v2_achievements VALUES
${achValues};

INSERT INTO _app_review_v2_profile_posts VALUES
${postValues};

DO $$
DECLARE
  target_user_id uuid := '__TARGET_USER_ID__'::uuid;
  expected_review_email text := '__EXPECTED_REVIEW_EMAIL__';
  auth_email text;
  profile_ok boolean;
  pro_ok boolean;
  reg_accounts int;
  v_live_id uuid := '${ACCOUNT_LIVE_ID}'::uuid;
  v_eval_id uuid := '${ACCOUNT_EVAL_ID}'::uuid;
  inserted_accounts int := 0;
  inserted_trades int := 0;
  inserted_checkins int := 0;
  inserted_ach int := 0;
  inserted_posts int := 0;
  v_trade_count int;
  v_win int;
  v_loss int;
  v_scratch int;
  v_pnl numeric;
  v_pf numeric;
  v_max_dd numeric;
  v_early_stress numeric;
  v_recent_stress numeric;
BEGIN
  IF target_user_id IS NULL OR target_user_id = '00000000-0000-0000-0000-000000000000'::uuid THEN
    RAISE EXCEPTION 'Set target_user_id to the dedicated App Review user UUID (replace __TARGET_USER_ID__).';
  END IF;
  IF expected_review_email IS NULL OR trim(expected_review_email) = '' OR expected_review_email = '__EXPECTED_REVIEW_EMAIL__' THEN
    RAISE EXCEPTION 'Set expected_review_email to the exact auth.users email (replace __EXPECTED_REVIEW_EMAIL__).';
  END IF;

  SELECT u.email INTO auth_email FROM auth.users u WHERE u.id = target_user_id;
  IF auth_email IS NULL THEN
    RAISE EXCEPTION 'auth.users has no row for %', target_user_id;
  END IF;
  IF lower(trim(auth_email)) <> lower(trim(expected_review_email)) THEN
    RAISE EXCEPTION 'Email mismatch for %. Expected % but auth.users has %.', target_user_id, expected_review_email, auth_email;
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = target_user_id) INTO profile_ok;
  IF NOT profile_ok THEN
    RAISE EXCEPTION 'profiles.id missing for %', target_user_id;
  END IF;

  SELECT
    coalesce(p.is_pro, false)
    OR lower(trim(coalesce(p.subscription_status::text, ''))) = 'active'
  INTO pro_ok
  FROM public.profiles p WHERE p.id = target_user_id;

  SELECT count(*)::int INTO reg_accounts FROM public.user_accounts ua WHERE ua.user_id = target_user_id;

  IF NOT coalesce(pro_ok, false) THEN
    RAISE EXCEPTION 'Review profile must have Pro entitlement (profiles.is_pro or subscription_status active) before seeding two manual trading accounts.';
  END IF;

  -- Accounts (deterministic ids; note marks seed ownership)
  INSERT INTO public.accounts (
    id, user_id, name, category, mode, account_size, can_add_trades, is_active,
    show_in_account_dropdowns, profit_target, max_drawdown, daily_drawdown,
    drawdown_type, winning_day_threshold, note
  ) VALUES (
    v_live_id, target_user_id, 'Apple Review Futures', 'Personal', 'Live', null, true, true,
    true, null, null, null, null, null,
    '[${SEED_NAMESPACE}] Apple Review primary live account'
  ) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    note = EXCLUDED.note
  WHERE public.accounts.id = v_live_id AND public.accounts.user_id = target_user_id;

  IF FOUND THEN inserted_accounts := inserted_accounts + 1; END IF;

  INSERT INTO public.accounts (
    id, user_id, name, category, mode, account_size, can_add_trades, is_active,
    show_in_account_dropdowns, profit_target, max_drawdown, daily_drawdown,
    drawdown_type, winning_day_threshold, note
  ) VALUES (
    v_eval_id, target_user_id, 'Evaluation Account', 'Prop Firm', 'Eval', '50000', true, true,
    true, 3000, 2000, 1000, 'end_of_day_trailing', 100,
    '[${SEED_NAMESPACE}] Apple Review prop eval account'
  ) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    note = EXCLUDED.note
  WHERE public.accounts.id = v_eval_id AND public.accounts.user_id = target_user_id;

  IF FOUND THEN inserted_accounts := inserted_accounts + 1; END IF;

  INSERT INTO public.trades (
    id, user_id, account_id, account_name, account_size, account_type, account_category,
    ticker, direction, mode, contracts, entry_price, exit_price, entry_time, exit_time,
    trade_date, pnl, rr, points, session, strategy, notes, timeframe, news_event,
    confidence, emotion, followed_plan, market_condition, psychology_notes,
    exit_emotion, execution_rating, duration_seconds, duration_text,
    is_public, public_description, first_published_at, image_display_mode, reviewed, is_initial_import,
    import_source, import_fingerprint, created_at, date,
    mistake_type, trade_type, top_confluences
  )
  SELECT
    s.id, target_user_id, s.account_id,
    CASE WHEN s.account_id = v_live_id THEN 'Apple Review Futures' ELSE 'Evaluation Account' END,
    CASE WHEN s.account_id = v_eval_id THEN '50000' ELSE null END,
    CASE WHEN s.account_id = v_live_id THEN 'Live' ELSE 'Eval' END,
    CASE WHEN s.account_id = v_live_id THEN 'Personal' ELSE 'Prop Firm' END,
    s.ticker, s.direction,
    CASE WHEN s.account_id = v_live_id THEN 'Live' ELSE 'Eval' END,
    s.contracts, s.entry_price, s.exit_price, s.entry_time, s.exit_time,
    s.trade_date, s.pnl, s.rr, s.points, s.session, s.strategy, s.notes, s.timeframe, s.news_event,
    s.confidence, s.emotion, s.followed_plan, s.market_condition, s.psychology_notes,
    s.exit_emotion, s.execution_rating, s.duration_seconds, s.duration_text,
    s.is_public, '', s.first_published_at, 'fit', true, false,
    'manual', s.import_fingerprint, s.entry_time, s.entry_time,
    s.mistake_type, s.trade_type, s.top_confluences
  FROM _app_review_v2_trades s
  WHERE NOT EXISTS (
    SELECT 1 FROM public.trades t
    WHERE t.user_id = target_user_id AND t.import_fingerprint = s.import_fingerprint
  );

  GET DIAGNOSTICS inserted_trades = ROW_COUNT;

  INSERT INTO public.trader_daily_check_ins (
    id, user_id, check_in_date, sleep_hours, sleep_quality, morning_rating,
    stress_level, energy_level, focus_level, notes
  )
  SELECT c.id, target_user_id, c.check_in_date, c.sleep_hours, c.sleep_quality, c.morning_rating,
    c.stress_level, c.energy_level, c.focus_level, c.notes
  FROM _app_review_v2_checkins c
  WHERE NOT EXISTS (
    SELECT 1 FROM public.trader_daily_check_ins x
    WHERE x.user_id = target_user_id AND x.check_in_date = c.check_in_date
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.trader_daily_check_ins x
    WHERE x.user_id = target_user_id AND x.check_in_date = c.check_in_date AND x.notes NOT LIKE '[${SEED_NAMESPACE}]%'
  );

  GET DIAGNOSTICS inserted_checkins = ROW_COUNT;

  INSERT INTO public.achievements (
    id, user_id, achievement_type, category, title, description, achieved_at,
    value_numeric, value_text, account_id, is_public, is_featured, sort_order, metadata
  )
  SELECT a.id, target_user_id, a.achievement_type, a.category, a.title, a.description, a.achieved_at,
    a.value_numeric, a.value_text, a.account_id, a.is_public, a.is_featured, a.sort_order, a.metadata
  FROM _app_review_v2_achievements a
  WHERE NOT EXISTS (
    SELECT 1 FROM public.achievements x
    WHERE x.id = a.id AND x.user_id = target_user_id
  );

  GET DIAGNOSTICS inserted_ach = ROW_COUNT;

  INSERT INTO public.profile_posts (id, user_id, content, created_at, image_url)
  SELECT p.id, target_user_id, p.content, p.created_at, null
  FROM _app_review_v2_profile_posts p
  WHERE NOT EXISTS (SELECT 1 FROM public.profile_posts x WHERE x.id = p.id);

  GET DIAGNOSTICS inserted_posts = ROW_COUNT;

  -- Pre-commit validation on seeded rows only
  SELECT count(*) INTO v_trade_count FROM public.trades t
    WHERE t.user_id = target_user_id AND t.import_fingerprint LIKE '${SEED_NAMESPACE}:%';

  IF v_trade_count < ${TARGET_TRADES_MIN} THEN
    RAISE EXCEPTION 'Post-insert trade count % below minimum (includes prior v2 runs).', v_trade_count;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.trades t
    WHERE t.user_id = target_user_id AND t.import_fingerprint LIKE '${SEED_NAMESPACE}:%'
      AND (t.trade_date > '${END_DATE}'::date OR t.trade_date < '${START_DATE}'::date)
  ) THEN
    RAISE EXCEPTION 'Seeded trades outside allowed date window.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.trades t
    WHERE t.user_id = target_user_id AND t.import_fingerprint LIKE '${SEED_NAMESPACE}:%'
      AND (t.image_url IS NOT NULL OR t.broker_connection_id IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'Seeded trades must not reference storage or broker fields.';
  END IF;

  SELECT
    count(*) FILTER (WHERE pnl > 0),
    count(*) FILTER (WHERE pnl < 0),
    count(*) FILTER (WHERE pnl = 0),
    coalesce(sum(pnl), 0)
  INTO v_win, v_loss, v_scratch, v_pnl
  FROM public.trades t
  WHERE t.user_id = target_user_id AND t.import_fingerprint LIKE '${SEED_NAMESPACE}:%';

  SELECT coalesce(
    sum(gw) / nullif(sum(gl), 0), 0)
  INTO v_pf
  FROM (
    SELECT
      CASE WHEN pnl > 0 THEN pnl ELSE 0 END AS gw,
      CASE WHEN pnl < 0 THEN abs(pnl) ELSE 0 END AS gl
    FROM public.trades
    WHERE user_id = target_user_id AND import_fingerprint LIKE '${SEED_NAMESPACE}:%'
  ) s;

  SELECT avg(stress_level) INTO v_early_stress
  FROM public.trader_daily_check_ins
  WHERE user_id = target_user_id AND notes LIKE '[${SEED_NAMESPACE}]%'
    AND check_in_date < '2026-01-01'::date;

  SELECT avg(stress_level) INTO v_recent_stress
  FROM public.trader_daily_check_ins
  WHERE user_id = target_user_id AND notes LIKE '[${SEED_NAMESPACE}]%'
    AND check_in_date >= '2026-07-01'::date;

  RAISE NOTICE 'App Review V2 seed summary: accounts touched=%, trades inserted=%, check-ins inserted=%, achievements inserted=%, posts inserted=%',
    inserted_accounts, inserted_trades, inserted_checkins, inserted_ach, inserted_posts;
  RAISE NOTICE 'V2 totals: trades=%, wins=%, losses=%, scratches=%, pnl=%, profit_factor=%, stress_early=%, stress_recent=%',
    v_trade_count, v_win, v_loss, v_scratch, round(v_pnl::numeric, 2), round(v_pf::numeric, 2),
    round(v_early_stress::numeric, 2), round(v_recent_stress::numeric, 2);
END $$;

COMMIT;

-- =============================================================================
-- OPTIONAL ROLLBACK (separate transaction; replace __TARGET_USER_ID__)
-- Removes ONLY ${SEED_NAMESPACE} rows — never all trades for the user.
-- =============================================================================
-- BEGIN;
-- DELETE FROM public.trade_ai_messages m
--  USING public.trades t
--  WHERE m.trade_id = t.id AND t.user_id = '__TARGET_USER_ID__'::uuid
--    AND t.import_fingerprint LIKE '${SEED_NAMESPACE}:%';
-- DELETE FROM public.profile_posts
--  WHERE user_id = '__TARGET_USER_ID__'::uuid
--    AND content LIKE '[${SEED_NAMESPACE}]%';
-- DELETE FROM public.achievements
--  WHERE user_id = '__TARGET_USER_ID__'::uuid
--    AND metadata->>'seed' = '${SEED_NAMESPACE}';
-- DELETE FROM public.trader_daily_check_ins
--  WHERE user_id = '__TARGET_USER_ID__'::uuid
--    AND notes LIKE '[${SEED_NAMESPACE}]%';
-- DELETE FROM public.trades
--  WHERE user_id = '__TARGET_USER_ID__'::uuid
--    AND import_fingerprint LIKE '${SEED_NAMESPACE}:%';
-- DELETE FROM public.accounts
--  WHERE user_id = '__TARGET_USER_ID__'::uuid
--    AND note LIKE '[${SEED_NAMESPACE}]%';
-- COMMIT;
`

  return sql
}

function main() {
  const { trades, checkIns, achievements, profilePosts } = buildDataset()
  const stats = computeStats(trades, checkIns)
  stats.achievementCount = achievements.length
  validateDataset(trades, checkIns, stats)
  const sql = emitSql({ trades, checkIns, achievements, profilePosts }, stats)
  writeFileSync(OUT_SQL, sql, "utf8")

  console.log("Generated:", OUT_SQL)
  console.log(JSON.stringify(stats, null, 2))
}

main()
