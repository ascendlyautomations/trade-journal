"use client"

import {
  LANDING_HEADLINE_SM,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
  LANDING_TITLE_GRADIENT,
} from "@/lib/landingPageUi"

type TriState = "full" | "partial" | "none"

type CompareRow = {
  feature: string
  tt: TriState
  tz: TriState
  ts: TriState
  excel: TriState
  discord: TriState
}

function emojiFor(s: TriState): string {
  if (s === "full") return "✅"
  if (s === "partial") return "⚠️"
  return "❌"
}

function Cell({ state }: { state: TriState }) {
  return (
    <span className="text-base leading-none" aria-hidden>
      {emojiFor(state)}
    </span>
  )
}

const ROWS: CompareRow[] = [
  { feature: "Trade Journal", tt: "full", tz: "full", ts: "full", excel: "partial", discord: "none" },
  { feature: "Analytics", tt: "full", tz: "full", ts: "full", excel: "partial", discord: "none" },
  { feature: "Community", tt: "full", tz: "none", ts: "none", excel: "none", discord: "full" },
  { feature: "Trade Rooms", tt: "full", tz: "none", ts: "none", excel: "none", discord: "partial" },
  { feature: "Reels", tt: "full", tz: "none", ts: "none", excel: "none", discord: "none" },
  { feature: "Achievements", tt: "full", tz: "none", ts: "none", excel: "none", discord: "none" },
  { feature: "AI Trade Analysis", tt: "full", tz: "partial", ts: "partial", excel: "none", discord: "none" },
  { feature: "Trading Calendar", tt: "full", tz: "full", ts: "partial", excel: "none", discord: "none" },
  { feature: "Prop Firm Mode", tt: "full", tz: "partial", ts: "partial", excel: "none", discord: "none" },
  { feature: "Social Feed", tt: "full", tz: "none", ts: "none", excel: "none", discord: "partial" },
  { feature: "Leaderboards", tt: "full", tz: "none", ts: "none", excel: "none", discord: "none" },
  {
    feature: "Mobile Experience",
    tt: "partial",
    tz: "partial",
    ts: "partial",
    excel: "none",
    discord: "partial",
  },
]

const COLUMNS = [
  { key: "tt" as const, label: "TradeTraxs", highlight: true },
  { key: "tz" as const, label: "TradeZella", highlight: false },
  { key: "ts" as const, label: "TraderSync", highlight: false },
  { key: "excel" as const, label: "Excel", highlight: false },
  { key: "discord" as const, label: "Discord", highlight: false },
]

export default function LandingComparisonSection() {
  return (
    <section
      id="compare"
      className={`relative z-10 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="compare-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div className="mx-auto max-w-3xl text-center">
          <h2 id="compare-heading" className={LANDING_HEADLINE_SM}>
            Nothing Else{" "}
            <span className={LANDING_TITLE_GRADIENT}>Comes Close</span>
          </h2>
        </div>

        <div className="mt-14 overflow-x-auto rounded-2xl border border-white/10 bg-white/[0.04] shadow-lg shadow-black/25 backdrop-blur-md [-webkit-overflow-scrolling:touch]">
          <table className="w-full min-w-[760px] border-collapse text-left text-sm">
            <thead>
              <tr className="border-b border-white/10">
                <th
                  scope="col"
                  className="sticky left-0 z-[1] min-w-[160px] bg-[#0a0f1c]/95 px-4 py-4 text-xs font-semibold uppercase tracking-wide text-gray-500 backdrop-blur-sm md:static md:bg-transparent"
                >
                  Feature
                </th>
                {COLUMNS.map((col) => (
                  <th
                    key={col.key}
                    scope="col"
                    className={`min-w-[100px] border-l border-white/10 px-3 py-4 text-center text-xs font-semibold md:px-4 md:text-sm ${
                      col.highlight ? "bg-emerald-500/[0.06] text-emerald-300" : "text-gray-400"
                    }`}
                  >
                    {col.label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {ROWS.map((row) => (
                <tr key={row.feature} className="border-b border-white/10 last:border-b-0">
                  <th
                    scope="row"
                    className="sticky left-0 z-[1] bg-[#0a0f1c]/95 px-4 py-3.5 text-sm font-normal text-gray-300 backdrop-blur-sm md:static md:bg-transparent"
                  >
                    {row.feature}
                  </th>
                  {COLUMNS.map((col) => (
                    <td
                      key={col.key}
                      className={`border-l border-white/10 px-3 py-3.5 text-center align-middle md:px-4 ${
                        col.highlight ? "bg-emerald-500/[0.04]" : ""
                      }`}
                    >
                      <Cell state={row[col.key]} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <p className="mx-auto mt-6 max-w-3xl text-center text-xs leading-relaxed text-gray-500">
          Feature availability based on publicly available information and may vary by platform,
          plan, or configuration.
        </p>
      </div>
    </section>
  )
}
