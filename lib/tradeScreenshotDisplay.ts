/** Max rendered height for content images in feed thumbnails. */
export const TRADE_SCREENSHOT_MAX_HEIGHT_PX = 440

/**
 * Previous Trades-page Tailwind cap. Live cards use ContentMediaPreview
 * (520px desktop ceiling) instead of this class.
 */
export const TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS = "max-h-[396px]"

/** @deprecated Use TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS — height is a max, not forced. */
export const TRADE_PAGE_SCREENSHOT_PREVIEW_HEIGHT_PX = 396

export type TradeScreenshotDisplayMode = "fit" | "fill"

/** Default for existing trades and new uploads — show the entire saved image. */
export const DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE: TradeScreenshotDisplayMode =
  "fit"

export function resolveTradeScreenshotDisplayMode(
  raw: unknown
): TradeScreenshotDisplayMode {
  return String(raw ?? "")
    .trim()
    .toLowerCase() === "fill"
    ? "fill"
    : "fit"
}

/** Tailwind object-fit class for trade screenshot previews. */
export function tradeScreenshotObjectFitClass(
  mode: TradeScreenshotDisplayMode = DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE
): string {
  return mode === "fill" ? "object-cover" : "object-contain"
}
