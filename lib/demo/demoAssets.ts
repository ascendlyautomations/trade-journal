type ChartOutcome = "win" | "loss" | "breakeven"

type DemoChartScreenshot = {
  path: string
  direction: "Long" | "Short"
  outcome: ChartOutcome
}

/**
 * Sole source of demo chart imagery (trades, stories, feed previews, profiles, reels).
 * To add a new screenshot: drop the file in `public/images/` and append an entry here.
 */
export const DEMO_CHART_SCREENSHOTS: readonly DemoChartScreenshot[] = [
  { path: "/images/3.9.2026(Short)0.png", direction: "Short", outcome: "breakeven" },
  { path: "/images/3.9.2026(Short)987.65.png", direction: "Short", outcome: "win" },
  { path: "/images/3.10.2026(Long)0.PNG", direction: "Long", outcome: "breakeven" },
  { path: "/images/3.11.2026(Short)150.PNG", direction: "Short", outcome: "win" },
  { path: "/images/3.11.2026(Short)-185.png", direction: "Short", outcome: "loss" },
  { path: "/images/3.12.2026(Short)831.png", direction: "Short", outcome: "win" },
  { path: "/images/3.13.2026(Short)2400.png", direction: "Short", outcome: "win" },
  { path: "/images/3.23.2026(Long)500.png", direction: "Long", outcome: "win" },
  { path: "/images/Screenshot 2026-07-01 204116.png", direction: "Short", outcome: "loss" },
  { path: "/images/Screenshot 2026-07-01 204216.png", direction: "Short", outcome: "win" },
  { path: "/images/Screenshot 2026-07-01 204242.png", direction: "Short", outcome: "loss" },
  { path: "/images/Screenshot 2026-07-01 204314.png", direction: "Long", outcome: "win" },
] as const

/** Plain path list — derived from {@link DEMO_CHART_SCREENSHOTS}. */
export const DEMO_CHART_IMAGE_PATHS: readonly string[] = DEMO_CHART_SCREENSHOTS.map(
  (chart) => chart.path
)

export type DemoTradeScreenshotOpts = {
  direction?: "Long" | "Short"
  pnl?: number
}

function stableIndex(key: string, length: number): number {
  let hash = 0
  for (let i = 0; i < key.length; i += 1) {
    hash = (hash * 31 + key.charCodeAt(i)) | 0
  }
  return Math.abs(hash) % length
}

function tradeOutcome(pnl: number): ChartOutcome {
  if (pnl > 0) return "win"
  if (pnl < 0) return "loss"
  return "breakeven"
}

function pickChartScreenshot(
  key: string,
  opts?: DemoTradeScreenshotOpts
): string {
  let pool: DemoChartScreenshot[] = [...DEMO_CHART_SCREENSHOTS]

  if (opts?.direction) {
    const byDirection = pool.filter((chart) => chart.direction === opts.direction)
    if (byDirection.length > 0) pool = byDirection
  }

  if (opts?.pnl !== undefined) {
    const outcome = tradeOutcome(opts.pnl)
    const byOutcome = pool.filter((chart) => chart.outcome === outcome)
    if (byOutcome.length > 0) {
      pool = byOutcome
    } else if (outcome === "loss" && opts.direction === "Long") {
      const breakeven = pool.filter((chart) => chart.outcome === "breakeven")
      if (breakeven.length > 0) pool = breakeven
    } else if (outcome === "win") {
      const wins = pool.filter((chart) => chart.outcome === "win")
      if (wins.length > 0) pool = wins
    } else if (outcome === "loss") {
      const losses = pool.filter((chart) => chart.outcome === "loss")
      if (losses.length > 0) pool = losses
    }
  }

  return pool[stableIndex(key, pool.length)]!.path
}

/** Pick a chart screenshot from the shared demo pool. */
export function demoChartImageUrl(
  key: string,
  opts?: DemoTradeScreenshotOpts
): string {
  return pickChartScreenshot(key, opts)
}

export function demoTradeScreenshotUrl(
  tradeId: string,
  opts?: DemoTradeScreenshotOpts
): string {
  return demoChartImageUrl(tradeId, opts)
}

export function demoStoryImageUrl(storyId: string): string {
  return demoChartImageUrl(`story-${storyId}`)
}

export function demoPostImageUrl(postId: string): string {
  return demoChartImageUrl(`post-${postId}`)
}

/** @deprecated Use {@link demoChartImageUrl} — kept for existing demo fixture imports. */
export function demoStaticImageUrl(key: string): string {
  return demoChartImageUrl(key)
}
