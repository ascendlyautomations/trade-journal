"use client"

import type { ReactNode } from "react"
import type { PropFirmDesktopModel } from "@/app/components/propfirm/PropFirmDesktopView"
import PropfirmProfitTargetProgressBar from "@/app/components/propfirm/PropfirmProfitTargetProgressBar"
import { formatPropfirmUsd, type TrailingDrawdownResult } from "@/lib/propfirmMetrics"
import { formatPnlCurrency } from "@/lib/formatMoney"

type MobileWebPropFirmSurfaceProps = {
  model: PropFirmDesktopModel | null
  selector: ReactNode
  actions: ReactNode
  equity: ReactNode
  trailing: TrailingDrawdownResult
  startingBalance: number
  dailyRows: [string, number][]
  empty: ReactNode
}

const CARD =
  "rounded-[14px] border border-white/10 bg-white/5 px-3.5 py-3"
const LABEL =
  "text-[11px] text-[color:var(--tt-text-tertiary,#a8b3c2)]"
const VALUE =
  "text-[15px] font-semibold tabular-nums text-[color:var(--tt-text,#f0f3f6)]"
const TITLE =
  "text-[13px] font-semibold uppercase tracking-[0.04em] text-[color:var(--tt-text-tertiary,#a8b3c2)]"

function signedUsd(value: number): string {
  const formatted = formatPropfirmUsd(value)
  if (value > 0) return `+${formatted}`
  return formatted
}

function pnlClass(value: number): string {
  if (value > 0) return "text-[color:var(--tt-positive,#3ddc97)]"
  if (value < 0) return "text-[color:var(--tt-negative,#ff7b72)]"
  return "text-[color:var(--tt-text,#f0f3f6)]"
}

function statusClass(tone: PropFirmDesktopModel["statusTone"]): string {
  if (tone === "good") return "bg-emerald-500/15 text-emerald-300"
  if (tone === "bad") return "bg-red-500/15 text-red-400"
  if (tone === "warn") return "bg-amber-500/15 text-amber-200"
  return "bg-white/10 text-[color:var(--tt-text-muted,#c0cad6)]"
}

function mark(state: "met" | "progress" | "failed"): string {
  if (state === "met") return "✓"
  if (state === "failed") return "✕"
  return "○"
}

function markClass(state: "met" | "progress" | "failed"): string {
  if (state === "met") return "text-emerald-300"
  if (state === "failed") return "text-red-400"
  return "text-amber-200"
}

export default function MobileWebPropFirmSurface({
  model,
  selector,
  actions,
  equity,
  trailing,
  startingBalance,
  dailyRows,
  empty,
}: MobileWebPropFirmSurfaceProps) {
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-2.5">
        <div className="min-w-0">{selector}</div>
        <div className="flex flex-wrap items-center gap-2">{actions}</div>
      </div>

      {model ? <AccountBody model={model} trailing={trailing} startingBalance={startingBalance} equity={equity} /> : null}

      <section>
        <div className="mb-2 flex items-end justify-between gap-2">
          <div>
            <h2 className={TITLE}>Daily Performance</h2>
            <p className="mt-0.5 text-[12px] text-[color:var(--tt-text-muted,#c0cad6)]">
              Lifetime, aggregated by trading day
            </p>
          </div>
          <span className="text-[11px] tabular-nums text-[color:var(--tt-text-tertiary,#a8b3c2)]">
            {dailyRows.length} days
          </span>
        </div>
        <div className={`${CARD} max-h-72 space-y-0 overflow-y-auto p-0`}>
          {dailyRows.length > 0 ? (
            dailyRows.map(([date, pnl]) => (
              <div
                key={date}
                className="flex items-center justify-between gap-3 border-b border-white/10 px-3.5 py-2.5 last:border-b-0"
              >
                <span className="text-[13px] text-[color:var(--tt-text-muted,#c0cad6)]">
                  {date}
                </span>
                <span className={`text-[13px] font-semibold tabular-nums ${pnlClass(pnl)}`}>
                  {formatPnlCurrency(pnl, {
                    minimumFractionDigits: 0,
                    maximumFractionDigits: 2,
                  })}
                </span>
              </div>
            ))
          ) : (
            <p className="px-3.5 py-6 text-center text-[13px] text-[color:var(--tt-text-muted,#c0cad6)]">
              No daily performance yet.
            </p>
          )}
        </div>
      </section>

      {empty}
    </div>
  )
}

