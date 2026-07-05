/** Deep-link URL for AI Trade Analyst with a trade pre-selected. */
export function tradeAnalysisHref(tradeId: string | number): string {
  return `/analyst?trade=${encodeURIComponent(String(tradeId))}`
}
