"use client"

import type { ReactNode } from "react"
import PropfirmProfitTargetProgressBar from "@/app/components/propfirm/PropfirmProfitTargetProgressBar"
import { formatPropfirmUsd } from "@/lib/propfirmMetrics"
import { formatPnlCurrency } from "@/lib/formatMoney"

export type PropFirmDesktopPhase = "Eval" | "Funded"

export type PropFirmDesktopModel = {
  accountName: string
  sizeLabel: string
  phase: PropFirmDesktopPhase
  balanceLabel: string
  cyclePnl: number
  lifetimePnl: number
  statusLabel: string
  statusTone: "good" | "warn" | "bad" | "neutral"
  profitTarget: number
  progressPercent: number
  profitPassed: boolean
  maxDdLimit: number
  drawdownUsed: number
  distanceToDD: number
  ddPercent: number
  distanceDanger: boolean
  trailingBreached: boolean
  drawdownFloor: number
  dailyLimit: number
  dailyBreached: boolean
  worstDailyLossUsed: number
  todayPnl: number
  worstDay: number
  consistencyRequired: boolean
  consistencyMet: boolean
  consistencyRuleLabel: string | null
  biggestWin: number
  allowedMax: number
  winningDaysRequired: boolean
  winningDays: number
  winningDaysTarget: number
  winningDaysMet: boolean
  winningDayThresholdLabel: string | null
  isFunded: boolean
  payoutReady: boolean
  payoutFailed: boolean
  payoutCount: number
  payoutTotalLabel: string
  payoutHistory: { id: string; dateLabel: string; amountLabel: string }[]
  dailyRows: [string, number][]
  warnings: string[]
}

type PropFirmDesktopViewProps = {
  model: PropFirmDesktopModel
  selector: ReactNode
  actions: ReactNode
  equity: ReactNode
}

const SURFACE = "rounded-xl border border-white/10 bg-white/5"
const TITLE =
  "text-[11px] font-semibold uppercase tracking-[0.14em] text-blue-300"
const LABEL = "text-xs text-gray-400"
const VALUE = "font-semibold tabular-nums text-white"

function signedUsd(value: number): string {
  const formatted = formatPropfirmUsd(value)
  if (value > 0) return `+${formatted}`
  return formatted
}

function toneClass(tone: "good" | "warn" | "bad" | "neutral"): string {
  if (tone === "good") return "border-emerald-500/35 bg-emerald-500/10 text-emerald-300"
  if (tone === "bad") return "border-red-500/35 bg-red-500/10 text-red-400"
  if (tone === "warn") return "border-amber-500/35 bg-amber-500/10 text-amber-200"
  return "border-white/15 bg-white/5 text-gray-200"
}

function pnlClass(value: number): string {
  if (value > 0) return "text-emerald-300"
  if (value < 0) return "text-red-400"
  return "text-white"
}

function requirementMark(state: "met" | "progress" | "failed"): string {
  if (state === "met") return "✓"
  if (state === "failed") return "!"
  return "•"
}

function requirementClass(state: "met" | "progress" | "failed"): string {
  if (state === "met") return "text-emerald-300"
  if (state === "failed") return "text-red-400"
  return "text-amber-200"
}

function Bar({
  percent,
  className,
}: {
  percent: number
  className: string
}) {
  const width = Math.max(0, Math.min(100, percent))
  return (
    <div className="h-1.5 w-full overflow-hidden rounded-full bg-white/10">
      <div
        className={`h-full rounded-full ${className}`}
        style={{ width: `${width}%` }}
      />
    </div>
  )
}

function Metric({
  label,
  value,
  detail,
  valueClassName,
  children,
}: {
  label: string
  value: string
  detail?: string
  valueClassName?: string
  children?: ReactNode
}) {
  return (
    <div className={`${SURFACE} px-3 py-3`}>
      <p className={LABEL}>{label}</p>
      <p className={`mt-1 text-sm ${VALUE} ${valueClassName ?? ""}`}>{value}</p>
      {detail ? <p className="mt-0.5 text-[11px] text-gray-400">{detail}</p> : null}
      {children ? <div className="mt-2">{children}</div> : null}
    </div>
  )
}

