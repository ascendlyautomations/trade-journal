import {
  EMPTY_PSYCHOLOGY_METRICS,
  type PsychologyGroupMetrics,
  type PsychologyReportTrade,
  type PsychologySampleReliability,
} from "./types.ts"

export function resolvePsychologyReliability(
  tradeCount: number
): PsychologySampleReliability {
  if (tradeCount < 5) return "insufficient"
  if (tradeCount <= 9) return "earlySignal"
  if (tradeCount <= 29) return "developing"
  return "strong"
}

export function reliabilityLabel(reliability: PsychologySampleReliability): string {
  switch (reliability) {
    case "insufficient":
      return "Insufficient data"
    case "earlySignal":
      return "Early signal"
    case "developing":
      return "Developing"
    case "strong":
      return "Strong signal"
  }
}

export function qualifiesForDashboardCard(
  reliability: PsychologySampleReliability
): boolean {
  return reliability !== "insufficient"
}

export function qualifiesForComparison(
  reliability: PsychologySampleReliability
): boolean {
  return reliability === "developing" || reliability === "strong"
}

export function psychologyTradeMetrics(
  trades: readonly PsychologyReportTrade[]
): PsychologyGroupMetrics {
  if (trades.length === 0) return EMPTY_PSYCHOLOGY_METRICS

  const pnls = trades.map((trade) =>
    Number.isFinite(trade.pnl) ? trade.pnl : 0
  )
  const wins = pnls.filter((value) => value > 0)
  const losses = pnls.filter((value) => value < 0)
  const tradeCount = trades.length
  const winCount = wins.length
  const lossCount = losses.length
  const grossWins = wins.reduce((sum, value) => sum + value, 0)
  const grossLosses = losses.reduce((sum, value) => sum + value, 0)
  const totalPnL = pnls.reduce((sum, value) => sum + value, 0)
  const winRate = tradeCount > 0 ? winCount / tradeCount : null
  const avgWin = winCount > 0 ? grossWins / winCount : null
  const avgLossAbs = lossCount > 0 ? Math.abs(grossLosses) / lossCount : null
  const lossRate = tradeCount > 0 ? lossCount / tradeCount : 0
  const expectancy =
    tradeCount > 0
      ? (winRate ?? 0) * (avgWin ?? 0) - lossRate * (avgLossAbs ?? 0)
      : null
  const profitFactor = grossLosses < 0 ? grossWins / Math.abs(grossLosses) : null

  let rrSum = 0
  let rrCount = 0
  for (const trade of trades) {
    if (trade.rr == null || !Number.isFinite(trade.rr)) continue
    rrSum += trade.rr
    rrCount += 1
  }

  return {
    tradeCount,
    winCount,
    lossCount,
    winRate,
    totalPnL,
    averagePnL: totalPnL / tradeCount,
    expectancy,
    averageRR: rrCount > 0 ? rrSum / rrCount : null,
    profitFactor,
    reliability: resolvePsychologyReliability(tradeCount),
  }
}

export function pnlSign(trade: PsychologyReportTrade): "win" | "loss" | "flat" {
  if (trade.pnl > 0) return "win"
  if (trade.pnl < 0) return "loss"
  return "flat"
}
