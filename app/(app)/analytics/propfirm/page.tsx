"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import { useEffect, useMemo, useState, type ReactNode } from "react"
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"
import { supabase } from "@/lib/supabaseClient"
import {
  buildPropfirmEquityCurveData,
  computePropfirmAccountMetrics,
  computePropfirmEquityCurveYDomain,
  computePropfirmEquityCurveYTicks,
  computePropfirmEvalDisplayStatus,
  computePropfirmFundedDisplayStatus,
  computePayoutDrawdownFloor,
  formatPropfirmUsd,
  parseAccountSizeToNumber,
  selectPropfirmEquityCurveInputs,
  type ConsistencyRuleResult,
  type PropfirmAccountRules,
  type PropfirmEquityCurvePoint,
  type PropfirmEquityCurveScope,
  type PropfirmTrade,
  type TrailingDrawdownResult,
} from "@/lib/propfirmMetrics"
import LockedFeature from "@/app/components/LockedFeature"
import CustomSelect from "@/app/components/CustomSelect"
import EmptyState from "@/app/components/ui/EmptyState"
import { SkeletonAnalyticsPage } from "@/app/components/ui/skeletons"
import {
  dashboardInsightBodyClass,
  dashboardInsightCardClass,
  dashboardInsightLabelClass,
  dashboardInsightMetricNegativeClass,
  dashboardInsightMetricPositiveClass,
  dashboardInsightTitleClass,
} from "@/app/components/dashboard/dashboardInsightStyles"
import { isProActive } from "@/lib/subscription"
import { formatPnlCurrency } from "@/lib/formatMoney"
import {
  MANAGE_ACCOUNTS_VALUE,
  navigateToManageAccounts,
} from "@/app/components/TradeFilterBar"
import { formatAccountNameWithSizeDisplay } from "@/lib/tradeAccountDisplay"
import Modal from "@/app/components/ui/Modal"
import AchievementUploadModal, {
  type AchievementUploadInitialValues,
} from "@/app/components/AchievementUploadModal"
import CreateAccountModal from "@/app/components/CreateAccountModal"
import PropFirmEvalContinuanceModal from "@/app/components/propfirm/PropFirmEvalContinuanceModal"
import PropFirmFundedRulesChoiceModal from "@/app/components/propfirm/PropFirmFundedRulesChoiceModal"
import PayoutSetupModal, {
  type PayoutSetupValues,
} from "@/app/components/PayoutSetupModal"
import PropFirmPayoutHistoryModal from "@/app/components/propfirm/PropFirmPayoutHistoryModal"
import { useUserProfile } from "@/lib/useUserProfile"
import {
  buildPayoutCycleContext,
  fetchPayoutCycleHistoryByAccountIds,
  isEvalPropfirmAccount,
  isFundedPropfirmAccount,
  mergeFundedPayoutHistory,
  PROPFIRM_ALL_ACCOUNTS_VALUE,
  recordAccountPayout,
  resolveDefaultPayoutDrawdownBehavior,
  selectActivePayoutCycle,
  summarizeAccountPayouts,
  applyRecordedPayoutToHistory,
  selectCompletedPayoutHistory,
  selectRecordedPayoutEquityEvents,
  type AccountPayoutCycle,
  type PayoutHistoryEntry,
} from "@/lib/propfirmPayoutCycles"
import { ACCOUNT_DROPDOWN_TRIGGER_COMPACT_CLASS } from "@/lib/accountDropdownStyles"
import {
  buildConvertEvalToFundedFormInitial,
  buildCreateFundedAccountFormInitial,
  buildPropFirmMilestoneAchievementInitials,
  convertEvalAccountToFundedWithRules,
  propFirmMilestoneUploadConfig,
  type PropFirmMilestoneKind,
} from "@/lib/propfirmMilestones"
import {
  insertTradingAccount,
  type CreateTradingAccountPayload,
  type TradingAccountListItem,
} from "@/lib/tradingAccounts"
import { resolveAccountModeForSave } from "@/lib/createAccountForm"
import { invalidateAccountsCache } from "@/lib/appDataCache"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { isDemoUserId } from "@/lib/demo/constants"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import {
  getDemoPayoutCyclesByAccountId,
  getDemoPropfirmAccounts,
  getDemoPropfirmTrades,
} from "@/lib/demo/demoPropfirm"

const SECTION_PANEL = dashboardInsightCardClass

const INNER_ROW_CLASS =
  "flex items-center justify-between rounded-lg border border-white/10 bg-white/5 px-2.5 py-2 transition-colors hover:bg-white/[0.07] md:px-3 md:py-2.5"

const RULE_CHIP_CLASS =
  "flex items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-2.5 py-2 text-xs transition-colors hover:bg-white/[0.07] md:gap-2.5 md:px-3 md:py-2.5 md:text-sm"

