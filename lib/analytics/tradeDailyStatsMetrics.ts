/** Composed metrics from trade_daily_stats ingredients (presentation layer). */

export type DailyStatsIngredients = {
  trade_count: number
  win_count: number
  loss_count: number
  breakeven_count: number
  net_pnl: number
  gross_profit: number
  gross_loss: number
  long_count: number
  long_pnl: number
  short_count: number
  short_pnl: number
  sum_rr: number
  rr_count: number
  sum_hold_seconds: number
  hold_count: number
  largest_win: number | null
  largest_loss: number | null
}

export function composeWinRate(s: DailyStatsIngredients): number | null {
  if (s.trade_count === 0) return null
  return s.win_count / s.trade_count
}

export function composeProfitFactor(s: DailyStatsIngredients): number | null {
  if (s.gross_loss === 0) return s.gross_profit > 0 ? null : null
  const denom = Math.abs(s.gross_loss)
  if (denom === 0) return null
  return s.gross_profit / denom
}

export function composeAverageWinner(s: DailyStatsIngredients): number | null {
  if (s.win_count === 0) return null
  return s.gross_profit / s.win_count
}

export function composeAverageLoser(s: DailyStatsIngredients): number | null {
  if (s.loss_count === 0) return null
  return Math.abs(s.gross_loss) / s.loss_count
}

export function composeAverageRr(s: DailyStatsIngredients): number | null {
  if (s.rr_count === 0) return null
  return s.sum_rr / s.rr_count
}

export function composeAverageHoldSeconds(
  s: DailyStatsIngredients
): number | null {
  if (s.hold_count === 0) return null
  return s.sum_hold_seconds / s.hold_count
}
