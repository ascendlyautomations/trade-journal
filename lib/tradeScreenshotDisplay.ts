/** Max rendered height before tall images crop with object-cover. */
export const TRADE_SCREENSHOT_MAX_HEIGHT_PX = 560

/**
 * Height/width above this is treated as extremely tall and cropped at max height.
 * Moderate portrait images keep their natural height.
 */
export const TRADE_SCREENSHOT_TALL_RATIO = 1.2

export type TradeScreenshotLayout = "natural" | "tall-crop"

export function resolveTradeScreenshotLayout(
  naturalWidth: number,
  naturalHeight: number
): TradeScreenshotLayout {
  if (naturalWidth <= 0 || naturalHeight <= 0) return "natural"
  return naturalHeight / naturalWidth > TRADE_SCREENSHOT_TALL_RATIO
    ? "tall-crop"
    : "natural"
}