function RequirementRow({
  state,
  title,
  detail,
}: {
  state: "met" | "progress" | "failed"
  title: string
  detail: string
}) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-white/10 py-2.5 last:border-b-0">
      <div className="flex min-w-0 items-baseline gap-2">
        <span className={`w-3 shrink-0 text-sm ${requirementClass(state)}`} aria-hidden>
          {requirementMark(state)}
        </span>
        <span className="truncate text-sm text-gray-200">{title}</span>
      </div>
      <span className={`shrink-0 text-sm ${VALUE}`}>{detail}</span>
    </div>
  )
}

function DetailRow({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-white/10 py-2 last:border-b-0">
      <span className="truncate text-sm text-gray-300">{title}</span>
      <span className={`shrink-0 text-sm ${VALUE}`}>{detail}</span>
    </div>
  )
}

function objectiveFootnote(model: PropFirmDesktopModel): string | null {
  if (!model.isFunded) {
    if (model.profitTarget <= 0) return null
    if (model.profitPassed) return "Profit target met."
    const remaining = model.profitTarget - model.cyclePnl
    return `${formatPropfirmUsd(Math.max(0, remaining))} remaining`
  }
  if (model.payoutFailed) return "A drawdown rule is breached."
  if (model.payoutReady) return "Payout requirements are met."
  if (model.profitTarget > 0 && !model.profitPassed) return "Profit target still open."
  if (model.winningDaysRequired && !model.winningDaysMet) return "Winning days still open."
  if (model.consistencyRequired && !model.consistencyMet) return "Consistency rule still open."
  if (model.dailyBreached) return "Daily loss limit is breached."
  return "Payout requirements still open."
}

export function PropFirmDesktopHeader({
  selector,
  actions,
}: {
  selector: ReactNode
  actions?: ReactNode
}) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <h1 className="shrink-0 text-sm font-semibold tracking-tight text-white">
        Prop Firm Mode
      </h1>
      <div className="min-w-0 flex-1 basis-[280px]">{selector}</div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  )
}

export function PropFirmDesktopSkeleton() {
  return (
    <div className="tt-propfirm-desktop" aria-hidden>
      <div className="tt-propfirm-hero">
        <div className="h-52 animate-pulse rounded-xl bg-white/5" />
        <div className="h-52 animate-pulse rounded-xl bg-white/5" />
      </div>
      <div className="tt-propfirm-metrics">
        {Array.from({ length: 4 }).map((_, index) => (
          <div key={index} className="h-20 animate-pulse rounded-xl bg-white/5" />
        ))}
      </div>
    </div>
  )
}

