"use client"

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  getESTDate,
  isExitBeforeEntry,
} from "@/lib/inputTradeDateTime"
import { tradeFormHasFutureDate } from "@/lib/tradeDateValidation"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import {
  saveManualTrade,
  validateQuickTradeInput,
  type ManualTradeAccount,
} from "@/lib/saveManualTrade"
import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import TradeAccountPicker, {
  type TradeAccountOption,
} from "@/app/components/TradeAccountPicker"
import { MODAL_FIXED_BELOW_NAVBAR_CLASS } from "@/app/components/ui/DetailModalShell"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import { FeedbackModal, useFeedbackPopup, buttonVariants } from "@/app/components/ui"
import {
  parseQuickCsvImport,
  type QuickTradeCsvFormPatch,
} from "@/lib/parseQuickCsvPaste"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"
import { handleTradeNumericInput } from "@/lib/formatMoney"
import TradeFormCurrencyInput from "@/app/components/trade/TradeFormCurrencyInput"
import { TRADE_OPTIONAL_ATTACHMENT_LABEL_CLASS } from "@/lib/tradeFormUi"
import { assertCanCreateTradingAccount } from "@/lib/tradingAccounts"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { upsertAccountInCache } from "@/lib/appDataCache"
import { parseOptionalRr } from "@/lib/tradeRr"
import CommunitySharePreviewPanel from "@/app/components/CommunitySharePreviewPanel"
import TradePublicShareToggle from "@/app/components/TradePublicShareToggle"
import TradeReelAttachment from "@/app/components/TradeReelAttachment"
import { publishTradeReel } from "@/lib/reels"
import { buildCommunitySharePreviewPost } from "@/lib/buildCommunitySharePreviewPost"
import { buildDateTime } from "@/lib/inputTradeDateTime"
import { isProActive } from "@/lib/subscription"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

const QUICK_TRADE_PRIMARY_BUTTON_CLASS =
  "h-11 rounded-lg bg-blue-600 px-5 text-sm font-semibold text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-60"

type QuickTradeModalProps = {
  open: boolean
  onClose: () => void
  userId: string | null
  onSaved?: () => void
}

const INPUT_CLASS =
  "h-12 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-base text-white placeholder:text-slate-500 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"

const LABEL_CLASS = "block text-xs font-medium text-gray-300"

const FIELD_PAIR_ROW_CLASS = "grid grid-cols-1 gap-4 sm:grid-cols-2 sm:gap-5"

const FIELD_TRIPLE_ROW_CLASS = "grid grid-cols-1 gap-4 sm:grid-cols-3 sm:gap-5"

const QUICK_CURRENCY_INPUT_CLASS = `${INPUT_CLASS} mt-2 pl-8 tabular-nums`

const QUICK_CSV_BUTTON_CLASS = buttonVariants({
  variant: "secondary",
  size: "md",
  className: "h-11 flex-1 font-medium",
})

function csvPatchHasPrices(patch: QuickTradeCsvFormPatch): boolean {
  return Boolean(patch.entryPrice.trim() || patch.exitPrice.trim())
}

function toManualTradeAccount(account: TradeAccountOption): ManualTradeAccount {
  return {
    name: account.name,
    size: account.size,
    id: account.id,
    account_number: account.account_number ?? null,
    mode: String(account.mode ?? "live"),
    category: account.category ?? null,
  }
}

function inferPreviewDirection(
  entryPrice: string,
  exitPrice: string
): string {
  const entry = Number(entryPrice.replace(/,/g, "").replace(/\$/g, ""))
  const exit = Number(exitPrice.replace(/,/g, "").replace(/\$/g, ""))
  if (Number.isFinite(entry) && Number.isFinite(exit)) {
    return exit >= entry ? "Long" : "Short"
  }
  return "Long"
}

