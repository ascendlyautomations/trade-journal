/** Fixed 4:3 frame used across trade cards (profile, feed, journal). */
export const TRADE_IMAGE_ASPECT = 4 / 3

export const TRADE_IMAGE_OUTPUT_WIDTH = 1200
export const TRADE_IMAGE_OUTPUT_HEIGHT = 900

/** Letterbox fill for Fit mode — transparent so images blend with card/modal surfaces. */
export const TRADE_IMAGE_LETTERBOX_COLOR = "transparent"

/**
 * Normalized media frame matching upload cropper output (4:3).
 * Homepage featured cards and similar surfaces share this so heights stay equal.
 */
export const TRADE_IMAGE_MEDIA_FRAME_CLASS =
  "relative aspect-[4/3] w-full overflow-hidden bg-black/20"

/** Full saved crop inside {@link TRADE_IMAGE_MEDIA_FRAME_CLASS} — contain, no second crop. */
export const TRADE_IMAGE_MEDIA_FRAME_IMG_CLASS =
  "absolute inset-0 h-full w-full object-contain object-center"
