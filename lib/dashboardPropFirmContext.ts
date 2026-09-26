import { accountIdFromDashboardAccountFilterKey } from "@/app/components/dashboard/dashboardGearUtils"
import {
  computePropfirmAccountMetrics,
  computePropfirmEvalDisplayStatus,
  computePropfirmFundedDisplayStatus,
  formatPropfirmUsd,
  parseAccountSizeToNumber,
  type PropfirmAccountRules,
  type PropfirmTrade,
} from "@/lib/propfirmMetrics"
import {
  buildPayoutCycleContext,
  isEvalPropfirmAccount,
  isFundedPropfirmAccount,
  selectActivePayoutCycle,
  type AccountPayoutCycle,
} from "@/lib/propfirmPayoutCycles"
import { isCopyGroupFilterValue } from "@/lib/tradeAccountSelection"
import { formatAccountNameWithSizeDisplay } from "@/lib/tradeAccountDisplay"

export type DashboardPropFirmAccount = PropfirmAccountRules & {
  id: string
  name?: string | null
  mode?: string | null
  category?: string | null
  daily_drawdown?: number | string | null
}

export type DashboardPropFirmPhase = "eval" | "funded"

export type DashboardPropFirmTone = "positive" | "negative" | "neutral"

export type DashboardPropFirmSnapshot = {
  accountId: string
  phase: DashboardPropFirmPhase
  heading: string
  phaseLabel: string
  statusLabel: string
  statusTone: DashboardPropFirmTone
  balanceLabel: string
  profitTarget: { remainingLabel: string; progress: number } | null
  drawdown: { remainingLabel: string; usedProgress: number; danger: boolean } | null
  consistency: { percentLabel: string; progress: number; met: boolean } | null
  winningDays: { label: string; progress: number; met: boolean } | null
}

const PROP_FIRM_CATEGORY = "Prop Firm"

export function propFirmDetailsHref(accountId: string): string {
  return `/analytics/propfirm?account=${encodeURIComponent(accountId)}`
}

export type DashboardPropFirmAccountSource = {
  id?: string | null
  name?: string | null
  account_size?: unknown
  mode?: string | null
  category?: string | null
  consistency?: number | string | null
  max_drawdown?: number | string | null
  daily_drawdown?: number | string | null
  profit_target?: number | string | null
  winning_days?: number | string | null
  winning_day_threshold?: number | string | null
}

export function resolveDashboardPropFirmAccount(
  accountFilter: string,
  accountById: Record<string, DashboardPropFirmAccountSource | null | undefined>
): DashboardPropFirmAccount | null {
  if (!accountFilter || accountFilter === "all") return null
  if (isCopyGroupFilterValue(accountFilter)) return null

  const accountId = accountIdFromDashboardAccountFilterKey(accountFilter)
  if (!accountId) return null

  const account = accountById[accountId]
  if (!account || String(account.category ?? "") !== PROP_FIRM_CATEGORY) return null
  if (
    !isEvalPropfirmAccount(account.mode) &&
    !isFundedPropfirmAccount(account.mode)
  ) {
    return null
  }

  return {
    ...account,
    id: accountId,
    account_size: account.account_size,
  }
}

/** Prop Firm Mode only selects an account the signed-in user's prop list already contains. */
export function propFirmModeAccountIdFromQuery(
  accountId: string | null | undefined,
  accounts: Array<{ id: string | number; mode?: string | null }>
): string | null {
  const id = String(accountId ?? "").trim()
  if (!id) return null
  const match = accounts.find((account) => String(account.id) === id)
  if (!match) return null
  if (
    !isEvalPropfirmAccount(match.mode) &&
    !isFundedPropfirmAccount(match.mode)
  ) {
    return null
  }
  return String(match.id)
}

function statusPresentation(
  phase: DashboardPropFirmPhase,
  evalStatus: ReturnType<typeof computePropfirmEvalDisplayStatus>,
  fundedStatus: ReturnType<typeof computePropfirmFundedDisplayStatus>
): { label: string; tone: DashboardPropFirmTone } {
  if (phase === "funded") {
    if (fundedStatus === "FAILED") return { label: "Failed", tone: "negative" }
    if (fundedStatus === "PAYOUT_READY") {
      return { label: "Payout Ready", tone: "positive" }
    }
    return { label: "In Progress", tone: "neutral" }
  }
  if (evalStatus === "PASSED") return { label: "Passed", tone: "positive" }
  if (evalStatus === "FAILED") return { label: "Failed", tone: "negative" }
  return { label: "In Progress", tone: "neutral" }
}