function PropfirmStat({
  title,
  value,
  positive,
  valueClassName,
  onClick,
}: {
  title: string
  value: string
  positive?: boolean
  valueClassName?: string
  onClick?: () => void
}) {
  let color = valueClassName ?? "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  const className = `flex min-h-[76px] w-full flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-2.5 text-center backdrop-blur-md md:min-h-[90px] md:p-4${
    onClick
      ? " cursor-pointer transition hover:border-white/20 hover:bg-white/[0.14] focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500/40"
      : ""
  }`

  const content = (
    <>
      <p className="mb-1 text-[11px] text-gray-400 md:text-sm">{title}</p>
      <span
        className={`block whitespace-nowrap text-sm font-semibold leading-tight tabular-nums md:text-lg lg:text-xl ${color}`}
      >
        {value}
      </span>
    </>
  )

  if (onClick) {
    return (
      <button type="button" onClick={onClick} className={className}>
        {content}
      </button>
    )
  }

  return <div className={className}>{content}</div>
}

const PROPFIRM_ACCOUNT_FIELDS =
  "id,name,account_size,account_number,mode,consistency,max_drawdown,daily_drawdown,profit_target,winning_days,winning_day_threshold,payout_drawdown_behavior,remember_payout_drawdown_behavior"

const PROPFIRM_TRADE_FIELDS =
  "id,pnl,date,trade_date,entry_time,exit_time,created_at"

type PropfirmAccount = PropfirmAccountRules & {
  id: string | number
  name?: string | null
  account_number?: string | null
  mode?: string | null
  daily_drawdown?: number | string | null
  winning_days?: number | string | null
  winning_day_threshold?: number | string | null
  payout_drawdown_behavior?: string | null
  remember_payout_drawdown_behavior?: boolean | null
}

/** Default equity curve scope; wire to a toggle when adding Lifetime / Cycle views. */
const PROPFIRM_EQUITY_CURVE_SCOPE: PropfirmEquityCurveScope = "lifetime"

function PropfirmPageShell({ children }: { children: ReactNode }) {
  return (
    <div className="w-full px-3 pb-3 pt-0 text-white md:px-4 md:pb-10">
      <div className="relative z-0 mx-auto mt-2.5 flex w-full max-w-[1600px] flex-col gap-6 px-1 md:gap-8 md:px-6">
        {children}
      </div>
    </div>
  )
}

function PropfirmEquityCurve({ data }: { data: PropfirmEquityCurvePoint[] }) {
  const values = data.map((point) => point.balance)
  const yAxisDomain = computePropfirmEquityCurveYDomain(values)
  const yAxisTicks = computePropfirmEquityCurveYTicks(yAxisDomain)

  return (
    <div className={SECTION_PANEL}>
      <div className="mb-3 flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-xs font-semibold text-blue-300 md:text-base">
            Equity Curve
          </h2>
          <p className="mt-0.5 text-[11px] text-gray-400 md:text-sm">
            Lifetime account balance progression by trading day
          </p>
        </div>
      </div>

      {data.length > 1 ? (
        <div className="h-[240px] w-full overflow-hidden sm:h-[280px] md:h-[300px]">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart
              data={data}
              margin={{ top: 4, right: 12, left: 8, bottom: 10 }}
            >
              <CartesianGrid stroke="#334155" strokeDasharray="3 3" />
              <XAxis
                dataKey="date"
                stroke="#94a3b8"
                tick={{ fill: "#94a3b8", fontSize: 11 }}
                tickFormatter={(value) => {
                  const label = String(value)
                  if (label === "Start") return label
                  const d = new Date(`${label}T12:00:00Z`)
                  if (Number.isNaN(d.getTime())) return label
                  return `${d.getUTCMonth() + 1}/${d.getUTCDate()}`
                }}
                interval="preserveStartEnd"
                minTickGap={20}
              />
              <YAxis
                stroke="#94a3b8"
                tick={{ fill: "#94a3b8", fontSize: 11 }}
                tickFormatter={(value) => formatPropfirmUsd(Number(value))}
                width={72}
                domain={yAxisDomain}
                ticks={yAxisTicks}
                allowDataOverflow
              />
              <Tooltip
                formatter={(value, name) => {
                  if (name === "Balance") {
                    return [formatPropfirmUsd(Number(value)), "Balance"]
                  }
                  return [formatPropfirmUsd(Number(value)), "Day P&L"]
                }}
                labelFormatter={(label) => `Day: ${String(label)}`}
                contentStyle={{
                  backgroundColor: "#0f172a",
                  border: "1px solid rgba(255,255,255,0.12)",
                  borderRadius: "10px",
                }}
                labelStyle={{ color: "#94a3b8" }}
              />
              <Line
                type="monotone"
                dataKey="balance"
                name="Balance"
                stroke="#22c55e"
                strokeWidth={2.5}
                dot={data.length <= 12 ? { r: 3, fill: "#22c55e" } : false}
                activeDot={{ r: 5 }}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <EmptyState
          title="Not Enough Data Yet"
          description="Add more trades to unlock detailed analytics."
          className="border-0 bg-transparent py-8"
        />
      )}
    </div>
  )
}

export type { ConsistencyRuleResult, TrailingDrawdownResult }

export {
  computeConsistencyRule,
  computeTrailingDrawdown,
} from "@/lib/propfirmMetrics"

function formatPropfirmAccountNameOnly(acc: PropfirmAccount) {
  const nameSize = formatAccountNameWithSizeDisplay(
    acc.name ?? "",
    acc.account_size as string | null | undefined
  )
  return nameSize || acc.name || "Account"
}

function tradingListItemToPropfirmAccount(
  item: TradingAccountListItem,
  previous?: PropfirmAccount
): PropfirmAccount {
  return {
    ...previous,
    id: item.id,
    name: item.name,
    account_size: item.size,
    account_number: item.account_number,
    mode: item.mode,
    consistency: item.rules?.consistency ?? null,
    max_drawdown: item.rules?.maxDrawdown ?? null,
    daily_drawdown: item.rules?.dailyDrawdown ?? null,
    profit_target: item.rules?.profitTarget ?? null,
    winning_days: item.rules?.winningDays ?? null,
    winning_day_threshold: item.rules?.winningDayThreshold ?? null,
  }
}

export default function PropFirmPage() {
  const router = useRouter()
  const { user, profile } = useUserProfile()
  const [planChecked, setPlanChecked] = useState(false)
  const [hasProAccess, setHasProAccess] = useState(false)
  const [accounts, setAccounts] = useState<PropfirmAccount[]>([])
  const [accountsLoaded, setAccountsLoaded] = useState(false)
  const [accountFilter, setAccountFilter] = useState(PROPFIRM_ALL_ACCOUNTS_VALUE)
  const [trades, setTrades] = useState<PropfirmTrade[]>([])
  const [loadingTrades, setLoadingTrades] = useState(false)
  const [payoutCyclesByAccountId, setPayoutCyclesByAccountId] = useState<
    Record<string, AccountPayoutCycle[]>
  >({})
  const [loadingPayoutHistory, setLoadingPayoutHistory] = useState(false)
  const [payoutModalOpen, setPayoutModalOpen] = useState(false)
  const [payoutSetupOpen, setPayoutSetupOpen] = useState(false)
  const [payoutSetupKey, setPayoutSetupKey] = useState(0)
  const [payoutHistoryOpen, setPayoutHistoryOpen] = useState(false)
  const [recordingPayout, setRecordingPayout] = useState(false)
  const [achievementUploadOpen, setAchievementUploadOpen] = useState(false)
  const [achievementUploadInitial, setAchievementUploadInitial] = useState<
    AchievementUploadInitialValues | undefined
  >(undefined)
  const [activeMilestoneKind, setActiveMilestoneKind] =
    useState<PropFirmMilestoneKind | null>(null)
  const [evalContinuanceOpen, setEvalContinuanceOpen] = useState(false)
  const [evalContinuanceAccount, setEvalContinuanceAccount] =
    useState<PropfirmAccount | null>(null)
  const [evalContinuanceBusy, setEvalContinuanceBusy] = useState(false)
  const [evalRulesChoiceOpen, setEvalRulesChoiceOpen] = useState(false)
  const [convertRulesEditorOpen, setConvertRulesEditorOpen] = useState(false)
  const [convertRulesSameAsEval, setConvertRulesSameAsEval] = useState(false)
  const [createFundedAccountOpen, setCreateFundedAccountOpen] = useState(false)

  const isAllAccountsView = accountFilter === PROPFIRM_ALL_ACCOUNTS_VALUE

  const selectedAccount = useMemo(() => {
    if (isAllAccountsView) return null
    return (
      accounts.find((account) => String(account.id) === accountFilter) ?? null
    )
  }, [accounts, accountFilter, isAllAccountsView])

  const fundedAccounts = useMemo(
    () => accounts.filter((account) => isFundedPropfirmAccount(account.mode)),
    [accounts]
  )

  const payoutCycles = useMemo(() => {
    if (!selectedAccount) return []
    return payoutCyclesByAccountId[String(selectedAccount.id)] ?? []
  }, [selectedAccount, payoutCyclesByAccountId])

  const isFundedAccountSelected =
    selectedAccount != null && isFundedPropfirmAccount(selectedAccount.mode)

  const isEvalAccountSelected =
    selectedAccount != null && isEvalPropfirmAccount(selectedAccount.mode)

  const showPassEvalControls = isEvalAccountSelected

  const showPayoutHistoryButton =
    isAllAccountsView || isFundedAccountSelected

  const showPayoutControls = isFundedAccountSelected

  const showAccountDashboard = selectedAccount != null

  const activePayoutCycle = useMemo(
    () => selectActivePayoutCycle(payoutCycles),
    [payoutCycles]
  )

  const payoutSummary = useMemo(
    () => summarizeAccountPayouts(payoutCycles),
    [payoutCycles]
  )

  const completedPayoutHistory = useMemo((): PayoutHistoryEntry[] => {
    if (isAllAccountsView) {
      return mergeFundedPayoutHistory(
        fundedAccounts,
        payoutCyclesByAccountId,
        (account) =>
          formatPropfirmAccountNameOnly(account as PropfirmAccount)
      )
    }

    if (!selectedAccount) return []

    const accountName = formatPropfirmAccountNameOnly(selectedAccount)
    return selectCompletedPayoutHistory(payoutCycles).map((payout) => ({
      ...payout,
      accountName,
    }))
  }, [
    isAllAccountsView,
    fundedAccounts,
    payoutCyclesByAccountId,
    selectedAccount,
    payoutCycles,
  ])

  const payoutHistorySubtitle = isAllAccountsView
    ? "Every payout recorded across your funded prop firm accounts, newest first."
    : "View every payout recorded for this trading account."

  const payoutCycleContext = useMemo(() => {
    const startingBalance = selectedAccount
      ? parseAccountSizeToNumber(selectedAccount)
      : 0
    return buildPayoutCycleContext(activePayoutCycle, startingBalance)
  }, [activePayoutCycle, selectedAccount])

  const accountMetrics = useMemo(
    () =>
      computePropfirmAccountMetrics(trades, selectedAccount, payoutCycleContext),
    [trades, selectedAccount, payoutCycleContext]
  )

  const {
    cycleDailyMetrics,
    lifetimeDailyMetrics,
    startingBalance,
    cycleTrailingMetrics,
    lifetimeTrailingMetrics,
    cycleConsistencyMetrics,
    cyclePnL,
    cycleProgress,
    displayCurrentBalance,
  } = accountMetrics
  const { winningDays, worstDailyLossUsed } = cycleDailyMetrics
  const lifetimeDailyRows = lifetimeDailyMetrics.dailyRows

  const accountSelectOptions = useMemo(
    () => [
      { value: PROPFIRM_ALL_ACCOUNTS_VALUE, label: "All Accounts" },
      { value: "__divider__", label: "----------------", disabled: true },
      ...accounts.map((acc) => ({
        value: String(acc.id),
        label: `${formatAccountNameWithSizeDisplay(acc.name ?? "", acc.account_size as string | null | undefined)} • ${acc.mode}`,
      })),
      { value: MANAGE_ACCOUNTS_VALUE, label: "⚙️ Manage Accounts" },
    ],
    [accounts]
  )
  const equityCurveData = useMemo(() => {
    if (!showAccountDashboard) return []
    const { startingBalance: curveStart } = selectPropfirmEquityCurveInputs(
      accountMetrics,
      PROPFIRM_EQUITY_CURVE_SCOPE
    )
    return buildPropfirmEquityCurveData(
      trades,
      curveStart,
      selectRecordedPayoutEquityEvents(payoutCycles)
    )
  }, [accountMetrics, showAccountDashboard, trades, payoutCycles])

  useEffect(() => {
    if (profile) {
      setHasProAccess(isProActive(profile))
      setPlanChecked(true)
      return
    }

    if (!user?.id) {
      setHasProAccess(false)
      setPlanChecked(true)
      return
    }

    async function checkPlan() {
      const { data: profileRow } = await supabase
        .from("profiles")
        .select("is_pro, subscription_status")
        .eq("id", user!.id)
        .maybeSingle()
      setHasProAccess(isProActive(profileRow))
      setPlanChecked(true)
    }
    void checkPlan()
  }, [profile, user?.id])

  useEffect(() => {
    if (!planChecked || !hasProAccess) return
    async function loadAccounts() {
      if (isDemoUserId(user?.id)) {
        setAccounts(getDemoPropfirmAccounts() as PropfirmAccount[])
        setAccountsLoaded(true)
        return
      }

      if (!user?.id) {
        setAccountsLoaded(true)
        return
      }

      const { data, error } = await supabase
        .from("accounts")
        .select(PROPFIRM_ACCOUNT_FIELDS)
        .eq("user_id", user.id)
        .eq("category", "Prop Firm")

      if (error) {
        console.error(error)
        setAccountsLoaded(true)
        return
      }

      setAccounts(data || [])
      setAccountsLoaded(true)
    }

    loadAccounts()
  }, [planChecked, hasProAccess, user?.id])

  useEffect(() => {
    if (!planChecked || !hasProAccess) return
    if (!accountsLoaded || fundedAccounts.length === 0) {
      setPayoutCyclesByAccountId({})
      return
    }

    let cancelled = false

    async function loadFundedPayoutCycles() {
      setLoadingPayoutHistory(true)
      try {
        if (isDemoUserId(user?.id)) {
          if (!cancelled) {
            setPayoutCyclesByAccountId(
              getDemoPayoutCyclesByAccountId(fundedAccounts.map((account) => account.id))
            )
          }
          return
        }

        const cyclesByAccountId = await fetchPayoutCycleHistoryByAccountIds(
          supabase,
          fundedAccounts.map((account) => account.id)
        )
        if (!cancelled) setPayoutCyclesByAccountId(cyclesByAccountId)
      } finally {
        if (!cancelled) setLoadingPayoutHistory(false)
      }
    }

    void loadFundedPayoutCycles()
    return () => {
      cancelled = true
    }
  }, [planChecked, hasProAccess, accountsLoaded, fundedAccounts, user?.id])

  useEffect(() => {
    if (!planChecked || !hasProAccess) return

    const accountIds = isAllAccountsView
      ? accounts.map((account) => account.id)
      : selectedAccount
        ? [selectedAccount.id]
        : []

    if (accountIds.length === 0) {
      setTrades([])
      return
    }

    setTrades([])

    async function loadTrades() {
      setLoadingTrades(true)
      try {
        if (isDemoUserId(user?.id)) {
          setTrades(getDemoPropfirmTrades(accountIds))
          return
        }

        const { data, error } = await supabase
          .from("trades")
          .select(PROPFIRM_TRADE_FIELDS)
          .in("account_id", accountIds)
          .order("trade_date", { ascending: true })
          .order("entry_time", { ascending: true })

        if (error) {
          console.error(error)
          return
        }

        setTrades(data || [])
      } finally {
        setLoadingTrades(false)
      }
    }

    loadTrades()
  }, [
    isAllAccountsView,
    selectedAccount,
    accounts,
    planChecked,
    hasProAccess,
    user?.id,
  ])

  async function handlePayoutSetupSubmit(values: PayoutSetupValues) {
    if (isDemoModeActive()) {
      requestDemoSignup("save")
      return
    }
    if (!selectedAccount) return

    setRecordingPayout(true)
    try {
      const balanceBeforePayout = lifetimeTrailingMetrics.currentBalance
      const drawdownFloorAfterPayout = computePayoutDrawdownFloor(
        values.drawdownBehavior,
        startingBalance,
        cycleTrailingMetrics,
        Number(selectedAccount.max_drawdown) || 0
      )
      const nextCycleNumber =
        activePayoutCycle?.cycle_number != null
          ? activePayoutCycle.cycle_number + 1
          : 1

      const { cycle, accountPreferences, error } = await recordAccountPayout(
        supabase,
        selectedAccount.id,
        {
          balanceAfterPayout: values.balanceAfterPayout,
          payoutAmount: values.payoutAmount,
          drawdownBehavior: values.drawdownBehavior,
          drawdownFloorAfterPayout,
          balanceBeforePayout,
          rememberDrawdownBehavior: values.rememberDrawdownBehavior,
        },
        nextCycleNumber
      )

      if (error || !cycle) {
        console.error(error ?? "Failed to record payout")
        return
      }

      setPayoutCyclesByAccountId((previous) => {
        const accountId = String(selectedAccount.id)
        const previousCycles = previous[accountId] ?? []
        return {
          ...previous,
          [accountId]: applyRecordedPayoutToHistory(
            previousCycles,
            activePayoutCycle,
            cycle,
            {
              amount: values.payoutAmount,
              balanceBefore: balanceBeforePayout,
              balanceAfter: values.balanceAfterPayout,
              drawdownBehavior: values.drawdownBehavior,
              drawdownFloor: drawdownFloorAfterPayout,
              recordedAt: cycle.started_at,
              cycleNumber: nextCycleNumber,
            }
          ),
        }
      })
      if (accountPreferences) {
        setAccounts((prev) =>
          prev.map((acc) =>
            String(acc.id) === String(selectedAccount.id)
              ? {
                  ...acc,
                  payout_drawdown_behavior:
                    accountPreferences.payout_drawdown_behavior,
                  remember_payout_drawdown_behavior:
                    accountPreferences.remember_payout_drawdown_behavior,
                }
              : acc
          )
        )
      }

      setPayoutSetupOpen(false)

      setActiveMilestoneKind("payout")
      setAchievementUploadInitial(
        buildPropFirmMilestoneAchievementInitials("payout", selectedAccount, {
          payoutAmount: values.payoutAmount,
        })
      )
      setAchievementUploadOpen(true)
    } finally {
      setRecordingPayout(false)
    }
  }

  function openPassEvalWorkflow() {
    if (isDemoModeActive()) {
      requestDemoSignup("save")
      return
    }
    if (!selectedAccount) return
    setEvalContinuanceAccount(selectedAccount)
    setActiveMilestoneKind("passed_eval")
    setAchievementUploadInitial(
      buildPropFirmMilestoneAchievementInitials("passed_eval", selectedAccount)
    )
    setAchievementUploadOpen(true)
  }

  function handleAchievementUploadClose() {
    setAchievementUploadOpen(false)
    if (activeMilestoneKind === "passed_eval") {
      setEvalContinuanceAccount(null)
    }
    setActiveMilestoneKind(null)
    setAchievementUploadInitial(undefined)
  }

  async function handleAchievementSaved() {
    const shouldOpenContinuance =
      activeMilestoneKind === "passed_eval" && evalContinuanceAccount != null

    setActiveMilestoneKind(null)
    setAchievementUploadInitial(undefined)

    if (shouldOpenContinuance) {
      setEvalContinuanceOpen(true)
    }
  }

  function closeEvalMilestoneFlow() {
    if (evalContinuanceBusy) return
    setEvalContinuanceOpen(false)
    setEvalRulesChoiceOpen(false)
    setConvertRulesEditorOpen(false)
    setCreateFundedAccountOpen(false)
    setEvalContinuanceAccount(null)
    setConvertRulesSameAsEval(false)
  }

  function handleConvertEvalToFunded() {
    setEvalContinuanceOpen(false)
    setEvalRulesChoiceOpen(true)
  }

  function openConvertRulesEditor(sameAsEval: boolean) {
    setConvertRulesSameAsEval(sameAsEval)
    setEvalRulesChoiceOpen(false)
    setConvertRulesEditorOpen(true)
  }

  async function handleConvertRulesSave(account: CreateTradingAccountPayload) {
    if (isDemoModeActive()) {
      requestDemoSignup("save")
      return
    }
    if (!user?.id || !evalContinuanceAccount) return

    setEvalContinuanceBusy(true)
    try {
      const { account: updated, error } = await convertEvalAccountToFundedWithRules(
        supabase,
        user.id,
        evalContinuanceAccount,
        {
          name: account.name,
          size: account.size,
          id: account.id,
          category: "Prop Firm",
          mode: resolveAccountModeForSave("Prop Firm", "Funded"),
          rules: account.rules,
        }
      )
      if (error || !updated) {
        console.error(error ?? "Failed to convert account")
        return
      }

      const accountId = String(evalContinuanceAccount.id)
      setAccounts((previous) =>
        previous.map((row) =>
          String(row.id) === accountId
            ? tradingListItemToPropfirmAccount(updated, row)
            : row
        )
      )
      setAccountFilter(accountId)
      invalidateAccountsCache(user.id)
      closeEvalMilestoneFlow()
    } finally {
      setEvalContinuanceBusy(false)
    }
  }

  function handleOpenCreateFundedAccount() {
    setEvalContinuanceOpen(false)
    setCreateFundedAccountOpen(true)
  }

  async function handleCreateFundedAccountSave(account: CreateTradingAccountPayload) {
    if (isDemoModeActive()) {
      requestDemoSignup("save")
      return
    }
    if (!user?.id || !evalContinuanceAccount) return

    setEvalContinuanceBusy(true)
    try {
      const { account: created, error } = await insertTradingAccount(
        supabase,
        user.id,
        {
          name: account.name,
          size: account.size,
          id: account.id,
          category: "Prop Firm",
          mode: resolveAccountModeForSave("Prop Firm", "Funded"),
          rules: account.rules,
        }
      )
      if (error || !created) {
        console.error(error ?? "Failed to create funded account")
        return
      }

      setAccounts((previous) => [...previous, created as PropfirmAccount])
      setAccountFilter(String(created.id))
      invalidateAccountsCache(user.id)
      closeEvalMilestoneFlow()
    } finally {
      setEvalContinuanceBusy(false)
    }
  }

  const milestoneUploadConfig = activeMilestoneKind
    ? propFirmMilestoneUploadConfig(activeMilestoneKind)
    : propFirmMilestoneUploadConfig("payout")

  function openPayoutHistory() {
    setPayoutHistoryOpen(true)
  }

  function openPayoutWorkflow() {
    setPayoutSetupOpen(false)
    setPayoutModalOpen(true)
  }

  function closePayoutWorkflow() {
    setPayoutModalOpen(false)
    setPayoutSetupOpen(false)
  }

  function handlePayoutConfirmContinue() {
    setPayoutModalOpen(false)
    setPayoutSetupKey((key) => key + 1)
    setPayoutSetupOpen(true)
  }

  if (!planChecked) {
    return (
      <PropfirmPageShell>
        <SkeletonAnalyticsPage />
      </PropfirmPageShell>
    )
  }

  if (!hasProAccess) {
    return (
      <PropfirmPageShell>
        <LockedFeature title="Prop Firm Mode" className="mx-auto max-w-lg" />
      </PropfirmPageShell>
    )
  }

  const isEmptyAccounts = accountsLoaded && accounts.length === 0

  const drawdownUsed = cycleTrailingMetrics.maxDrawdownUsed
  const { progressPercent, ddPercent } = cycleProgress
  const maxDdLimit = Number(selectedAccount?.max_drawdown) || 0
  const dailyDrawdownBreached =
    worstDailyLossUsed > Number(selectedAccount?.daily_drawdown)
  const winningDaysRequired =
    selectedAccount?.winning_days != null &&
    selectedAccount.winning_days !== "" &&
    Number(selectedAccount.winning_days) > 0
  const consistencyRequired = cycleConsistencyMetrics.ruleActive
  const winningDaysTargetMet =
    !winningDaysRequired ||
    winningDays >= Number(selectedAccount?.winning_days)

  const payoutQualificationInput = {
    cycleProgress,
    dailyDrawdownBreached,
    winningDaysRequired,
    winningDaysTargetMet,
    consistencyRequired,
    consistencyMet: cycleConsistencyMetrics.isConsistent,
  }

  const evalDisplayStatus = isEvalAccountSelected
    ? computePropfirmEvalDisplayStatus(cycleProgress)
    : null

  const fundedDisplayStatus = isFundedAccountSelected
    ? computePropfirmFundedDisplayStatus(payoutQualificationInput)
    : null

  return (
    <PropfirmPageShell>
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">
            Analytics
          </p>
          <h1 className="mt-0.5 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-xl font-semibold text-transparent md:text-3xl">
            Prop Firm Mode
          </h1>
          <p className="mt-1 max-w-2xl text-xs text-gray-400 md:text-base">
            Track rule progress, drawdown room, and account balance from one
            stabilized view.
          </p>
        </div>

        <div className={SECTION_PANEL}>
          <div
            className={
              isEvalAccountSelected
                ? "grid min-w-0 grid-cols-[minmax(0,1fr)_auto] grid-rows-[auto_auto] gap-x-2 gap-y-2.5 sm:flex sm:flex-row sm:items-center sm:gap-3"
                : "flex min-w-0 flex-col gap-2.5 sm:flex-row sm:items-center sm:gap-3"
            }
          >
              <div
                className={
                  isEvalAccountSelected
                    ? "col-start-1 row-start-1 min-w-0 sm:flex-1 sm:basis-0"
                    : "min-w-0 w-full sm:flex-1 sm:basis-0"
                }
              >
                <CustomSelect
                  value={accountFilter}
                  onChange={(value) => {
                    if (value === MANAGE_ACCOUNTS_VALUE) {
                      if (isDemoModeActive()) {
                        requestDemoSignup("save")
                        return
                      }
                      navigateToManageAccounts(router)
                      return
                    }
                    if (value === "__divider__") return
                    setAccountFilter(value)
                  }}
                  placeholder="Select Account"
                  options={accountSelectOptions}
                  triggerClassName={ACCOUNT_DROPDOWN_TRIGGER_COMPACT_CLASS}
                />
              </div>

              {evalDisplayStatus && isEvalAccountSelected ? (
                <div
                  className={`col-start-2 row-start-1 inline-flex w-[108px] shrink-0 items-center justify-center self-center rounded-full border px-2.5 py-1.5 text-xs font-semibold md:px-3 md:text-sm ${
                    evalDisplayStatus === "PASSED"
                      ? "border-green-500/30 bg-green-500/10 text-green-400"
                      : evalDisplayStatus === "FAILED"
                        ? "border-red-500/30 bg-red-500/10 text-red-400"
                        : "border-amber-500/30 bg-amber-500/10 text-amber-300"
                  }`}
                >
                  {evalDisplayStatus}
                </div>
              ) : null}

              <div
                className={
                  isEvalAccountSelected
                    ? "col-span-2 row-start-2 flex w-full sm:col-span-1 sm:row-start-1 sm:w-auto"
                    : "flex min-w-0 w-full flex-wrap items-center gap-2 sm:w-auto sm:flex-nowrap sm:gap-3"
                }
              >
              {!isEvalAccountSelected && showPayoutHistoryButton ? (
                <button
                  type="button"
                  onClick={openPayoutHistory}
                  className="shrink-0 rounded-lg border border-white/10 bg-white/5 px-2.5 py-1.5 text-xs font-semibold text-gray-200 transition hover:bg-white/10 max-sm:min-w-0 max-sm:flex-1 md:px-3 md:text-sm"
                >
                  Payouts
                </button>
              ) : null}

              {!isEvalAccountSelected && fundedDisplayStatus === "FAILED" ? (
                <div className="inline-flex shrink-0 items-center justify-center rounded-full border border-red-500/30 bg-red-500/10 px-2.5 py-1.5 text-xs font-semibold text-red-400 md:px-3 md:text-sm">
                  ❌ Failed
                </div>
              ) : null}

              {!isEvalAccountSelected && fundedDisplayStatus === "PAYOUT_READY" ? (
                <div className="inline-flex shrink-0 items-center justify-center rounded-full border border-emerald-500/30 bg-emerald-500/10 px-2.5 py-1.5 text-xs font-semibold text-emerald-300 md:px-3 md:text-sm">
                  💰 Payout Ready
                </div>
              ) : null}

              {showPassEvalControls ? (
                <button
                  type="button"
                  onClick={openPassEvalWorkflow}
                  className="w-full shrink-0 rounded-lg border border-blue-500/30 bg-blue-500/10 px-3 py-1.5 text-xs font-semibold text-blue-300 transition hover:bg-blue-500/20 sm:w-auto md:px-3.5 md:text-sm"
                >
                  Pass Evaluation
                </button>
              ) : null}

              {showPayoutControls ? (
                <button
                  type="button"
                  onClick={openPayoutWorkflow}
                  className="w-full shrink-0 rounded-lg border border-emerald-500/30 bg-emerald-500/10 px-3 py-1.5 text-xs font-semibold text-emerald-300 transition hover:bg-emerald-500/20 sm:w-auto md:px-3.5 md:text-sm"
                >
                  Record Payout
                </button>
              ) : null}
              </div>
          </div>
        </div>

        <PropFirmPayoutHistoryModal
          open={payoutHistoryOpen}
          onClose={() => setPayoutHistoryOpen(false)}
          subtitle={payoutHistorySubtitle}
          payouts={completedPayoutHistory}
          showAccountNames={isAllAccountsView}
          loading={loadingPayoutHistory}
        />

        <Modal
          open={payoutModalOpen}
          onClose={closePayoutWorkflow}
          title="Record Payout"
          size="sm"
          footer={
            <div className="flex justify-end gap-3">
              <button
                type="button"
                onClick={closePayoutWorkflow}
                className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-gray-200 transition hover:bg-white/10"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handlePayoutConfirmContinue}
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-500"
              >
                Continue
              </button>
            </div>
          }
        >
          <p className="text-sm leading-relaxed text-gray-300">
            Recording a payout will begin a new payout cycle. Historical trades
            and lifetime statistics will remain unchanged. Current payout cycle
            progress will reset.
          </p>
        </Modal>

        <PayoutSetupModal
          key={payoutSetupKey}
          open={payoutSetupOpen}
          onClose={() => {
            if (!recordingPayout) setPayoutSetupOpen(false)
          }}
          onSubmit={handlePayoutSetupSubmit}
          busy={recordingPayout}
          accountBaseBalance={startingBalance}
          balanceBeforePayout={lifetimeTrailingMetrics.currentBalance}
          defaultDrawdownBehavior={resolveDefaultPayoutDrawdownBehavior(
            selectedAccount,
            activePayoutCycle
          )}
          defaultRememberDrawdownBehavior={
            selectedAccount?.remember_payout_drawdown_behavior ?? false
          }
        />

        <AchievementUploadModal
          open={achievementUploadOpen}
          onClose={handleAchievementUploadClose}
          userId={user?.id ?? null}
          initialValues={achievementUploadInitial}
          onSaved={handleAchievementSaved}
          lockAchievementType={milestoneUploadConfig.lockAchievementType}
          dialogTitle={milestoneUploadConfig.dialogTitle}
          dialogSubtitle={milestoneUploadConfig.dialogSubtitle}
          saveLabel={milestoneUploadConfig.saveLabel}
        />

        <PropFirmEvalContinuanceModal
          open={evalContinuanceOpen}
          account={evalContinuanceAccount}
          busy={evalContinuanceBusy}
          onClose={closeEvalMilestoneFlow}
          onConvertToFunded={handleConvertEvalToFunded}
          onCreateNewFundedAccount={handleOpenCreateFundedAccount}
        />

        <PropFirmFundedRulesChoiceModal
          open={evalRulesChoiceOpen}
          busy={evalContinuanceBusy}
          onClose={closeEvalMilestoneFlow}
          onKeepSameRules={() => openConvertRulesEditor(true)}
          onReviewRules={() => openConvertRulesEditor(false)}
        />

        <CreateAccountModal
          open={convertRulesEditorOpen}
          onClose={() => {
            if (!evalContinuanceBusy) {
              setConvertRulesEditorOpen(false)
              setEvalRulesChoiceOpen(true)
            }
          }}
          initialAccount={
            evalContinuanceAccount
              ? buildConvertEvalToFundedFormInitial(evalContinuanceAccount)
              : null
          }
          onSave={handleConvertRulesSave}
          dialogTitle="Funded Account Rules"
          dialogSubtitle={
            convertRulesSameAsEval
              ? "Your evaluation rules are pre-filled below. Press Continue if nothing changed."
              : "Review and update your funded account rules before continuing."
          }
          saveLabel="Continue"
          lockCategory="Prop Firm"
          lockMode="Funded"
        />

        <CreateAccountModal
          open={createFundedAccountOpen}
          onClose={() => {
            if (!evalContinuanceBusy) {
              setCreateFundedAccountOpen(false)
              setEvalContinuanceOpen(true)
            }
          }}
          initialAccount={
            evalContinuanceAccount
              ? buildCreateFundedAccountFormInitial(evalContinuanceAccount)
              : null
          }
          onSave={handleCreateFundedAccountSave}
          dialogTitle="Create Funded Account"
          dialogSubtitle="Your prop firm issued a new funded account. Rules are copied from your evaluation and can be edited before saving."
          lockCategory="Prop Firm"
          lockMode="Funded"
        />

        {loadingTrades ? (
          <SkeletonAnalyticsPage />
        ) : (
          <>
        {showAccountDashboard && (
          <div
            className={`grid gap-3 ${
              showPayoutControls
                ? "grid-cols-2 lg:grid-cols-4"
                : "grid-cols-2 lg:grid-cols-3"
            }`}
          >
            <PropfirmStat
              title="Current Balance"
              value={formatPropfirmUsd(displayCurrentBalance)}
            />
            <PropfirmStat
              title="Current Cycle P&L"
              value={formatPropfirmUsd(cyclePnL)}
              positive={cyclePnL >= 0}
            />
            <PropfirmStat
              title="Cycle Winning Days"
              value={
                winningDaysRequired
                  ? `${winningDays}/${Number(selectedAccount!.winning_days)}`
                  : "—"
              }
              valueClassName={
                !winningDaysRequired
                  ? undefined
                  : winningDaysTargetMet
                    ? "text-green-400"
                    : "text-amber-300"
              }
            />
            {showPayoutControls ? (
              <PropfirmStat
                title={`Payout Total (${payoutSummary.count})`}
                value={formatPropfirmUsd(payoutSummary.totalAmount)}
                positive={payoutSummary.totalAmount > 0}
                onClick={openPayoutHistory}
              />
            ) : null}
          </div>
        )}

        {showAccountDashboard && (
          <PropfirmEquityCurve data={equityCurveData} />
        )}

        {showAccountDashboard && (
          <div className={SECTION_PANEL}>
            <div className="mb-3 flex items-center justify-between gap-2">
              <h2 className={dashboardInsightTitleClass}>Rule Status</h2>
              <span className="rounded-full border border-white/10 bg-white/5 px-2.5 py-0.5 text-xs font-medium uppercase tracking-wide text-gray-400">
                Current Cycle
              </span>
            </div>

            <div className="grid gap-2 sm:grid-cols-2">
              <div
                className={`${RULE_CHIP_CLASS} ${
                  maxDdLimit > 0 && cycleTrailingMetrics.breachedTrailingDD
                    ? "text-red-400"
                    : "text-green-400"
                }`}
              >
                <span aria-hidden>
                  {maxDdLimit > 0 && cycleTrailingMetrics.breachedTrailingDD ? "❌" : "✔"}
                </span>
                <span className="font-medium">Max Drawdown</span>
              </div>

              <div
                className={`${RULE_CHIP_CLASS} ${
                  dailyDrawdownBreached
                    ? "text-red-400"
                    : "text-green-400"
                }`}
              >
                <span aria-hidden>{dailyDrawdownBreached ? "❌" : "✔"}</span>
                <span className="font-medium">Daily Drawdown</span>
              </div>

              <div
                className={`${RULE_CHIP_CLASS} ${
                  !winningDaysRequired
                    ? "text-gray-400"
                    : winningDaysTargetMet
                      ? "text-green-400"
                      : "text-amber-300"
                }`}
              >
                <span aria-hidden>
                  {!winningDaysRequired
                    ? "—"
                    : winningDaysTargetMet
                      ? "✔"
                      : "⚠"}
                </span>
                <span className="font-medium">Winning Days</span>
              </div>

              {consistencyRequired ? (
                <div
                  className={`${RULE_CHIP_CLASS} ${
                    cycleConsistencyMetrics.isConsistent
                      ? "text-green-400"
                      : "text-red-400"
                  }`}
                >
                  <span aria-hidden>
                    {cycleConsistencyMetrics.isConsistent ? "✔" : "✖"}
                  </span>
                  <span className="font-medium">Consistency</span>
                </div>
              ) : null}
            </div>
          </div>
        )}

        {showAccountDashboard && (
          <div className={SECTION_PANEL}>
            <h2 className={`${dashboardInsightTitleClass} mb-3`}>
              Account Rules
            </h2>

            <div className={`grid gap-x-6 gap-y-2.5 sm:grid-cols-2 ${dashboardInsightBodyClass}`}>
              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Account size</span>
                <span className="font-medium text-gray-100">
                  {startingBalance > 0 ? formatPropfirmUsd(startingBalance) : "—"}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Consistency</span>
                <span className="font-medium text-gray-100">
                  {consistencyRequired
                    ? `${selectedAccount!.consistency}%`
                    : "Does Not Apply"}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Max Drawdown</span>
                <span className="font-medium text-gray-100">
                  ${selectedAccount!.max_drawdown}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Daily Drawdown</span>
                <span className="font-medium text-gray-100">
                  ${selectedAccount!.daily_drawdown}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Profit Target</span>
                <span className="font-medium text-gray-100">
                  ${selectedAccount!.profit_target}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Winning Days</span>
                <span className="font-medium text-gray-100">
                  {selectedAccount!.winning_days != null &&
                  selectedAccount!.winning_days !== ""
                    ? selectedAccount!.winning_days
                    : "Does Not Apply"}
                </span>
              </div>

              {selectedAccount!.winning_days != null &&
              selectedAccount!.winning_days !== "" ? (
                <div className="flex justify-between gap-3">
                  <span className={dashboardInsightLabelClass}>
                    Winning Day Threshold
                  </span>
                  <span className="font-medium text-gray-100">
                    {selectedAccount!.winning_day_threshold
                      ? `$${selectedAccount!.winning_day_threshold}`
                      : "Any positive day"}
                  </span>
                </div>
              ) : null}
            </div>
          </div>
        )}

        {showAccountDashboard && (
          <div className={SECTION_PANEL}>
            <h2 className={`${dashboardInsightTitleClass} mb-3`}>
              Progress <span className="text-[10px] font-normal text-gray-500 md:text-xs">(current cycle)</span>
            </h2>

            <div className={`grid gap-x-6 gap-y-2.5 sm:grid-cols-2 ${dashboardInsightBodyClass}`}>
              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Cycle P&L</span>
                <span className={cyclePnL >= 0 ? dashboardInsightMetricPositiveClass : dashboardInsightMetricNegativeClass}>
                  {formatPropfirmUsd(cyclePnL)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Profit Target</span>
                <span className="font-medium text-gray-200">${selectedAccount!.profit_target}</span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Max Drawdown Used</span>
                <span
                  className={
                    maxDdLimit > 0 && drawdownUsed > maxDdLimit
                      ? dashboardInsightMetricNegativeClass
                      : "font-medium text-gray-200"
                  }
                >
                  {formatPropfirmUsd(drawdownUsed)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Drawdown Floor</span>
                <span className="font-medium text-gray-200">
                  {formatPropfirmUsd(cycleTrailingMetrics.drawdownFloor)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Today P&L</span>
                <span className={lifetimeDailyMetrics.todayPnL >= 0 ? dashboardInsightMetricPositiveClass : dashboardInsightMetricNegativeClass}>
                  {formatPropfirmUsd(lifetimeDailyMetrics.todayPnL)}
                </span>
              </div>

              {consistencyRequired ? (
                <>
                  <div className="flex justify-between gap-3">
                    <span className={dashboardInsightLabelClass}>Biggest Trade</span>
                    <span className="font-medium text-gray-200">
                      {formatPropfirmUsd(cycleConsistencyMetrics.biggestWin)}
                    </span>
                  </div>

                  <div className="flex justify-between gap-3">
                    <span className={dashboardInsightLabelClass}>Allowed Max</span>
                    <span className="font-medium text-gray-200">
                      {formatPropfirmUsd(cycleConsistencyMetrics.allowedMax)}
                    </span>
                  </div>

                  <div className="flex justify-between gap-3">
                    <span className={dashboardInsightLabelClass}>Consistency</span>
                    <span
                      className={
                        cycleConsistencyMetrics.isConsistent
                          ? dashboardInsightMetricPositiveClass
                          : dashboardInsightMetricNegativeClass
                      }
                    >
                      {cycleConsistencyMetrics.isConsistent
                        ? "Consistent"
                        : "Not Consistent"}
                    </span>
                  </div>
                </>
              ) : null}
            </div>

            <div className="mt-4 space-y-3">
              <div>
                <div className="mb-1.5 flex justify-between text-[11px] text-gray-400 md:text-sm">
                  <span>Profit target (cycle)</span>
                  <span className="tabular-nums">{progressPercent.toFixed(0)}%</span>
                </div>
                <div className="h-2 w-full overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full bg-gradient-to-r from-blue-500 to-emerald-500 transition-[width] duration-300"
                    style={{ width: `${progressPercent}%` }}
                  />
                </div>
              </div>

              <div>
                <div className="mb-1.5 flex justify-between text-[11px] text-gray-400 md:text-sm">
                  <span>Drawdown used (cycle)</span>
                  <span className="tabular-nums">{ddPercent.toFixed(0)}%</span>
                </div>
                <div className="h-2 w-full overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full bg-red-500 transition-[width] duration-300"
                    style={{ width: `${ddPercent}%` }}
                  />
                </div>
              </div>
            </div>

            {showAccountDashboard &&
              maxDdLimit > 0 &&
              cycleTrailingMetrics.breachedTrailingDD && (
                <div className="mt-4 rounded-lg border border-red-500/20 bg-red-500/10 px-2.5 py-2 text-xs text-red-400 md:px-3 md:py-2.5 md:text-sm">
                  Trailing max drawdown breached (balance below drawdown floor)
                </div>
              )}

            {showAccountDashboard &&
              dailyDrawdownBreached && (
                <div className="mt-2 rounded-lg border border-red-500/20 bg-red-500/10 px-2.5 py-2 text-xs text-red-400 md:px-3 md:py-2.5 md:text-sm">
                  Daily drawdown exceeded
                </div>
              )}
          </div>
        )}

        <div className={SECTION_PANEL}>
          <div className="mb-3 flex items-center justify-between gap-2">
            <div>
              <h2 className={dashboardInsightTitleClass}>Daily Performance</h2>
              <p className="mt-0.5 text-xs text-gray-400 md:text-sm">
                Lifetime — aggregated by trading day
              </p>
            </div>
            <span className="shrink-0 rounded-full border border-white/10 bg-white/5 px-2.5 py-0.5 text-xs font-medium tabular-nums text-gray-300">
              {lifetimeDailyRows.length} days
            </span>
          </div>

          <div className="max-h-64 space-y-1.5 overflow-y-auto pr-1 text-xs md:text-sm">
            {lifetimeDailyRows.length > 0 ? (
              lifetimeDailyRows.map(([date, pnl]) => (
                <div
                  key={date}
                  className={INNER_ROW_CLASS}
                >
                  <span className="font-medium text-gray-300">{date}</span>
                  <span
                    className={
                      pnl >= 0
                        ? dashboardInsightMetricPositiveClass
                        : dashboardInsightMetricNegativeClass
                    }
                  >
                    {formatPnlCurrency(pnl, {
                      minimumFractionDigits: 0,
                      maximumFractionDigits: 2,
                    })}
                  </span>
                </div>
              ))
            ) : (
              <div className="rounded-lg border border-dashed border-white/10 bg-white/5 px-3 py-5 text-center text-xs text-gray-400 md:py-6 md:text-sm">
                No daily performance yet.
              </div>
            )}
          </div>
        </div>

        {isEmptyAccounts ? (
          <EmptyState
            title="No Prop Firm Accounts"
            description="You don't have any Prop Firm accounts yet. Create one in Settings to start tracking rule progress."
            action={
              <Link
                href="/settings#trading-accounts"
                className="inline-flex items-center justify-center rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-600"
              >
                Create Prop Firm Account
              </Link>
            }
          />
        ) : !showAccountDashboard && !isAllAccountsView ? (
          <EmptyState
            title="Select an Account"
            description="Choose a prop firm account above to view drawdown room, rule status, and daily performance."
            className="py-8"
          />
        ) : null}
          </>
        )}
    </PropfirmPageShell>
  )
}