function AccountBody({
  model,
  trailing,
  startingBalance,
  equity,
}: {
  model: PropFirmDesktopModel
  trailing: TrailingDrawdownResult
  startingBalance: number
  equity: ReactNode
}) {
  const requirements: { state: "met" | "progress" | "failed"; title: string; detail: string }[] =
    []
  if (model.profitTarget > 0) {
    requirements.push({
      state: model.profitPassed ? "met" : "progress",
      title: "Profit target",
      detail: `${signedUsd(model.cyclePnl)} / ${formatPropfirmUsd(model.profitTarget)}`,
    })
  }
  if (model.winningDaysRequired) {
    requirements.push({
      state: model.winningDaysMet ? "met" : "progress",
      title: "Winning days",
      detail: `${model.winningDays} / ${model.winningDaysTarget}`,
    })
  }
  if (model.consistencyRequired) {
    requirements.push({
      state: model.consistencyMet ? "met" : "progress",
      title: "Consistency",
      detail: `${formatPropfirmUsd(model.biggestWin)} / ${formatPropfirmUsd(model.allowedMax)}`,
    })
  }
  if (model.maxDdLimit > 0) {
    requirements.push({
      state: model.drawdownUsed > model.maxDdLimit ? "failed" : "met",
      title: "Max drawdown",
      detail: `${formatPropfirmUsd(model.drawdownUsed)} / ${formatPropfirmUsd(model.maxDdLimit)}`,
    })
    requirements.push({
      state: model.trailingBreached ? "failed" : "met",
      title: "Trailing drawdown",
      detail: model.trailingBreached
        ? "Breached"
        : `${formatPropfirmUsd(model.distanceToDD)} room`,
    })
  }
  if (model.dailyLimit > 0) {
    requirements.push({
      state: model.dailyBreached ? "failed" : "met",
      title: "Daily loss",
      detail: model.dailyBreached
        ? "Breached"
        : `${formatPropfirmUsd(model.worstDailyLossUsed)} / ${formatPropfirmUsd(model.dailyLimit)}`,
    })
  }

  return (
    <>
      <section className={CARD}>
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate text-[17px] font-semibold text-[color:var(--tt-text,#f0f3f6)]">
              {model.accountName}
            </p>
            <p className="mt-0.5 text-[12px] text-[color:var(--tt-text-muted,#c0cad6)]">
              {model.phase} · {model.sizeLabel}
            </p>
          </div>
          <span
            className={`shrink-0 rounded-full px-2 py-1 text-[11px] font-semibold ${statusClass(model.statusTone)}`}
          >
            {model.statusLabel}
          </span>
        </div>
        <div className="mt-3 grid grid-cols-3 gap-2">
          <HeroMetric label="Balance" value={model.balanceLabel} />
          <HeroMetric
            label="Cycle P&L"
            value={signedUsd(model.cyclePnl)}
            valueClassName={pnlClass(model.cyclePnl)}
          />
          <HeroMetric
            label="To floor"
            value={formatPropfirmUsd(model.distanceToDD)}
            valueClassName={
              model.distanceDanger || model.distanceToDD < 0
                ? "text-[color:var(--tt-negative,#ff7b72)]"
                : "text-[color:var(--tt-positive,#3ddc97)]"
            }
          />
        </div>
      </section>

      <div className="grid grid-cols-2 gap-2">
        <div className={CARD}>
          <p className={LABEL}>Current cycle P&L</p>
          <p className={`mt-1 ${VALUE} ${pnlClass(model.cyclePnl)}`}>
            {signedUsd(model.cyclePnl)}
          </p>
        </div>
        {model.winningDaysRequired ? (
          <div className={CARD}>
            <p className={LABEL}>Cycle winning days</p>
            <p className={`mt-1 ${VALUE} ${model.winningDaysMet ? "text-emerald-300" : "text-amber-200"}`}>
              {model.winningDays}/{model.winningDaysTarget}
            </p>
          </div>
        ) : (
          <div className={CARD}>
            <p className={LABEL}>Lifetime P&L</p>
            <p className={`mt-1 ${VALUE} ${pnlClass(model.lifetimePnl)}`}>
              {signedUsd(model.lifetimePnl)}
            </p>
          </div>
        )}
        {model.isFunded ? (
          <div className={`${CARD} col-span-2`}>
            <p className={LABEL}>Payout total ({model.payoutCount})</p>
            <p className={`mt-1 ${VALUE}`}>{model.payoutTotalLabel}</p>
          </div>
        ) : null}
      </div>

      {equity}

      {requirements.length > 0 ? (
        <section>
          <h2 className={`${TITLE} mb-2`}>At a glance</h2>
          <div className={CARD}>
            {requirements.map((row) => (
              <div
                key={row.title}
                className="flex items-baseline justify-between gap-3 border-b border-white/10 py-2.5 last:border-b-0"
              >
                <span className="flex min-w-0 items-baseline gap-2">
                  <span className={`w-3 shrink-0 text-[13px] ${markClass(row.state)}`} aria-hidden>
                    {mark(row.state)}
                  </span>
                  <span className="text-[13px] text-[color:var(--tt-text-muted,#c0cad6)]">
                    {row.title}
                  </span>
                </span>
                <span className="shrink-0 text-[13px] font-semibold tabular-nums text-[color:var(--tt-text,#f0f3f6)]">
                  {row.detail}
                </span>
              </div>
            ))}
          </div>
        </section>
      ) : null}

      {model.maxDdLimit > 0 ? (
        <DrawdownCard model={model} trailing={trailing} startingBalance={startingBalance} />
      ) : null}

      <section>
        <h2 className={`${TITLE} mb-2`}>Consistency</h2>
        <div className={CARD}>
          {model.consistencyRequired ? (
            <div className="flex items-center gap-3">
              <ConsistencyRing
                ratio={
                  model.allowedMax > 0
                    ? Math.min(1, Math.max(0, model.biggestWin / model.allowedMax))
                    : 0
                }
                passing={model.consistencyMet}
              />
              <div className="min-w-0">
                <p className="text-[20px] font-bold tabular-nums text-[color:var(--tt-text,#f0f3f6)]">
                  {model.consistencyRuleLabel}
                </p>
                <p className="mt-0.5 text-[12px] text-[color:var(--tt-text-muted,#c0cad6)]">
                  Max single winning trade share of total win profits
                </p>
                <p className="mt-1 text-[12px] text-[color:var(--tt-text-tertiary,#a8b3c2)]">
                  {model.consistencyMet ? "Passing" : "Failing"}
                  {model.biggestWin > 0
                    ? ` · Largest win ${formatPropfirmUsd(model.biggestWin)}`
                    : ""}
                </p>
              </div>
            </div>
          ) : (
            <p className="text-[14px] text-[color:var(--tt-text,#f0f3f6)]">
              No consistency rule
            </p>
          )}
        </div>
      </section>

      <section>
        <h2 className={`${TITLE} mb-2`}>Trading rules</h2>
        <div className={CARD}>
          <RuleRow label="Account size" value={model.sizeLabel} />
          <RuleRow
            label="Consistency"
            value={model.consistencyRequired ? model.consistencyRuleLabel ?? "—" : "Does not apply"}
          />
          <RuleRow
            label="Max drawdown"
            value={model.maxDdLimit > 0 ? formatPropfirmUsd(model.maxDdLimit) : "—"}
          />
          <RuleRow
            label="Daily drawdown"
            value={model.dailyLimit > 0 ? formatPropfirmUsd(model.dailyLimit) : "—"}
          />
          <RuleRow
            label="Profit target"
            value={model.profitTarget > 0 ? formatPropfirmUsd(model.profitTarget) : "—"}
            valueClassName="text-emerald-300"
          />
          <RuleRow
            label="Winning days"
            value={
              model.winningDaysRequired
                ? String(model.winningDaysTarget)
                : "Does not apply"
            }
          />
          {model.winningDayThresholdLabel ? (
            <RuleRow label="Winning day threshold" value={model.winningDayThresholdLabel} />
          ) : null}
        </div>
      </section>

      <section>
        <h2 className={`${TITLE} mb-2`}>
          {model.isFunded ? "Payout path" : "Evaluation path"}
        </h2>
        <div className={CARD}>
          <div className="mb-3">
            <div className="mb-1.5 flex justify-between text-[12px] text-[color:var(--tt-text-muted,#c0cad6)]">
              <span>Profit target (cycle)</span>
              <span
                className={`font-semibold tabular-nums ${
                  model.cyclePnl < 0
                    ? "text-red-400"
                    : model.progressPercent >= 100
                      ? "text-emerald-300"
                      : "text-[color:var(--tt-accent,#4ec4e0)]"
                }`}
              >
                {model.cyclePnl < 0 ? "-" : ""}
                {model.progressPercent.toFixed(0)}%
              </span>
            </div>
            <PropfirmProfitTargetProgressBar
              progressPercent={model.progressPercent}
              negative={model.cyclePnl < 0}
            />
          </div>
          {model.maxDdLimit > 0 ? (
            <div>
              <div className="mb-1.5 flex justify-between text-[12px] text-[color:var(--tt-text-muted,#c0cad6)]">
                <span>Drawdown used (cycle)</span>
                <span
                  className={`font-semibold tabular-nums ${
                    model.ddPercent >= 100 ? "text-red-400" : "text-amber-300"
                  }`}
                >
                  {model.ddPercent.toFixed(0)}%
                </span>
              </div>
              <div className="h-2 w-full overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full bg-red-500"
                  style={{ width: `${Math.min(100, model.ddPercent)}%` }}
                />
              </div>
            </div>
          ) : null}
          {model.warnings.map((warning) => (
            <p
              key={warning}
              className="mt-3 rounded-[10px] bg-red-500/10 px-3 py-2 text-[12px] text-red-400"
            >
              {warning}
            </p>
          ))}
        </div>
      </section>

      {model.isFunded ? (
        <section>
          <h2 className={`${TITLE} mb-2`}>Payouts</h2>
          <div className={CARD}>
            <div className="flex items-end justify-between gap-3">
              <div>
                <p className={LABEL}>Eligibility</p>
                <p
                  className={`mt-0.5 text-[18px] font-bold ${
                    model.payoutReady ? "text-emerald-300" : VALUE
                  }`}
                >
                  {model.payoutFailed ? "Failed" : model.payoutReady ? "Ready" : "Not yet"}
                </p>
              </div>
              <p className="text-[12px] tabular-nums text-[color:var(--tt-text-muted,#c0cad6)]">
                {model.payoutCount} · {model.payoutTotalLabel}
              </p>
            </div>
            {model.payoutHistory.length > 0 ? (
              <ul className="mt-3 divide-y divide-white/10">
                {model.payoutHistory.map((payout) => (
                  <li
                    key={payout.id}
                    className="flex items-center justify-between py-2 text-[13px]"
                  >
                    <span className="text-[color:var(--tt-text-muted,#c0cad6)]">
                      {payout.dateLabel}
                    </span>
                    <span className="font-semibold tabular-nums text-[color:var(--tt-text,#f0f3f6)]">
                      {payout.amountLabel}
                    </span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="mt-2 text-[12px] text-[color:var(--tt-text-muted,#c0cad6)]">
                Recorded payouts will appear here.
              </p>
            )}
          </div>
        </section>
      ) : (
        <p className="text-[12px] text-[color:var(--tt-text-muted,#c0cad6)]">
          Payout recording applies after the account is set to Funded mode.
        </p>
      )}
    </>
  )
}

function HeroMetric({
  label,
  value,
  valueClassName,
}: {
  label: string
  value: string
  valueClassName?: string
}) {
  return (
    <div className="min-w-0">
      <p className={LABEL}>{label}</p>
      <p className={`mt-0.5 truncate text-[13px] font-semibold tabular-nums ${valueClassName ?? "text-[color:var(--tt-text,#f0f3f6)]"}`}>
        {value}
      </p>
    </div>
  )
}

function RuleRow({
  label,
  value,
  valueClassName,
}: {
  label: string
  value: string
  valueClassName?: string
}) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-white/10 py-2 last:border-b-0">
      <span className="text-[13px] text-[color:var(--tt-text-muted,#c0cad6)]">{label}</span>
      <span className={`shrink-0 text-[13px] font-semibold tabular-nums ${valueClassName ?? "text-[color:var(--tt-text,#f0f3f6)]"}`}>
        {value}
      </span>
    </div>
  )
}

function DrawdownCard({
  model,
  trailing,
  startingBalance,
}: {
  model: PropFirmDesktopModel
  trailing: TrailingDrawdownResult
  startingBalance: number
}) {
  const low = Math.min(trailing.drawdownFloor, startingBalance)
  const high = Math.max(trailing.peakBalance, trailing.currentBalance, low + 1)
  const span = Math.max(high - low, 1)
  const floorRatio = Math.min(1, Math.max(0, (trailing.drawdownFloor - low) / span))
  const balanceRatio = Math.min(1, Math.max(0, (trailing.currentBalance - low) / span))

  return (
    <section>
      <h2 className={`${TITLE} mb-2`}>Drawdown</h2>
      <div className={CARD}>
        <RuleRow label="Maximum drawdown" value={formatPropfirmUsd(model.maxDdLimit)} />
        <RuleRow label="Drawdown floor" value={formatPropfirmUsd(trailing.drawdownFloor)} />
        <div className="relative mt-3 h-2.5 overflow-hidden rounded-full bg-white/10">
          <div
            className="absolute inset-y-0 left-0 rounded-full bg-[color:color-mix(in_srgb,var(--tt-accent,#4ec4e0)_40%,transparent)]"
            style={{ width: `${balanceRatio * 100}%` }}
          />
          <div
            className="absolute top-0 h-full w-0.5 bg-amber-300"
            style={{ left: `${floorRatio * 100}%` }}
          />
        </div>
        <div className="mt-1 flex justify-between text-[10px] text-[color:var(--tt-text-tertiary,#a8b3c2)]">
          <span>Floor</span>
          <span>Peak</span>
        </div>
        <RuleRow label="Cycle start" value={formatPropfirmUsd(startingBalance)} />
        <RuleRow label="Peak balance" value={formatPropfirmUsd(trailing.peakBalance)} />
        <RuleRow label="Current balance" value={formatPropfirmUsd(trailing.currentBalance)} />
        {model.trailingBreached ? (
          <p className="mt-2 text-[12px] text-red-400">
            Trailing max drawdown breached (balance below drawdown floor)
          </p>
        ) : null}
      </div>
    </section>
  )
}

function ConsistencyRing({
  ratio,
  passing,
}: {
  ratio: number
  passing: boolean
}) {
  const size = 72
  const stroke = 8
  const radius = (size - stroke) / 2
  const circumference = 2 * Math.PI * radius
  const offset = circumference * (1 - ratio)
  const color = passing ? "var(--tt-positive,#3ddc97)" : "var(--tt-warning,#e3b341)"
  return (
    <svg width={size} height={size} className="shrink-0 -rotate-90" aria-hidden>
      <circle
        cx={size / 2}
        cy={size / 2}
        r={radius}
        fill="none"
        stroke="color-mix(in srgb, var(--tt-text,#f0f3f6) 12%, transparent)"
        strokeWidth={stroke}
      />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={radius}
        fill="none"
        stroke={color}
        strokeWidth={stroke}
        strokeLinecap="round"
        strokeDasharray={circumference}
        strokeDashoffset={offset}
      />
    </svg>
  )
}
