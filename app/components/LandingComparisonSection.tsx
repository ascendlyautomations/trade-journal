"use client"

type TriState = "full" | "partial" | "none"

type QuadRow = {
  feature: string
  tt: TriState
  tz: TriState
  tv: TriState
  ew: TriState
}

type UiRow = {
  feature: string
  kind: "text"
  tt: string
  tz: string
  tv: string
  ew: string
}

type Row = QuadRow | UiRow

function isQuadRow(row: Row): row is QuadRow {
  return !("kind" in row && row.kind === "text")
}

function emojiFor(s: TriState): string {
  if (s === "full") return "✅"
  if (s === "partial") return "⚠️"
  return "❌"
}

function QuadCell({ state }: { state: TriState }) {
  return (
    <span className="tabular-nums text-[15px] leading-none" aria-hidden>
      {emojiFor(state)}
    </span>
  )
}

const ROWS: Row[] = [
  {
    feature: "Trade Logging",
    tt: "full",
    tz: "full",
    tv: "full",
    ew: "full",
  },
  {
    feature: "Basic Analytics (PnL, Win Rate)",
    tt: "full",
    tz: "full",
    tv: "full",
    ew: "full",
  },
  {
    feature: "Advanced Analytics (Sessions, RR, Trends)",
    tt: "full",
    tz: "partial",
    tv: "partial",
    ew: "partial",
  },
  {
    feature: "Trading Calendar",
    tt: "full",
    tz: "full",
    tv: "none",
    ew: "none",
  },
  {
    feature: "Screenshot Uploads",
    tt: "full",
    tz: "full",
    tv: "none",
    ew: "none",
  },
  {
    feature: "AI Trade Analysis",
    tt: "full",
    tz: "none",
    tv: "none",
    ew: "none",
  },
  {
    feature: "Community Feed",
    tt: "full",
    tz: "none",
    tv: "none",
    ew: "none",
  },
  {
    feature: "Public Profiles",
    tt: "full",
    tz: "none",
    tv: "none",
    ew: "none",
  },
  {
    feature: "Leaderboards",
    tt: "full",
    tz: "none",
    tv: "none",
    ew: "none",
  },
  {
    feature: "Mobile Experience",
    tt: "full",
    tz: "partial",
    tv: "partial",
    ew: "partial",
  },
  {
    feature: "UI / Ease of Use",
    kind: "text",
    tt: "Modern",
    tz: "Varies",
    tv: "Varies",
    ew: "Varies",
  },
]

