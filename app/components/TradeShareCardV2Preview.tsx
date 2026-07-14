"use client"

import { useMemo, useState } from "react"
import TradeShareCardV2, {
  TRADE_SHARE_V2_SQUARE_SIZE,
  TRADE_SHARE_V2_STORY_SIZE,
  type TradeShareCardV2Trade,
} from "./TradeShareCardV2"

export const TRADE_SHARE_V2_MOCK_WIN: TradeShareCardV2Trade = {
  ticker: "NQ",
  pnl: 1247.5,
  rr: 2.4,
  direction: "Long",
  entry_price: 21450,
  exit_price: 21512,
  exit_time: "2026-03-22T14:32:00-04:00",
}

export const TRADE_SHARE_V2_MOCK_LOSS: TradeShareCardV2Trade = {
  ticker: "ES",
  pnl: -680,
  rr: 0.8,
  direction: "Short",
  entry_price: 5820,
  exit_price: 5834,
  exit_time: "2026-03-21T10:15:00-04:00",
}

const MOCK_PROFILE = { username: "nicktrades" }

type MockPreset = "win" | "loss"

function CardFrame({
  title,
  exportLabel,
  children,
}: {
  title: string
  exportLabel: string
  children: React.ReactNode
}) {
  return (
    <section className="flex flex-col items-center gap-4">
      <div className="text-center">
        <h2 className="text-lg font-semibold text-white">{title}</h2>
        <p className="mt-1 text-sm text-gray-400">{exportLabel}</p>
      </div>
      <div className="overflow-hidden rounded-lg shadow-2xl ring-1 ring-white/10">
        {children}
      </div>
    </section>
  )
}

export default function TradeShareCardV2Preview() {
  const [preset, setPreset] = useState<MockPreset>("win")

  const trade = useMemo(
    () => (preset === "win" ? TRADE_SHARE_V2_MOCK_WIN : TRADE_SHARE_V2_MOCK_LOSS),
    [preset]
  )

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <header className="mb-10 text-center">
        <p className="text-xs font-semibold uppercase tracking-[0.28em] text-cyan-400/80">
          Preview only, not wired to export
        </p>
        <h1 className="mt-2 text-3xl font-bold text-white">
          Trade Share Card V2
        </h1>
        <p className="mx-auto mt-3 max-w-xl text-sm leading-relaxed text-gray-400">
          Layout mockup at half-scale design canvas. Existing download flow still
          uses <code className="text-cyan-200/90">TradeShareCard</code> v1.
        </p>
      </header>

      <div className="mb-10 flex flex-wrap items-center justify-center gap-3">
        <span className="text-sm text-gray-500">Mock trade:</span>
        {(["win", "loss"] as const).map((key) => (
          <button
            key={key}
            type="button"
            onClick={() => setPreset(key)}
            className={`rounded-full border px-4 py-2 text-sm font-semibold transition ${
              preset === key
                ? "border-cyan-400/50 bg-cyan-500/20 text-cyan-100"
                : "border-white/10 bg-white/5 text-gray-300 hover:bg-white/10"
            }`}
          >
            {key === "win" ? "Winning NQ" : "Losing ES"}
          </button>
        ))}
      </div>

      <div className="flex flex-col items-center gap-16 lg:flex-row lg:items-start lg:justify-center lg:gap-12">
        <CardFrame
          title="Square"
          exportLabel={`${TRADE_SHARE_V2_SQUARE_SIZE.width}×${TRADE_SHARE_V2_SQUARE_SIZE.height} canvas → 1080×1080 @2× export`}
        >
          <TradeShareCardV2
            variant="square"
            trade={trade}
            profile={MOCK_PROFILE}
          />
        </CardFrame>

        <CardFrame
          title="Story"
          exportLabel={`${TRADE_SHARE_V2_STORY_SIZE.width}×${TRADE_SHARE_V2_STORY_SIZE.height} canvas → 1080×1920 @2× export`}
        >
          <TradeShareCardV2
            variant="story"
            trade={trade}
            profile={MOCK_PROFILE}
          />
        </CardFrame>
      </div>

      <aside className="mx-auto mt-14 max-w-2xl rounded-xl border border-white/10 bg-white/[0.03] p-5 text-sm text-gray-400">
        <p className="font-semibold text-gray-200">Included in mockup</p>
        <ul className="mt-2 list-inside list-disc space-y-1">
          <li>@username, symbol, large P&amp;L, long/short pill, RR, date</li>
          <li>TradeTraxs logo + footer tagline</li>
          <li>Win/loss background tint (no blur, export-safe CSS)</li>
        </ul>
        <p className="mt-4 text-xs text-gray-500">
          Approve layout here before swapping into{" "}
          <code className="text-gray-400">ShareTradeButton</code> export path.
        </p>
      </aside>
    </div>
  )
}
