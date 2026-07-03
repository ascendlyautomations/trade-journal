"use client"

import { useState } from "react"
import {
  LANDING_CARD_FULL,
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_LEAD_GAP,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_CONTENT_GAP,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
  LANDING_TITLE_GRADIENT,
} from "@/lib/landingPageUi"
import {
  comparisonStateEmoji,
  comparisonStateLabel,
  getComparisonCellState,
  LANDING_COMPARISON_COLUMNS,
  LANDING_COMPARISON_MOBILE_PREVIEW_COUNT,
  LANDING_COMPARISON_ROWS,
  LANDING_COMPARISON_SUBTITLE,
  type ComparisonTriState,
  type LandingComparisonRow,
} from "@/lib/landingComparison"

function Cell({ state }: { state: ComparisonTriState }) {
  return (
    <span className="text-base leading-none" aria-hidden>
      {comparisonStateEmoji(state)}
    </span>
  )
}

function ComparisonMobileCard({ row }: { row: LandingComparisonRow }) {
  return (
    <article
      className={`${LANDING_CARD_FULL} overflow-hidden p-4`}
      aria-label={`${row.feature} comparison`}
    >
      <h3 className="text-sm font-semibold leading-snug text-white">{row.feature}</h3>
      <dl className="mt-3 divide-y divide-white/10">
        {LANDING_COMPARISON_COLUMNS.map((col) => {
          const state = getComparisonCellState(row, col.key)
          return (
            <div
              key={col.key}
              className={`flex items-center justify-between gap-3 py-2.5 ${
                col.highlight ? "rounded-md bg-emerald-500/[0.06] px-2 -mx-1" : ""
              }`}
            >
              <dt
                className={`min-w-0 text-sm ${
                  col.highlight ? "font-medium text-emerald-300" : "text-gray-400"
                }`}
              >
                {col.label}
              </dt>
              <dd className="flex shrink-0 items-center gap-1.5 text-sm text-gray-300">
                <span aria-hidden>{comparisonStateEmoji(state)}</span>
                <span>{comparisonStateLabel(state)}</span>
              </dd>
            </div>
          )
        })}
      </dl>
    </article>
  )
}

export default function LandingComparisonSection() {
  const [mobileExpanded, setMobileExpanded] = useState(false)

  const mobileVisibleRows = mobileExpanded
    ? LANDING_COMPARISON_ROWS
    : LANDING_COMPARISON_ROWS.slice(0, LANDING_COMPARISON_MOBILE_PREVIEW_COUNT)

  const hasMoreMobileRows =
    LANDING_COMPARISON_ROWS.length > LANDING_COMPARISON_MOBILE_PREVIEW_COUNT

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
          <p className={`${LANDING_LEAD} mx-auto max-w-2xl ${LANDING_LEAD_GAP}`}>
            {LANDING_COMPARISON_SUBTITLE}
          </p>
        </div>

        <div
          className={`${LANDING_SECTION_CONTENT_GAP} hidden overflow-hidden rounded-2xl border border-white/10 bg-white/[0.04] shadow-lg shadow-black/25 backdrop-blur-md md:block`}
        >
          <table className="w-full border-collapse text-left text-sm">
            <thead>
              <tr className="border-b border-white/10">
                <th
                  scope="col"
                  className="px-4 py-4 text-xs font-semibold uppercase tracking-wide text-gray-500"
                >
                  Feature
                </th>
                {LANDING_COMPARISON_COLUMNS.map((col) => (
                  <th
                    key={col.key}
                    scope="col"
                    className={`border-l border-white/10 px-4 py-4 text-center text-xs font-semibold md:text-sm ${
                      col.highlight ? "bg-emerald-500/[0.06] text-emerald-300" : "text-gray-400"
                    }`}
                  >
                    {col.label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {LANDING_COMPARISON_ROWS.map((row) => (
                <tr key={row.id} className="border-b border-white/10 last:border-b-0">
                  <th
                    scope="row"
                    className="px-4 py-3.5 text-sm font-normal text-gray-300"
                  >
                    {row.feature}
                  </th>
                  {LANDING_COMPARISON_COLUMNS.map((col) => (
                    <td
                      key={col.key}
                      className={`border-l border-white/10 px-4 py-3.5 text-center align-middle ${
                        col.highlight ? "bg-emerald-500/[0.04]" : ""
                      }`}
                    >
                      <Cell state={getComparisonCellState(row, col.key)} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div
          className={`${LANDING_SECTION_CONTENT_GAP} flex flex-col gap-3 md:hidden`}
          role="list"
          aria-label="Feature comparison"
        >
          {mobileVisibleRows.map((row) => (
            <div key={row.id} role="listitem">
              <ComparisonMobileCard row={row} />
            </div>
          ))}

          {hasMoreMobileRows ? (
            <button
              type="button"
              onClick={() => setMobileExpanded((open) => !open)}
              className="mt-1 w-full rounded-xl border border-white/10 bg-white/[0.04] px-4 py-3 text-sm font-medium text-gray-300 transition hover:border-white/20 hover:bg-white/[0.08] hover:text-white"
              aria-expanded={mobileExpanded}
            >
              {mobileExpanded ? "Show Less" : "Show More Comparisons ↓"}
            </button>
          ) : null}
        </div>

        <p className="mx-auto mt-4 max-w-3xl text-center text-xs leading-relaxed text-gray-500 md:mt-6">
          Feature availability based on publicly available information and may vary by platform,
          plan, or configuration.
        </p>
      </div>
    </section>
  )
}