export function buildDashboardPropFirmSnapshot(
  account: DashboardPropFirmAccount,
  trades: PropfirmTrade[],
  payoutCycles: AccountPayoutCycle[] = []
): DashboardPropFirmSnapshot {
  const phase: DashboardPropFirmPhase = isFundedPropfirmAccount(account.mode)
    ? "funded"
    : "eval"
  const startingBalance = parseAccountSizeToNumber(account)
  const activeCycle =
    phase === "funded" ? selectActivePayoutCycle(payoutCycles) : null
  const metrics = computePropfirmAccountMetrics(
    trades,
    account,
    buildPayoutCycleContext(activeCycle, startingBalance)
  )
  const evalStatus = computePropfirmEvalDisplayStatus(metrics.cycleProgress)
  const winningDaysRequired = Number(account.winning_days) > 0
  const winningDaysTargetMet =
    !winningDaysRequired ||
    metrics.cycleDailyMetrics.winningDays >= Number(account.winning_days)
  const dailyLimit = Number(account.daily_drawdown) || 0
  const dailyDrawdownBreached =
    dailyLimit > 0 &&
    metrics.cycleDailyMetrics.worstDailyLossUsed > dailyLimit
  const fundedStatus = computePropfirmFundedDisplayStatus({
    cycleProgress: metrics.cycleProgress,
    dailyDrawdownBreached,
    winningDaysRequired,
    winningDaysTargetMet,
    consistencyRequired: metrics.cycleConsistencyMetrics.ruleActive,
    consistencyMet: metrics.cycleConsistencyMetrics.isConsistent,
  })
  const status = statusPresentation(phase, evalStatus, fundedStatus)
  const nameSize = formatAccountNameWithSizeDisplay(
    account.name ?? "",
    account.account_size != null ? String(account.account_size) : null
  )
  const profitTarget = Number(account.profit_target) || 0
  const maxDrawdown = Number(account.max_drawdown) || 0
  const remainingTarget = Math.max(0, profitTarget - metrics.cyclePnL)
  const consistency = metrics.cycleConsistencyMetrics
  const consistencyRatio =
    consistency.ruleActive && consistency.totalProfit > 0
      ? Math.min((consistency.biggestWin / consistency.totalProfit) * 100, 100)
      : 0
  const requiredDays = Number(account.winning_days) || 0
  const winningDays = metrics.cycleDailyMetrics.winningDays

  return {
    accountId: account.id,
    phase,
    heading: nameSize || account.name || "Account",
    phaseLabel: phase === "funded" ? "Funded" : "Eval",
    statusLabel: status.label,
    statusTone: status.tone,
    balanceLabel: formatPropfirmUsd(metrics.displayCurrentBalance),
    profitTarget:
      profitTarget > 0
        ? {
            remainingLabel:
              remainingTarget <= 0
                ? "Met"
                : `${formatPropfirmUsd(remainingTarget)} left`,
            progress: Math.min(Math.max(metrics.cycleProgress.progressPercent, 0), 100),
          }
        : null,
    drawdown:
      maxDrawdown > 0
        ? {
            remainingLabel: formatPropfirmUsd(metrics.cycleTrailingMetrics.distanceToDD),
            usedProgress: Math.min(Math.max(metrics.cycleProgress.ddPercent, 0), 100),
            danger:
              metrics.cycleProgress.distanceDanger ||
              metrics.cycleTrailingMetrics.distanceToDD < 0,
          }
        : null,
    consistency: consistency.ruleActive
      ? {
          percentLabel:
            consistency.totalProfit > 0
              ? `${Math.round(consistencyRatio)}%`
              : "—",
          progress: consistencyRatio,
          met: consistency.isConsistent,
        }
      : null,
    winningDays: winningDaysRequired
      ? {
          label: `${winningDays} / ${requiredDays}`,
          progress: Math.min((winningDays / requiredDays) * 100, 100),
          met: winningDaysTargetMet,
        }
      : null,
  }
}