export default function LandingComparisonSection() {
  return (
    <section
      id="compare"
      className="relative z-10 mx-auto max-w-6xl border-t border-white/10 px-6 py-24 text-center"
      aria-labelledby="compare-heading"
    >
      <div className="mx-auto mb-12 max-w-3xl space-y-3 md:mb-14">
        <h2
          id="compare-heading"
          className="text-4xl font-extrabold tracking-tight text-white drop-shadow-lg"
        >
          How TradeTraxs Compares to Leading Trading Journals
        </h2>
        <p className="text-base leading-relaxed text-gray-400">
          A fair comparison of core features across popular platforms.
        </p>
      </div>

      <div className="overflow-x-auto rounded-2xl border border-white/10 bg-white/5 shadow-lg shadow-black/15 backdrop-blur-md [-webkit-overflow-scrolling:touch]">
        <table className="w-full min-w-[720px] border-collapse text-left text-sm">
          <thead>
            <tr className="border-b border-white/10">
              <th
                scope="col"
                className="sticky left-0 z-[1] w-[28%] min-w-[140px] bg-[#0f172a]/95 px-4 py-3.5 text-xs font-semibold uppercase tracking-wide text-gray-400 backdrop-blur-sm md:static md:bg-transparent md:px-4 md:py-4 md:normal-case md:tracking-normal md:text-gray-200">
                Feature
              </th>
              <th
                scope="col"
                className="min-w-[100px] border-l border-white/10 bg-white/10 px-3 py-3.5 text-center text-xs font-semibold text-emerald-300 shadow-[inset_0_0_24px_rgba(16,185,129,0.07)] md:px-4 md:py-4 md:text-sm"
              >
                TradeTraxs
              </th>
              <th
                scope="col"
                className="min-w-[100px] border-l border-white/10 bg-white/[0.04] px-3 py-3.5 text-center text-xs font-semibold text-gray-300 md:px-4 md:py-4 md:text-sm"
              >
                TradeZella
              </th>
              <th
                scope="col"
                className="min-w-[100px] border-l border-white/10 bg-white/[0.04] px-3 py-3.5 text-center text-xs font-semibold text-gray-300 md:px-4 md:py-4 md:text-sm"
              >
                Tradervue
              </th>
              <th
                scope="col"
                className="min-w-[100px] border-l border-white/10 bg-white/[0.04] px-3 py-3.5 text-center text-xs font-semibold text-gray-300 md:px-4 md:py-4 md:text-sm"
              >
                Edgewonk
              </th>
            </tr>
          </thead>
          <tbody>
            {ROWS.map((row) =>
              isQuadRow(row) ? (
                <tr key={row.feature} className="border-b border-white/10 last:border-b-0">
                  <th
                    scope="row"
                    className="sticky left-0 z-[1] bg-[#0f172a]/90 px-4 py-3 align-middle text-xs font-normal leading-snug text-gray-300 backdrop-blur-sm md:static md:bg-white/[0.02] md:px-4 md:py-3.5 md:text-sm"
                  >
                    {row.feature}
                  </th>
                  <td className="border-l border-white/10 bg-white/10 px-3 py-3 text-center align-middle shadow-[inset_0_0_18px_rgba(52,211,153,0.05)] md:px-4 md:py-3.5">
                    <QuadCell state={row.tt} />
                  </td>
                  <td className="border-l border-white/10 bg-white/[0.02] px-3 py-3 text-center align-middle md:px-4 md:py-3.5">
                    <QuadCell state={row.tz} />
                  </td>
                  <td className="border-l border-white/10 bg-white/[0.02] px-3 py-3 text-center align-middle md:px-4 md:py-3.5">
                    <QuadCell state={row.tv} />
                  </td>
                  <td className="border-l border-white/10 bg-white/[0.02] px-3 py-3 text-center align-middle md:px-4 md:py-3.5">
                    <QuadCell state={row.ew} />
                  </td>
                </tr>
              ) : (
                <tr key={row.feature} className="border-b border-white/10 last:border-b-0">
                  <th
                    scope="row"
                    className="sticky left-0 z-[1] bg-[#0f172a]/90 px-4 py-3 align-middle text-xs font-normal leading-snug text-gray-300 backdrop-blur-sm md:static md:bg-white/[0.02] md:px-4 md:py-3.5 md:text-sm"
                  >
                    {row.feature}
                  </th>
                  <td className="border-l border-white/10 bg-white/10 px-3 py-3 text-center align-middle text-xs font-medium text-emerald-200 md:px-4 md:py-3.5 md:text-sm">
                    {row.tt}
                  </td>
                  <td className="border-l border-white/10 bg-white/[0.02] px-3 py-3 text-center align-middle text-xs text-gray-400 md:px-4 md:py-3.5 md:text-sm">
                    {row.tz}
                  </td>
                  <td className="border-l border-white/10 bg-white/[0.02] px-3 py-3 text-center align-middle text-xs text-gray-400 md:px-4 md:py-3.5 md:text-sm">
                    {row.tv}
                  </td>
                  <td className="border-l border-white/10 bg-white/[0.02] px-3 py-3 text-center align-middle text-xs text-gray-400 md:px-4 md:py-3.5 md:text-sm">
                    {row.ew}
                  </td>
                </tr>
              )
            )}
          </tbody>
        </table>
      </div>

      <p className="mx-auto mt-8 max-w-3xl px-1 text-center text-[11px] leading-relaxed text-gray-500 md:text-xs">
        Feature availability based on publicly available information and may vary by platform or subscription plan.
      </p>
    </section>
  )
}