export default function PropFirmDesktopView({
  model,
  selector,
  actions,
  equity,
}: PropFirmDesktopViewProps) {
  const remainingRoomPercent =
    model.maxDdLimit > 0 ? Math.max(0, 100 - model.ddPercent) : 0
  const roomTone = model.trailingBreached || model.distanceToDD < 0
    ? "bg-red-500"
    : model.distanceDanger
      ? "bg-amber-400"
      : "bg-emerald-400"

  const requirements: { state: "met" | "progress" | "failed"; title: string; detail: string }[] = []

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

  const dots =
    model.winningDaysRequired && model.winningDaysTarget > 0 && model.winningDaysTarget <= 10
      ? model.winningDaysTarget
      : 0

  const objectiveTitle = model.isFunded ? "Payout eligibility" : "Profit target"
  const footnote = objectiveFootnote(model)

  return (
    <div className="tt-propfirm-desktop">
      <PropFirmDesktopHeader selector={selector} actions={actions} />

      <div className="tt-propfirm-hero">
        <section className={`${SURFACE} flex flex-col justify-between px-5 py-4`}>
          <p className={TITLE}>Account status</p>
          <div className="mt-3">
            <p className="truncate text-lg font-semibold text-white">{model.accountName}</p>
            <p className="mt-0.5 text-sm text-gray-300">
              {model.sizeLabel ? `${model.sizeLabel} · ` : ""}
              {model.phase === "Eval" ? "Evaluation" : "Funded"}
            </p>
          </div>
          <div className="mt-4">
            <p className="text-3xl font-semibold tabular-nums tracking-tight text-white">
              {model.balanceLabel}
            </p>
            <p className={LABEL}>Current balance</p>
            <p className={`mt-2 text-sm font-semibold tabular-nums ${pnlClass(model.cyclePnl)}`}>
              {signedUsd(model.cyclePnl)}
              <span className="ml-2 font-normal text-gray-400">Cycle P&L</span>
            </p>
          </div>
          <div className="mt-4">
            <span
              className={`inline-flex rounded-full border px-2.5 py-1 text-xs font-semibold ${toneClass(model.statusTone)}`}
            >
              {model.statusLabel}
            </span>
          </div>
        </section>

        <section className={`${SURFACE} flex flex-col justify-between px-5 py-4`}>
          <div>
            <p className={TITLE}>Primary objective</p>
            <p className="mt-3 text-sm font-semibold text-white">{objectiveTitle}</p>
          </div>
          {model.profitTarget > 0 ? (
            <div className="mt-4">
              <div className="flex items-baseline justify-between gap-3">
                <p className="text-2xl font-semibold tabular-nums text-white">
                  {signedUsd(model.cyclePnl)}
                  <span className="ml-2 text-base font-medium text-gray-300">
                    / {formatPropfirmUsd(model.profitTarget)}
                  </span>
                </p>
                <p className={`text-sm font-semibold tabular-nums ${model.cyclePnl < 0 ? "text-red-400" : "text-blue-300"}`}>
                  {model.cyclePnl < 0 ? "-" : ""}
                  {model.progressPercent.toFixed(0)}%
                </p>
              </div>
              <div className="mt-3">
                <PropfirmProfitTargetProgressBar
                  progressPercent={model.progressPercent}
                  negative={model.cyclePnl < 0}
                />
              </div>
            </div>
          ) : (
            <p className="mt-4 text-sm text-gray-300">No profit target on this account.</p>
          )}
          {footnote ? <p className="mt-3 text-sm text-gray-300">{footnote}</p> : null}
        </section>
      </div>

      <div className="tt-propfirm-metrics">
        {model.profitTarget > 0 ? (
          <Metric
            label="Profit target"
            value={`${signedUsd(model.cyclePnl)} / ${formatPropfirmUsd(model.profitTarget)}`}
            detail={`${model.progressPercent.toFixed(0)}% of target`}
          >
            <PropfirmProfitTargetProgressBar
              progressPercent={model.progressPercent}
              negative={model.cyclePnl < 0}
            />
          </Metric>
        ) : null}
        {model.maxDdLimit > 0 ? (
          <Metric
            label="Drawdown room"
            value={formatPropfirmUsd(model.distanceToDD)}
            detail={`${formatPropfirmUsd(model.drawdownUsed)} used of ${formatPropfirmUsd(model.maxDdLimit)}`}
            valueClassName={
              model.trailingBreached || model.distanceToDD < 0
                ? "text-red-400"
                : model.distanceDanger
                  ? "text-amber-200"
                  : "text-emerald-300"
            }
          >
            <Bar percent={remainingRoomPercent} className={roomTone} />
          </Metric>
        ) : null}
        {model.consistencyRequired ? (
          <Metric
            label="Consistency"
            value={model.consistencyMet ? "Within limit" : "Over limit"}
            detail={
              model.consistencyRuleLabel
                ? `Limit ${model.consistencyRuleLabel} · biggest ${formatPropfirmUsd(model.biggestWin)} / allowed ${formatPropfirmUsd(model.allowedMax)}`
                : `Biggest ${formatPropfirmUsd(model.biggestWin)} / allowed ${formatPropfirmUsd(model.allowedMax)}`
            }
            valueClassName={model.consistencyMet ? "text-emerald-300" : "text-amber-200"}
          >
            {model.allowedMax > 0 ? (
              <Bar
                percent={Math.min((model.biggestWin / model.allowedMax) * 100, 100)}
                className={model.consistencyMet ? "bg-emerald-400" : "bg-amber-400"}
              />
            ) : null}
          </Metric>
        ) : null}
        {model.winningDaysRequired ? (
          <Metric
            label="Winning days"
            value={`${model.winningDays} / ${model.winningDaysTarget}`}
            detail={model.winningDaysMet ? "Requirement met" : "Still in progress"}
            valueClassName={model.winningDaysMet ? "text-emerald-300" : "text-amber-200"}
          >
            {dots > 0 ? (
              <div className="flex gap-1" aria-hidden>
                {Array.from({ length: dots }).map((_, index) => (
                  <span
                    key={index}
                    className={`h-2 w-2 rounded-full ${
                      index < model.winningDays ? "bg-emerald-400" : "bg-white/15"
                    }`}
                  />
                ))}
              </div>
            ) : null}
          </Metric>
        ) : null}
        {model.dailyLimit > 0 ? (
          <Metric
            label="Daily loss"
            value={model.dailyBreached ? "Limit breached" : "Within limit"}
            detail={`Worst ${formatPropfirmUsd(model.worstDailyLossUsed)} · limit ${formatPropfirmUsd(model.dailyLimit)} · today ${signedUsd(model.todayPnl)}`}
            valueClassName={model.dailyBreached ? "text-red-400" : "text-emerald-300"}
          />
        ) : null}
      </div>

      {model.warnings.length > 0 ? (
        <div className="space-y-2">
          {model.warnings.map((warning) => (
            <p
              key={warning}
              className="rounded-lg border border-red-500/20 bg-red-500/10 px-3 py-2 text-sm text-red-400"
            >
              {warning}
            </p>
          ))}
        </div>
      ) : null}

      <section className={`${SURFACE} px-4 py-3`}>
        <h2 className={TITLE}>Requirements</h2>
        <div className="mt-1">
          {requirements.length > 0 ? (
            requirements.map((row) => (
              <RequirementRow key={row.title} {...row} />
            ))
          ) : (
            <p className="py-3 text-sm text-gray-400">No rules configured on this account.</p>
          )}
        </div>
      </section>

      <div className="tt-propfirm-lower">
        <div className="tt-propfirm-lower-stack">
          {model.isFunded ? (
            <section className={`${SURFACE} px-4 py-3`}>
              <h2 className={TITLE}>Payout status</h2>
              <div className="mt-1">
                <div className="flex items-baseline justify-between gap-3 border-b border-white/10 py-2">
                  <span className="truncate text-sm text-gray-300">Eligibility</span>
                  <span
                    className={`shrink-0 text-sm ${VALUE} ${
                      model.payoutReady
                        ? "text-emerald-300"
                        : model.payoutFailed
                          ? "text-red-400"
                          : "text-amber-200"
                    }`}
                  >
                    {model.payoutFailed ? "Failed" : model.payoutReady ? "Payout ready" : "Not ready"}
                  </span>
                </div>
                <div className="flex items-start justify-between gap-3 border-b border-white/10 py-2">
                  <span className="truncate text-sm text-gray-300">Recorded payouts</span>
                  <span className="shrink-0 text-right">
                    <span className={`block text-sm ${VALUE}`}>{model.payoutTotalLabel}</span>
                    <span className="text-[11px] text-gray-400">
                      {model.payoutCount} payout{model.payoutCount === 1 ? "" : "s"}
                    </span>
                  </span>
                </div>
                {model.maxDdLimit > 0 ? (
                  <DetailRow title="Drawdown room" detail={formatPropfirmUsd(model.distanceToDD)} />
                ) : null}
                <DetailRow title="Current balance" detail={model.balanceLabel} />
              </div>
              <h3 className={`${TITLE} mb-1 mt-4`}>Payout history</h3>
              {model.payoutHistory.length > 0 ? (
                <div className="max-h-48 overflow-y-auto">
                  {model.payoutHistory.map((row) => (
                    <div
                      key={row.id}
                      className="flex items-center justify-between gap-3 border-b border-white/10 py-1.5 text-sm last:border-b-0"
                    >
                      <span className="text-gray-300">{row.dateLabel}</span>
                      <span className="font-semibold tabular-nums text-white">{row.amountLabel}</span>
                      <span className="text-xs font-medium text-emerald-300">Paid</span>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="py-2 text-sm text-gray-400">No payouts recorded for this account.</p>
              )}
            </section>
          ) : null}

          <section className={`${SURFACE} px-4 py-3`}>
            <h2 className={TITLE}>Account rules</h2>
            <div className="mt-1">
              <DetailRow title="Account size" detail={model.sizeLabel || "—"} />
              <DetailRow
                title="Profit target"
                detail={model.profitTarget > 0 ? formatPropfirmUsd(model.profitTarget) : "—"}
              />
              <DetailRow
                title="Max drawdown"
                detail={model.maxDdLimit > 0 ? formatPropfirmUsd(model.maxDdLimit) : "—"}
              />
              <DetailRow title="Drawdown floor" detail={formatPropfirmUsd(model.drawdownFloor)} />
              <DetailRow
                title="Daily drawdown"
                detail={model.dailyLimit > 0 ? formatPropfirmUsd(model.dailyLimit) : "—"}
              />
              <DetailRow
                title="Consistency"
                detail={model.consistencyRequired ? (model.consistencyRuleLabel ?? "Active") : "Does not apply"}
              />
              <DetailRow
                title="Winning days"
                detail={model.winningDaysRequired ? String(model.winningDaysTarget) : "Does not apply"}
              />
              {model.winningDayThresholdLabel ? (
                <DetailRow title="Winning day threshold" detail={model.winningDayThresholdLabel} />
              ) : null}
            </div>
          </section>
        </div>

        <div className="tt-propfirm-lower-stack">
          <div className="min-w-0">{equity}</div>
        </div>
      </div>

      <div className="tt-propfirm-analytics">
        <section className={`${SURFACE} px-4 py-3`}>
          <div className="mb-2 flex items-center justify-between gap-2">
            <h2 className={TITLE}>Daily performance</h2>
            <span className="text-xs tabular-nums text-gray-400">{model.dailyRows.length} days</span>
          </div>
          <p className="mb-2 text-xs text-gray-400">Lifetime, aggregated by trading day</p>
          <div className="max-h-48 space-y-0 overflow-y-auto">
            {model.dailyRows.length > 0 ? (
              model.dailyRows.map(([date, pnl]) => (
                <div
                  key={date}
                  className="flex items-center justify-between gap-3 border-b border-white/10 py-1 text-sm last:border-b-0"
                >
                  <span className="text-gray-300">{date}</span>
                  <span className={`font-semibold tabular-nums ${pnlClass(pnl)}`}>
                    {formatPnlCurrency(pnl, {
                      minimumFractionDigits: 0,
                      maximumFractionDigits: 2,
                    })}
                  </span>
                </div>
              ))
            ) : (
              <p className="py-4 text-center text-sm text-gray-400">No daily performance yet.</p>
            )}
          </div>
        </section>

        <section className={`${SURFACE} px-4 py-3`}>
          <h2 className={TITLE}>Performance</h2>
          <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3">
            <div>
              <p className={LABEL}>Cycle P&L</p>
              <p className={`text-sm ${VALUE} ${pnlClass(model.cyclePnl)}`}>{signedUsd(model.cyclePnl)}</p>
            </div>
            <div>
              <p className={LABEL}>Lifetime P&L</p>
              <p className={`text-sm ${VALUE} ${pnlClass(model.lifetimePnl)}`}>{signedUsd(model.lifetimePnl)}</p>
            </div>
            <div>
              <p className={LABEL}>Today</p>
              <p className={`text-sm ${VALUE} ${pnlClass(model.todayPnl)}`}>{signedUsd(model.todayPnl)}</p>
            </div>
            <div>
              <p className={LABEL}>Winning days</p>
              <p className={`text-sm ${VALUE}`}>
                {model.winningDaysRequired
                  ? `${model.winningDays} / ${model.winningDaysTarget}`
                  : String(model.winningDays)}
              </p>
            </div>
            <div>
              <p className={LABEL}>Worst day</p>
              <p className={`text-sm ${VALUE} ${pnlClass(model.worstDay)}`}>
                {signedUsd(model.worstDay)}
              </p>
            </div>
          </div>
        </section>
      </div>
    </div>
  )
}