function FieldLabel({
  children,
  htmlFor,
  className,
}: {
  children: ReactNode
  htmlFor?: string
  className?: string
}) {
  const labelClass = className ?? LABEL_CLASS
  if (htmlFor) {
    return (
      <label htmlFor={htmlFor} className={labelClass}>
        {children}
      </label>
    )
  }
  return <p className={labelClass}>{children}</p>
}

function TimeField({
  id,
  label,
  value,
  onChange,
}: {
  id: string
  label: string
  value: string
  onChange: (value: string) => void
}) {
  return (
    <div>
      <FieldLabel htmlFor={id}>{label}</FieldLabel>
      <div
        className="relative mt-2 cursor-pointer"
        onClick={() => openTimePicker(id)}
      >
        <input
          id={id}
          type="time"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className={`${INPUT_CLASS} pr-10`}
        />
        <span
          className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-gray-400"
          aria-hidden
        >
          🕒
        </span>
      </div>
    </div>
  )
}

function openTimePicker(id: string) {
  const el = document.getElementById(id) as HTMLInputElement | null
  el?.showPicker?.()
}

export default function QuickTradeModal({
  open,
  onClose,
  userId,
  onSaved,
}: QuickTradeModalProps) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const csvFileInputRef = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [advancedOpen, setAdvancedOpen] = useState(false)
  const [accounts, setAccounts] = useState<TradeAccountOption[]>([])
  const [selectedAccount, setSelectedAccount] =
    useState<TradeAccountOption | null>(null)
  const [accountLoading, setAccountLoading] = useState(false)
  const [showCreateAccountModal, setShowCreateAccountModal] = useState(false)
  const [creatingAccount, setCreatingAccount] = useState(false)
  const creatingAccountRef = useRef(false)

  const [ticker, setTicker] = useState("")
  const [pnl, setPnl] = useState("")
  const [decimalError, setDecimalError] = useState("")
  const [points, setPoints] = useState("")
  const [contracts, setContracts] = useState("")
  const [rr, setRr] = useState("")
  const [entryDate, setEntryDate] = useState(getESTDate())
  const [exitDate, setExitDate] = useState(getESTDate())
  const [entryTime, setEntryTime] = useState("")
  const [exitTime, setExitTime] = useState("")
  const [entryPrice, setEntryPrice] = useState("")
  const [exitPrice, setExitPrice] = useState("")
  const [description, setDescription] = useState("")
  const [isPublic, setIsPublic] = useState(false)
  const [image, setImage] = useState<File | null>(null)
  const [pendingReelFile, setPendingReelFile] = useState<File | null>(null)
  const pendingReelFileRef = useRef<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [csvPasteOpen, setCsvPasteOpen] = useState(false)
  const [csvPasteText, setCsvPasteText] = useState("")
  const [csvImportError, setCsvImportError] = useState<string | null>(null)
  const [planProfile, setPlanProfile] = useState<{
    is_pro?: boolean | null
    subscription_status?: string | null
    locked_account_type?: string | null
    username?: string | null
    avatar_url?: string | null
  } | null>(null)

  const { showPopup, feedbackModalProps } = useFeedbackPopup()

  const resetForm = useCallback(() => {
    const today = getESTDate()
    setTicker("")
    setPnl("")
    setPoints("")
    setContracts("")
    setRr("")
    setEntryDate(today)
    setExitDate(today)
    setEntryTime("")
    setExitTime("")
    setEntryPrice("")
    setExitPrice("")
    setDescription("")
    setIsPublic(false)
    setImage(null)
    setPendingReelFile(null)
    setPreviewUrl(null)
    setAdvancedOpen(false)
    setError(null)
    setSelectedAccount(null)
    setCsvPasteOpen(false)
    setCsvPasteText("")
    setCsvImportError(null)
    setPlanProfile(null)
  }, [])

  useEffect(() => {
    pendingReelFileRef.current = pendingReelFile
  }, [pendingReelFile])

  const loadAccounts = useCallback(async (uid: string) => {
    setAccountLoading(true)
    const { data, error: fetchErr } = await supabase
      .from("accounts")
      .select("*")
      .eq("user_id", uid)

    if (fetchErr) {
      console.error("[QuickTradeModal] accounts fetch:", fetchErr)
      setAccounts([])
      setAccountLoading(false)
      return
    }

    const rows = (data ?? [])
      .filter((acc) => acc.is_active !== false)
      .map((acc) => ({
        name: String(acc.name ?? ""),
        size: String(acc.account_size ?? ""),
        id: String(acc.id),
        account_number: acc.account_number ?? null,
        mode: acc.mode ?? "live",
        category: acc.category ?? null,
      }))

    setAccounts(rows)
    setAccountLoading(false)
  }, [])

  const loadPlanProfile = useCallback(async (uid: string) => {
    const { data } = await supabase
      .from("profiles")
      .select(
        "is_pro, subscription_status, locked_account_type, username, avatar_url"
      )
      .eq("id", uid)
      .maybeSingle()
    setPlanProfile(data ?? null)
  }, [])

  useEffect(() => {
    if (!open) return
    resetForm()
  }, [open, resetForm])

  useEffect(() => {
    if (!open || !userId) return
    void loadAccounts(userId)
    void loadPlanProfile(userId)
  }, [open, userId, loadAccounts, loadPlanProfile])

  useEffect(() => {
    if (!image) {
      setPreviewUrl(null)
      return
    }
    const url = URL.createObjectURL(image)
    setPreviewUrl(url)
    return () => URL.revokeObjectURL(url)
  }, [image])

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [open])

  const previewDirection = useMemo(
    () => inferPreviewDirection(entryPrice, exitPrice),
    [entryPrice, exitPrice]
  )

  const communityPreviewPost = useMemo(() => {
    if (!userId) return null
    const previewEntryTime = entryTime
      ? buildDateTime(entryDate, entryTime)
      : null
    const previewExitTime = exitTime ? buildDateTime(exitDate, exitTime) : null
    return buildCommunitySharePreviewPost({
      userId,
      username: String(planProfile?.username ?? "").trim() || "User",
      avatarUrl: planProfile?.avatar_url ?? null,
      pnl,
      rr,
      points,
      ticker,
      direction: previewDirection,
      accountMode: selectedAccount?.mode,
      accountType: selectedAccount?.category ?? null,
      lockedAccountType: planProfile?.locked_account_type,
      isPro: isProActive(planProfile),
      publicDescription: description,
      imageUrl: previewUrl,
      entryTime: previewEntryTime,
      exitTime: previewExitTime,
      entryPrice: entryPrice.trim() === "" ? null : entryPrice,
      exitPrice: exitPrice.trim() === "" ? null : exitPrice,
      tradeDate: entryDate,
    })
  }, [
    userId,
    planProfile?.username,
    planProfile?.avatar_url,
    planProfile?.locked_account_type,
    planProfile,
    pnl,
    rr,
    points,
    ticker,
    previewDirection,
    selectedAccount,
    description,
    previewUrl,
    entryDate,
    entryTime,
    exitDate,
    exitTime,
    entryPrice,
    exitPrice,
  ])

  const communityPreviewUser = useMemo(
    () => (userId ? { id: userId } : null),
    [userId]
  )

  function handleClose() {
    if (busy) return
    onClose()
  }

  function applyQuickCsvPatch(patch: QuickTradeCsvFormPatch) {
    setCsvImportError(null)
    setError(null)
    setTicker(patch.ticker)
    setPnl(patch.pnl)
    setPoints(patch.points)
    setContracts(patch.contracts)
    setRr(patch.rr)
    setEntryDate(patch.entryDate || getESTDate())
    setExitDate(patch.exitDate || patch.entryDate || getESTDate())
    setEntryTime(patch.entryTime)
    setExitTime(patch.exitTime)
    setEntryPrice(patch.entryPrice)
    setExitPrice(patch.exitPrice)
    if (csvPatchHasPrices(patch)) {
      setAdvancedOpen(true)
    }
  }

  function handleAutoFillFromCsvPaste() {
    const result = parseQuickCsvImport(csvPasteText)
    if (!result.ok) {
      setCsvImportError(result.message)
      return
    }
    applyQuickCsvPatch(result.patch)
  }

  function handleUploadCsvClick() {
    csvFileInputRef.current?.click()
  }

  function handlePasteCsvClick() {
    setCsvPasteOpen((prev) => !prev)
    setCsvImportError(null)
  }

  async function handleCsvFileSelected(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    e.target.value = ""
    if (!file) return

    setCsvImportError(null)

    const name = file.name.trim().toLowerCase()
    if (!name.endsWith(".csv")) {
      setCsvImportError("Please upload a CSV file.")
      return
    }

    let text: string
    try {
      text = await file.text()
    } catch {
      setCsvImportError("Unable to read this CSV row.")
      return
    }

    const result = parseQuickCsvImport(text)
    if (!result.ok) {
      setCsvImportError(result.message)
      return
    }
    applyQuickCsvPatch(result.patch)
  }

  async function handleCreateAccountSave(newAccount: CreateAccountSavePayload) {
    if (isDemoModeActive()) {
      requestDemoSignup("save")
      return
    }
    if (creatingAccountRef.current || creatingAccount || !userId) return

    creatingAccountRef.current = true
    setCreatingAccount(true)

    try {
      const { data: profile } = await supabase
        .from("profiles")
        .select("is_pro, subscription_status")
        .eq("id", userId)
        .maybeSingle()

      const gate = await assertCanCreateTradingAccount(supabase, userId, profile)
      if (!gate.ok) {
        showPopup(feedbackPresets.accountLimit())
        return
      }

      const { data, error: insertErr } = await supabase
        .from("accounts")
        .insert([
          {
            user_id: userId,
            name: newAccount.name,
            account_size: newAccount.size,
            account_number: newAccount.id,
            category: newAccount.category,
            mode: newAccount.mode,
            is_active: true,
            consistency: newAccount.rules?.consistency ?? null,
            max_drawdown: newAccount.rules?.maxDrawdown ?? null,
            daily_drawdown: newAccount.rules?.dailyDrawdown ?? null,
            profit_target: newAccount.rules?.profitTarget ?? null,
            winning_days: newAccount.rules?.winningDays ?? null,
            winning_day_threshold: newAccount.rules?.winningDayThreshold ?? null,
          },
        ])
        .select()
        .single()

      if (insertErr) {
        console.error(insertErr)
        showPopup(
          persistentError("Save Failed", handleSupabaseError(insertErr))
        )
        return
      }

      if (!data) return

      upsertAccountInCache(userId, data)

      const createdAccount: TradeAccountOption = {
        name: data.name,
        size: data.account_size,
        id: String(data.id),
        account_number: data.account_number ?? null,
        mode: data.mode,
        category: data.category,
      }

      setAccounts((prev) => [...prev, createdAccount])
      setSelectedAccount(createdAccount)
      setShowCreateAccountModal(false)
    } finally {
      creatingAccountRef.current = false
      setCreatingAccount(false)
    }
  }

  async function handleSave() {
    if (isDemoModeActive()) {
      requestDemoSignup("trade")
      return
    }
    if (busy || !userId) return

    if (!selectedAccount) {
      showPopup({
        type: "error",
        title: "Trading Account Required",
        message:
          "Please select the Trading Account you would like to save this trade to before continuing.",
        persist: true,
        dismissLabel: "OK",
      })
      return
    }

    const validationError = validateQuickTradeInput({
      ticker,
      pnl,
      points,
      contracts,
    })
    if (validationError) {
      setError(validationError)
      return
    }

    if (rr.trim() !== "" && parseOptionalRr(rr) === null) {
      setError("Enter a valid RR value.")
      return
    }

    if (
      entryTime &&
      exitTime &&
      isExitBeforeEntry(entryDate, entryTime, exitDate, exitTime)
    ) {
      setError("Exit date and time must be after entry date and time.")
      return
    }

    if (tradeFormHasFutureDate({ entryDate, exitDate })) {
      setError("Trade date cannot be in the future.")
      return
    }

    setBusy(true)
    setError(null)

    const parsedPnl = Number(String(pnl).replace(/,/g, "").replace(/\$/g, ""))
    const parsedPoints = Number(String(points).replace(/,/g, ""))
    const parsedContracts = Number.parseInt(
      String(contracts).replace(/,/g, ""),
      10
    )
    const entryVal =
      entryPrice.trim() === ""
        ? null
        : Number(entryPrice.replace(/,/g, "").replace(/\$/g, ""))
    const exitVal =
      exitPrice.trim() === ""
        ? null
        : Number(exitPrice.replace(/,/g, "").replace(/\$/g, ""))

    const result = await saveManualTrade(
      supabase,
      userId,
      toManualTradeAccount(selectedAccount),
      {
      ticker: ticker.trim().toUpperCase(),
      pnl: parsedPnl,
      points: parsedPoints,
      contracts: parsedContracts,
      entryDate,
      exitDate,
      entryTime: entryTime || undefined,
      exitTime: exitTime || undefined,
      entryPrice:
        entryVal != null && Number.isFinite(entryVal) ? entryVal : null,
      exitPrice: exitVal != null && Number.isFinite(exitVal) ? exitVal : null,
      rr: parseOptionalRr(rr),
      publicDescription: description,
      isPublic,
      imageFile: image,
    }
    )

    if (!result.ok) {
      setBusy(false)
      if (result.code === "account_limit") {
        showPopup(feedbackPresets.accountLimit())
      } else if (result.code === "account_locked") {
        showPopup(feedbackPresets.accountLocked())
      } else {
        showPopup(persistentError("Save Failed", result.message))
      }
      return
    }

    console.log("[QuickTradeModal] trade created", {
      tradeId: result.trade?.id,
      posted: result.posted,
    })

    const reelFile = pendingReelFileRef.current ?? pendingReelFile
    if (reelFile && result.trade?.id) {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      const authUserId = user?.id ?? userId

      if (!authUserId) {
        setBusy(false)
        showPopup(
          persistentError(
            "Replay Upload Failed",
            "Trade saved, but you must be signed in to upload a replay."
          )
        )
        onSaved?.()
        onClose()
        return
      }

      console.log("[QuickTradeModal] replay upload starting", {
        tradeId: result.trade.id,
        userId: authUserId,
        fileName: reelFile.name,
      })

      const reelResult = await publishTradeReel(supabase, {
        tradeId: String(result.trade.id),
        userId: authUserId,
        file: reelFile,
      })
      if ("error" in reelResult) {
        setBusy(false)
        console.error("[QuickTradeModal] replay upload failed", reelResult.error)
        showPopup(
          persistentError(
            "Replay Upload Failed",
            `Trade saved, but replay could not be uploaded: ${reelResult.error}`
          )
        )
        onSaved?.()
        onClose()
        return
      }

      console.log("[QuickTradeModal] replay upload succeeded", {
        reelId: reelResult.reel.id,
        tradeId: reelResult.reel.trade_id,
      })
    } else if (!reelFile) {
      console.log("[QuickTradeModal] no replay file attached at save time")
    }

    setBusy(false)

    notifyGettingStartedChecklistMaybeCompleted()
    showPopup(
      result.posted
        ? feedbackPresets.postPublished()
        : feedbackPresets.tradeSaveSuccess()
    )
    onSaved?.()
    onClose()
  }

  if (!open) return null

  const invalidTimeRange =
    entryTime &&
    exitTime &&
    isExitBeforeEntry(entryDate, entryTime, exitDate, exitTime)

  return (
    <>
      <div
        className={`${MODAL_FIXED_BELOW_NAVBAR_CLASS} z-[150] bg-black/75 p-3 backdrop-blur-md sm:p-4`}
        onClick={handleClose}
      >
        <div
          className="max-h-[min(92vh,calc(100dvh-5rem))] w-full max-w-lg overflow-y-auto rounded-2xl border border-white/10 bg-gradient-to-br from-[#0f172a] via-[#0b1532] to-[#0a2230] p-4 shadow-2xl shadow-blue-900/20 sm:max-w-xl sm:p-6 md:max-w-2xl"
          onClick={(e) => e.stopPropagation()}
          role="dialog"
          aria-modal="true"
          aria-label="Quick Trade"
        >
          <div className="mb-5 border-b border-white/10 pb-4">
            <h2 className="text-xl font-semibold tracking-tight text-white">
              Quick Trade
            </h2>
            <p className="mt-1 text-sm text-slate-300">
              Log the essentials in under 30 seconds.
            </p>
          </div>

          {error ? (
            <div className="mb-4 rounded-lg border border-red-400/30 bg-red-500/10 p-3 text-sm text-red-200">
              {error}
            </div>
          ) : null}

          <div className="space-y-5">
            <div>
              <FieldLabel>Trading Account</FieldLabel>
              <TradeAccountPicker
                className="mt-2"
                accounts={accounts}
                selectedAccount={selectedAccount}
                onSelect={setSelectedAccount}
                onOpenCreate={() => setShowCreateAccountModal(true)}
                showExternalCreateButton={false}
              />
            </div>

            <div className="rounded-xl border border-white/10 bg-white/[0.03] px-4 py-4">
              <p className="text-sm font-medium text-white">Quick CSV Import</p>
              <p className="mt-1 text-sm leading-relaxed text-gray-400">
                Quickly autofill this trade using a single trade from your broker.
              </p>
              <div className="mt-3 flex flex-col gap-2 sm:flex-row">
                <button
                  type="button"
                  onClick={handleUploadCsvClick}
                  className={QUICK_CSV_BUTTON_CLASS}
                >
                  Upload CSV
                </button>
                <button
                  type="button"
                  onClick={handlePasteCsvClick}
                  className={QUICK_CSV_BUTTON_CLASS}
                >
                  Paste CSV
                </button>
              </div>
              <input
                ref={csvFileInputRef}
                type="file"
                accept=".csv,text/csv"
                className="hidden"
                onChange={(e) => void handleCsvFileSelected(e)}
              />
              {csvImportError ? (
                <p className="mt-3 text-xs leading-relaxed text-red-400">
                  {csvImportError}
                </p>
              ) : null}
              {csvPasteOpen ? (
                <div className="mt-4 space-y-3 border-t border-white/10 pt-4">
                  <FieldLabel htmlFor="quick-csv-paste">Paste CSV Row</FieldLabel>
                  <textarea
                    id="quick-csv-paste"
                    rows={4}
                    value={csvPasteText}
                    onChange={(e) => {
                      setCsvPasteText(e.target.value)
                      if (csvImportError) setCsvImportError(null)
                    }}
                    placeholder={`Symbol,Entry Time,Exit Time,Contracts,Points,PnL\nES,2026-07-01 09:35,2026-07-01 09:48,2,18.5,450`}
                    className="w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 py-3 font-mono text-sm text-white placeholder:text-slate-500 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
                  />
                  <button
                    type="button"
                    onClick={handleAutoFillFromCsvPaste}
                    disabled={!csvPasteText.trim()}
                    className={buttonVariants({
                      variant: "secondary",
                      size: "md",
                      className:
                        "h-11 w-full font-medium disabled:cursor-not-allowed sm:w-auto sm:px-5",
                    })}
                  >
                    Auto Fill
                  </button>
                </div>
              ) : null}
            </div>

            {/* Row 1: Symbol · P&L */}
            <div className={FIELD_PAIR_ROW_CLASS}>
              <div>
                <FieldLabel htmlFor="quick-trade-symbol">Symbol</FieldLabel>
                <input
                  id="quick-trade-symbol"
                  type="text"
                  value={ticker}
                  onChange={(e) => setTicker(e.target.value.toUpperCase())}
                  placeholder="ES, NQ, AAPL"
                  className={`${INPUT_CLASS} mt-2 uppercase`}
                />
              </div>
              <div>
                <FieldLabel htmlFor="quick-trade-pnl">P&amp;L</FieldLabel>
                <TradeFormCurrencyInput
                  id="quick-trade-pnl"
                  value={pnl}
                  onChange={setPnl}
                  allowNegative
                  onDecimalError={setDecimalError}
                  inputClassName={QUICK_CURRENCY_INPUT_CLASS}
                />
                {decimalError ? (
                  <p className="mt-1 text-xs text-red-400">{decimalError}</p>
                ) : null}
              </div>
            </div>

            {/* Row 2: Points · Contracts · RR */}
            <div className={FIELD_TRIPLE_ROW_CLASS}>
              <div>
                <FieldLabel htmlFor="quick-trade-points">Points</FieldLabel>
                <input
                  id="quick-trade-points"
                  type="text"
                  inputMode="decimal"
                  value={points}
                  onChange={(e) => {
                    const v = e.target.value.replace(/,/g, "")
                    if (/^-?\d*\.?\d*$/.test(v) || v === "-") setPoints(v)
                  }}
                  placeholder="12.5"
                  className={`${INPUT_CLASS} mt-2 tabular-nums`}
                />
              </div>
              <div>
                <FieldLabel htmlFor="quick-trade-contracts">Contracts</FieldLabel>
                <input
                  id="quick-trade-contracts"
                  type="text"
                  inputMode="numeric"
                  value={contracts}
                  onChange={(e) => {
                    const v = e.target.value.replace(/,/g, "")
                    if (/^\d*$/.test(v)) setContracts(v)
                  }}
                  placeholder="2"
                  className={`${INPUT_CLASS} mt-2 tabular-nums`}
                />
              </div>
              <div>
                <FieldLabel htmlFor="quick-trade-rr">RR</FieldLabel>
                <input
                  id="quick-trade-rr"
                  type="text"
                  inputMode="decimal"
                  value={rr}
                  onChange={(e) =>
                    handleTradeNumericInput(e.target.value, setRr, {
                      allowDecimal: true,
                    })
                  }
                  placeholder="2.5"
                  className={`${INPUT_CLASS} mt-2 tabular-nums`}
                />
              </div>
            </div>

            {/* Row 3: Entry date · Entry time */}
            <div className={FIELD_PAIR_ROW_CLASS}>
              <div>
                <FieldLabel htmlFor="quick-entry-date">Entry Date</FieldLabel>
                <NativeDateInput
                  id="quick-entry-date"
                  className="mt-2 h-12 rounded-lg"
                  value={entryDate}
                  onChange={(e) => setEntryDate(e.target.value)}
                />
              </div>
              <TimeField
                id="quick-entry-time"
                label="Entry Time"
                value={entryTime}
                onChange={setEntryTime}
              />
            </div>

            {/* Row 4: Exit date · Exit time */}
            <div className={FIELD_PAIR_ROW_CLASS}>
              <div>
                <FieldLabel htmlFor="quick-exit-date">Exit Date</FieldLabel>
                <NativeDateInput
                  id="quick-exit-date"
                  className="mt-2 h-12 rounded-lg"
                  value={exitDate}
                  onChange={(e) => setExitDate(e.target.value)}
                />
              </div>
              <TimeField
                id="quick-exit-time"
                label="Exit Time"
                value={exitTime}
                onChange={setExitTime}
              />
            </div>
            {invalidTimeRange ? (
              <p className="-mt-2 text-xs text-red-400">
                Exit must be after entry.
              </p>
            ) : null}

            {/* Advanced */}
            <div className="rounded-xl border border-white/10 bg-white/[0.03]">
              <button
                type="button"
                onClick={() => setAdvancedOpen((prev) => !prev)}
                className="flex w-full items-center justify-between px-4 py-3.5 text-left text-sm font-medium text-gray-200"
                aria-expanded={advancedOpen}
              >
                Advanced Details
                <span className="text-gray-500" aria-hidden>
                  {advancedOpen ? "▲" : "▼"}
                </span>
              </button>
              {advancedOpen ? (
                <div
                  className={`${FIELD_PAIR_ROW_CLASS} border-t border-white/10 px-4 pb-4 pt-3`}
                >
                  <div>
                    <FieldLabel htmlFor="quick-entry-price">Entry Price</FieldLabel>
                    <TradeFormCurrencyInput
                      id="quick-entry-price"
                      value={entryPrice}
                      onChange={setEntryPrice}
                      onDecimalError={setDecimalError}
                      inputClassName={QUICK_CURRENCY_INPUT_CLASS}
                    />
                  </div>
                  <div>
                    <FieldLabel htmlFor="quick-exit-price">Exit Price</FieldLabel>
                    <TradeFormCurrencyInput
                      id="quick-exit-price"
                      value={exitPrice}
                      onChange={setExitPrice}
                      onDecimalError={setDecimalError}
                      inputClassName={QUICK_CURRENCY_INPUT_CLASS}
                    />
                  </div>
                </div>
              ) : null}
            </div>

            {/* Row 5: Upload image */}
            <div>
              <FieldLabel className={TRADE_OPTIONAL_ATTACHMENT_LABEL_CLASS}>
                Screenshot (Optional)
              </FieldLabel>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => setImage(e.target.files?.[0] ?? null)}
              />
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                className="mt-2 h-12 w-full rounded-lg border border-dashed border-white/20 bg-white/5 text-sm font-medium text-gray-200 transition hover:bg-white/10"
              >
                {image ? "Change image" : "Upload image"}
              </button>
              {previewUrl ? (
                <img
                  src={previewUrl}
                  alt="Trade screenshot preview"
                  className="mt-3 max-h-32 w-full rounded-lg border border-white/10 object-cover"
                />
              ) : null}

              <TradeReelAttachment
                variant="quick"
                disabled={busy}
                pendingFile={pendingReelFile}
                onPendingFileChange={setPendingReelFile}
                labelClassName={TRADE_OPTIONAL_ATTACHMENT_LABEL_CLASS}
              />
            </div>

            {/* Row 6: Description */}
            <div>
              <FieldLabel htmlFor="quick-trade-description">
                Description (optional)
              </FieldLabel>
              <textarea
                id="quick-trade-description"
                rows={3}
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Quick note for your journal or profile..."
                className="mt-2 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 py-3 text-base text-white placeholder:text-slate-500 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
              />
            </div>

            {/* Share to Community */}
            <TradePublicShareToggle
              isPublic={isPublic}
              onToggle={() => setIsPublic((prev) => !prev)}
            />

            {isPublic ? (
              <CommunitySharePreviewPanel
                post={communityPreviewPost}
                user={communityPreviewUser}
              />
            ) : null}
          </div>

          <div className="mt-6 flex flex-col-reverse gap-3 border-t border-white/10 pt-5 sm:flex-row sm:justify-end">
            <button
              type="button"
              disabled={busy}
              onClick={handleClose}
              className="h-11 rounded-lg border border-white/20 bg-white/5 px-4 text-sm font-medium text-slate-200 transition hover:bg-white/10 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={busy || accountLoading}
              onClick={() => void handleSave()}
              className={QUICK_TRADE_PRIMARY_BUTTON_CLASS}
            >
              {busy
                ? isPublic
                  ? "Posting..."
                  : "Saving..."
                : isPublic
                  ? "Post Trade"
                  : "Save Trade"}
            </button>
          </div>
        </div>
      </div>
      <CreateAccountModal
        open={showCreateAccountModal}
        onClose={() => setShowCreateAccountModal(false)}
        onSave={handleCreateAccountSave}
      />
      <FeedbackModal {...feedbackModalProps} overlayClassName="z-[200]" />
    </>
  )
}
