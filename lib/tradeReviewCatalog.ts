/** Mirrors iOS `TradeReviewCatalog` psychology / timeframe option lists. */

export const TRADE_PSYCHOLOGY_CUSTOM_TOKEN = "Custom..." as const

export const TRADE_EMOTION_PRESETS = [
  "Confident",
  "Calm",
  "Focused",
  "Fearful",
  "FOMO",
  "Overconfident",
  "Hesitant",
  "Frustrated",
] as const

export const TRADE_MARKET_CONDITION_PRESETS = [
  "Trending",
  "Strong Trend",
  "Ranging",
  "Choppy",
  "Low Volume",
  "High Volume",
  "News Driven",
  "Volatile",
] as const

export const TRADE_EMOTION_OPTIONS = [
  ...TRADE_EMOTION_PRESETS,
  TRADE_PSYCHOLOGY_CUSTOM_TOKEN,
] as const

export const TRADE_MARKET_CONDITION_OPTIONS = [
  ...TRADE_MARKET_CONDITION_PRESETS,
  TRADE_PSYCHOLOGY_CUSTOM_TOKEN,
] as const

export function isTradeEmotionPreset(value: string): boolean {
  return (TRADE_EMOTION_PRESETS as readonly string[]).includes(value)
}

export function isTradeMarketConditionPreset(value: string): boolean {
  return (TRADE_MARKET_CONDITION_PRESETS as readonly string[]).includes(value)
}

export function resolveTradePsychologyValue(
  selection: string,
  custom: string
): string | null {
  const trimmedSelection = selection.trim()
  if (!trimmedSelection) return null
  if (trimmedSelection === TRADE_PSYCHOLOGY_CUSTOM_TOKEN) {
    const trimmedCustom = custom.trim()
    return trimmedCustom || null
  }
  return trimmedSelection
}

export function tradePsychologyPickerState(
  stored: string | null | undefined,
  presets: readonly string[]
): { selection: string; custom: string } {
  const trimmed = String(stored ?? "").trim()
  if (!trimmed) return { selection: "", custom: "" }
  if (presets.includes(trimmed)) {
    return { selection: trimmed, custom: "" }
  }
  return { selection: TRADE_PSYCHOLOGY_CUSTOM_TOKEN, custom: trimmed }
}
