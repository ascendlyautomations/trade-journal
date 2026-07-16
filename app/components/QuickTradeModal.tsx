"use client"

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  getESTDate,
} from "@/lib/inputTradeDateTime"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import {
  saveManualTrade,
  type ManualTradeAccount,
} from "@/lib/saveManualTrade"
import {
  validateQuickTradeForm,
  type QuickTradeValidationFailure,
} from "@/lib/validateQuickTradeForm"
import { focusQuickTradeField } from "@/lib/quickTradeFieldFocus"
import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import TradeAccountPicker, {
  type TradeAccountOption,
} from "@/app/components/TradeAccountPicker"
import CustomSelect from "@/app/components/CustomSelect"
import { SELECT_TRIGGER_COMPACT_CLASS } from "@/lib/accountDropdownStyles"
import ScrollableModalShell from "@/app/components/ui/ScrollableModalShell"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import NativeTimeInput from "@/app/components/ui/NativeTimeInput"
import { FeedbackModal, useFeedbackPopup, buttonVariants } from "@/app/components/ui"
import {
  parseQuickCsvImport,
  type QuickTradeCsvFormPatch,
} from "@/lib/parseQuickCsvPaste"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"
import { handleTradeNumericInput } from "@/lib/formatMoney"
import TradeFormCurrencyInput from "@/app/components/trade/TradeFormCurrencyInput"
import {
  QUICK_TRADE_INPUT_CLASS,
  QUICK_TRADE_LABEL_CLASS,
  TRADE_OPTIONAL_ATTACHMENT_LABEL_CLASS,
} from "@/lib/tradeFormUi"
import {
  READABLE_PLACEHOLDER_CLASS,
  READABLE_SECONDARY_CLASS,
} from "@/lib/readableTextStyles"
import { cn } from "@/app/components/ui/cn"
import { assertCanCreateTradingAccount, FREE_PLAN_ACCOUNT_LIMIT } from "@/lib/tradingAccounts"
import { assertRequiredAccountValue } from "@/lib/createAccountForm"
import {
  countTradeEntryEnabledAccounts,
  filterAccountsForTradeEntry,
} from "@/lib/freePlanAccountSlots"
import { supabaseMutationFeedback } from "@/lib/supabaseMutationFeedback"
import { upsertAccountInCache } from "@/lib/appDataCache"
import { parseOptionalRr } from "@/lib/tradeRr"
import {
  inferTradeDirectionFromPrices,
  nextDirectionAfterPriceChange,
  parseTradePriceInput,
  type TradeDirection,
} from "@/lib/inferTradeDirection"
import CommunitySharePreviewModal from "@/app/components/CommunitySharePreviewModal"
import TradePublicShareToggle from "@/app/components/TradePublicShareToggle"
import TradeReelAttachment from "@/app/components/TradeReelAttachment"
import { publishTradeReel } from "@/lib/reels"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import { buildCommunitySharePreviewPost } from "@/lib/buildCommunitySharePreviewPost"
import { buildDateTime } from "@/lib/inputTradeDateTime"
import { isProActive } from "@/lib/subscription"
import { useCopyTradingGroups } from "@/lib/useCopyTradingGroups"
import {
  resolveCopyGroupAccounts,
} from "@/lib/copyTradingGroups"
import { insertCopyTradedTrades } from "@/lib/tradeCopyTrading"
import type { TradingAccountListItem } from "@/lib/tradingAccounts"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import ImageCropModal from "@/app/components/ImageCropModal"
import { CONTENT_IMAGE_CROP_PRESET } from "@/lib/contentImagePipeline"
import { useTradeImageCropUpload } from "@/lib/useTradeImageCropUpload"

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

const QUICK_TRADE_PRIMARY_BUTTON_CLASS =
  "h-11 rounded-lg bg-blue-600 px-5 text-sm font-semibold text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-60"

type QuickTradeModalProps = {
  open: boolean
  onClose: () => void
  userId: string | null
  onSaved?: () => void
  /** Prefill from a single-trade CSV import (consumed when the modal opens). */
  initialCsvPatch?: QuickTradeCsvFormPatch | null
}

const INPUT_CLASS = QUICK_TRADE_INPUT_CLASS

const LABEL_CLASS = QUICK_TRADE_LABEL_CLASS

const FIELD_PAIR_ROW_CLASS = "grid grid-cols-1 gap-4 sm:grid-cols-2 sm:gap-5"

/** Points · Contracts · RR · Direction — compact two-up on narrow, four-up from `sm`. */
const FIELD_METRICS_ROW_CLASS = "grid grid-cols-2 gap-4 sm:grid-cols-4 sm:gap-5"

const QUICK_CURRENCY_INPUT_CLASS = `${INPUT_CLASS} mt-2 pl-8 tabular-nums`

const QUICK_CSV_BUTTON_CLASS = buttonVariants({
  variant: "secondary",
  size: "md",
  className: "h-11 flex-1 font-medium",
})

function resolveQuickTradeAccountFromCsvPatch(
  accounts: TradeAccountOption[],
  patch: Pick<QuickTradeCsvFormPatch, "accountId" | "accountName">
): TradeAccountOption | null {
  if (patch.accountId) {
    const byId = accounts.find((row) => String(row.id) === String(patch.accountId))
    if (byId) return byId
  }

  const normalizedName = patch.accountName?.trim().toLowerCase()
  if (normalizedName) {
    const byName = accounts.find(
      (row) => row.name.trim().toLowerCase() === normalizedName
    )
    if (byName) return byName
  }

  return null
}

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
      <NativeTimeInput
        id={id}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="mt-2 h-12 rounded-lg"
      />
    </div>
  )
}

export default function QuickTradeModal({
  open,
  onClose,
  userId,
  onSaved,
  initialCsvPatch = null,
}: QuickTradeModalProps) {
  const csvFileInputRef = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const uploadingRef = useRef(false)
  const { runUpload } = useUploadProgress()
  const [advancedOpen, setAdvancedOpen] = useState(false)
  const [accounts, setAccounts] = useState<TradeAccountOption[]>([])
  const [entryEnabledAccountCount, setEntryEnabledAccountCount] = useState(0)
  const [selectedAccount, setSelectedAccount] =
    useState<TradeAccountOption | null>(null)
  const [selectedCopyGroupId, setSelectedCopyGroupId] = useState<string | null>(
    null
  )
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
  const [direction, setDirection] = useState<TradeDirection>("Long")
  const [directionManuallySet, setDirectionManuallySet] = useState(false)
  const [entryDate, setEntryDate] = useState(getESTDate())
  const [exitDate, setExitDate] = useState(getESTDate())
  const [entryTime, setEntryTime] = useState("")
  const [exitTime, setExitTime] = useState("")
  const [entryPrice, setEntryPrice] = useState("")
  const [exitPrice, setExitPrice] = useState("")
  const [description, setDescription] = useState("")
  const [isPublic, setIsPublic] = useState(false)
  const [communityPreviewOpen, setCommunityPreviewOpen] = useState(false)
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [image, setImage] = useState<File | null>(null)
  const imageCrop = useTradeImageCropUpload({
    onCropped: setImage,
    onValidationError: (message) =>
      showPopup(persistentError("Invalid Image", message)),
  })
  const fileInputRef = imageCrop.fileInputRef
  const [pendingReelFile, setPendingReelFile] = useState<File | null>(null)
  const pendingReelFileRef = useRef<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [csvPasteOpen, setCsvPasteOpen] = useState(false)
  const [csvPasteText, setCsvPasteText] = useState("")
  const [csvImportError, setCsvImportError] = useState<string | null>(null)
  /** Full list of CSV-derived trades for this Quick Input session (all batches). */
  const [csvQueuePatches, setCsvQueuePatches] = useState<QuickTradeCsvFormPatch[]>(
    []
  )
  const [csvQueueIndex, setCsvQueueIndex] = useState(0)
  const [planProfile, setPlanProfile] = useState<{
    is_pro?: boolean | null
    subscription_status?: string | null
    locked_account_type?: string | null
    username?: string | null
    avatar_url?: string | null
  } | null>(null)

  const resetForm = useCallback(() => {
    const today = getESTDate()
    setTicker("")
    setPnl("")
    setPoints("")
    setContracts("")
    setRr("")
    setDirection("Long")
    setDirectionManuallySet(false)
    setEntryDate(today)
    setExitDate(today)
    setEntryTime("")
    setExitTime("")
    setEntryPrice("")
    setExitPrice("")
    setDescription("")
    setIsPublic(false)
    setCommunityPreviewOpen(false)
    setImage(null)
    imageCrop.resetFileInput()
    setPendingReelFile(null)
    setPreviewUrl(null)
    setAdvancedOpen(false)
    setSelectedAccount(null)
    setSelectedCopyGroupId(null)
    setCsvPasteOpen(false)
    setCsvPasteText("")
    setCsvImportError(null)
    setCsvQueuePatches([])
    setCsvQueueIndex(0)
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
      setEntryEnabledAccountCount(0)
      setAccountLoading(false)
      return
    }

    const allRows = data ?? []
    setEntryEnabledAccountCount(countTradeEntryEnabledAccounts(allRows))

    const rows = filterAccountsForTradeEntry(allRows).map((acc) => ({
      name: String(acc.name ?? ""),
      size: String(acc.account_size ?? ""),
      id: String(acc.id),
      account_number: acc.account_number ?? null,
      mode: acc.mode ?? "live",
      category: acc.category ?? null,
      can_add_trades: acc.can_add_trades !== false,
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

  function clearEphemeralTradeFields() {
    setDescription("")
    setIsPublic(false)
    setCommunityPreviewOpen(false)
    setImage(null)
    imageCrop.resetFileInput()
    setPendingReelFile(null)
    setPreviewUrl(null)
    setAdvancedOpen(false)
    setDecimalError("")
  }

  function applyQuickCsvPatch(patch: QuickTradeCsvFormPatch) {
    setCsvImportError(null)
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
    setDescription(patch.description)
    const inferred = inferTradeDirectionFromPrices(
      parseTradePriceInput(patch.entryPrice),
      parseTradePriceInput(patch.exitPrice)
    )
    if (inferred) {
      setDirection(inferred)
      setDirectionManuallySet(false)
    } else if (patch.direction === "Long" || patch.direction === "Short") {
      setDirection(patch.direction)
      setDirectionManuallySet(true)
    } else {
      setDirection("Long")
      setDirectionManuallySet(false)
    }
    if (csvPatchHasPrices(patch)) {
      setAdvancedOpen(true)
    } else {
      setAdvancedOpen(false)
    }
  }

  function applyQueuedTradePatch(
    patch: QuickTradeCsvFormPatch,
    accountList: TradeAccountOption[]
  ) {
    clearEphemeralTradeFields()
    applyQuickCsvPatch(patch)
    const matched = resolveQuickTradeAccountFromCsvPatch(accountList, patch)
    if (matched) {
      setSelectedAccount(matched)
      setSelectedCopyGroupId(null)
    }
  }

  function beginCsvQueue(patches: QuickTradeCsvFormPatch[]) {
    if (patches.length === 0) return
    setCsvQueuePatches(patches)
    setCsvQueueIndex(0)
    setCsvPasteOpen(false)
    setCsvPasteText("")
    applyQueuedTradePatch(patches[0], accounts)
  }

  function advanceCsvQueue(
    nextIndex: number,
    patches: QuickTradeCsvFormPatch[]
  ) {
    const nextPatch = patches[nextIndex]
    if (!nextPatch) return
    setCsvQueueIndex(nextIndex)
    applyQueuedTradePatch(nextPatch, accounts)
  }

  function handleEntryPriceChange(value: string) {
    setEntryPrice(value)
    setDirection((prev) =>
      nextDirectionAfterPriceChange({
        current: prev,
        manualOverride: directionManuallySet,
        entryPrice: parseTradePriceInput(value),
        exitPrice: parseTradePriceInput(exitPrice),
      })
    )
  }

  function handleExitPriceChange(value: string) {
    setExitPrice(value)
    setDirection((prev) =>
      nextDirectionAfterPriceChange({
        current: prev,
        manualOverride: directionManuallySet,
        entryPrice: parseTradePriceInput(entryPrice),
        exitPrice: parseTradePriceInput(value),
      })
    )
  }

  function handleDirectionChange(value: string) {
    if (value !== "Long" && value !== "Short") return
    setDirection(value)
    setDirectionManuallySet(true)
  }

  useEffect(() => {
    if (!open) return
    resetForm()
    if (initialCsvPatch) {
      applyQuickCsvPatch(initialCsvPatch)
    }
  }, [open, initialCsvPatch, resetForm])

  useEffect(() => {
    if (!open || accounts.length === 0) return
    const patch = csvQueuePatches[csvQueueIndex] ?? initialCsvPatch
    if (!patch) return
    const matched = resolveQuickTradeAccountFromCsvPatch(accounts, patch)
    if (matched) {
      setSelectedAccount(matched)
      setSelectedCopyGroupId(null)
    }
  }, [open, initialCsvPatch, csvQueuePatches, csvQueueIndex, accounts])

  useEffect(() => {
    if (!open || !userId) return
    void loadAccounts(userId)
    void loadPlanProfile(userId)
  }, [open, userId, loadAccounts, loadPlanProfile])

  const isPro = isProActive(planProfile)
  const { copyGroups } = useCopyTradingGroups(userId, isPro && open)

  useEffect(() => {
    setSelectedCopyGroupId((prev) =>
      prev && copyGroups.some((group) => group.id === prev) ? prev : null
    )
  }, [copyGroups])

  const selectedCopyGroup = useMemo(
    () => copyGroups.find((group) => group.id === selectedCopyGroupId) ?? null,
    [copyGroups, selectedCopyGroupId]
  )

  const copyGroupListAccounts = useMemo(
    (): TradingAccountListItem[] =>
      accounts.map((account) => ({
        id: account.id,
        name: account.name,
        size: account.size,
        account_number: account.account_number ?? null,
        mode: String(account.mode ?? "live"),
        category: account.category ?? null,
        is_active: true,
        note: "",
        rules: null,
      })),
    [accounts]
  )

  useEffect(() => {
    if (!image) {
      setPreviewUrl(null)
      return
    }
    const url = URL.createObjectURL(image)
    setPreviewUrl(url)
    return () => URL.revokeObjectURL(url)
  }, [image])

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
      direction,
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
      attachedReel: pendingReelFile ? true : null,
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
    direction,
    selectedAccount,
    description,
    previewUrl,
    entryDate,
    entryTime,
    exitDate,
    exitTime,
    entryPrice,
    exitPrice,
    pendingReelFile,
  ])

  const communityPreviewUser = useMemo(
    () => (userId ? { id: userId } : null),
    [userId]
  )

  const showQuickTradeValidationFailure = useCallback(
    (failure: QuickTradeValidationFailure) => {
      const focusField = () =>
        focusQuickTradeField(failure.field, {
          openAdvanced: () => setAdvancedOpen(true),
        })

      if (failure.kind === "missing") {
        showPopup({
          ...feedbackPresets.missingRequiredInformation(failure.message),
          onDismiss: focusField,
        })
        return
      }

      showPopup({
        type: "error",
        title: failure.title ?? "Invalid Input",
        message: failure.message,
        persist: true,
        onDismiss: focusField,
      })
    },
    [showPopup]
  )

  function handleClose() {
    if (busy || communityPreviewOpen) return
    onClose()
  }

  function handlePrimaryAction() {
    if (isPublic) {
      if (!communityPreviewPost || !communityPreviewUser) return
      setCommunityPreviewOpen(true)
      return
    }
    void handleSave()
  }

  function handleAutoFillFromCsvPaste() {
    const result = parseQuickCsvImport(csvPasteText)
    if (!result.ok) {
      setCsvImportError(result.message)
      return
    }
    beginCsvQueue(result.patches)
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
    beginCsvQueue(result.patches)
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

      const sizeGate = assertRequiredAccountValue(newAccount.size)
      if (!sizeGate.ok) {
        showPopup(persistentError("Account Value Required", sizeGate.message))
        return
      }

      const { data, error: insertErr } = await supabase
        .from("accounts")
        .insert([
          {
            user_id: userId,
            name: newAccount.name,
            account_size: sizeGate.value,
            account_number: newAccount.id,
            category: newAccount.category,
            mode: newAccount.mode,
            is_active: true,
            can_add_trades: true,
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
          supabaseMutationFeedback(insertErr, "Save Failed")
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
      setEntryEnabledAccountCount((n) => n + 1)
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

    const validation = validateQuickTradeForm({
      hasAccount: Boolean(selectedAccount || selectedCopyGroupId),
      ticker,
      pnl,
      points,
      contracts,
      rr,
      entryDate,
      exitDate,
      entryTime,
      exitTime,
      decimalError,
    })
    if (!validation.ok) {
      showQuickTradeValidationFailure(validation)
      return
    }

    if (uploadingRef.current || busy) return

    const reelFile = pendingReelFileRef.current ?? pendingReelFile
    const queuePatchesSnapshot = csvQueuePatches
    const queueIndexSnapshot = csvQueueIndex
    const hasQueuedTrades = queuePatchesSnapshot.length > 1
    const hasMoreQueuedTrades =
      hasQueuedTrades && queueIndexSnapshot < queuePatchesSnapshot.length - 1

    uploadingRef.current = true
    setBusy(true)

    const parsedPnl = Number(String(pnl).replace(/,/g, "").replace(/\$/g, ""))
    const parsedPoints = Number(String(points).replace(/,/g, ""))
    const parsedContracts = Number.parseInt(
      String(contracts).replace(/,/g, ""),
      10
    )
    const entryVal = parseTradePriceInput(entryPrice)
    const exitVal = parseTradePriceInput(exitPrice)

    const uploadTitle = isPublic
      ? reelFile || image
        ? "Uploading Trade"
        : "Posting Trade"
      : reelFile || image
        ? "Uploading Trade"
        : "Saving Trade"

    try {
      await runUpload({
        title: uploadTitle,
        // Keep the modal open while more CSV trades remain in this session.
        onDismissCompose: hasMoreQueuedTrades ? undefined : onClose,
        execute: async (report) => {
          if (selectedCopyGroup && userId) {
            const groupAccounts = resolveCopyGroupAccounts(
              selectedCopyGroup,
              copyGroupListAccounts
            )
            if (groupAccounts.length === 0) {
              showPopup(
                persistentError(
                  "Copy Group Empty",
                  "This copy trading group has no linked accounts."
                )
              )
              throw new Error("Copy group empty")
            }

            const now = new Date()
            const tradeTemplate = {
              ticker: ticker.trim().toUpperCase(),
              direction,
              pnl: parsedPnl,
              rr: parseOptionalRr(rr),
              points: parsedPoints,
              contracts: parsedContracts,
              session: "NY",
              notes: description.trim() || null,
              public_description: description.trim() || null,
              image_url: null,
              strategy: null,
              user_id: userId,
              created_at: now.toISOString(),
              date: now.toISOString(),
              trade_date: entryDate,
              entry_price:
                entryVal != null && Number.isFinite(entryVal) ? entryVal : null,
              exit_price:
                exitVal != null && Number.isFinite(exitVal) ? exitVal : null,
              entry_time: buildDateTime(entryDate, entryTime || undefined),
              exit_time: buildDateTime(exitDate, exitTime || undefined),
              psychology_notes: null,
              trade_type: null,
              confidence: null,
              emotion: null,
              followed_plan: false,
              mistake_type: null,
              market_condition: null,
              news_event: false,
              timeframe: null,
              is_public: isPublic,
            }

            const copyResult = await insertCopyTradedTrades({
              client: supabase,
              userId,
              isPro,
              groupId: selectedCopyGroup.id,
              accounts: groupAccounts,
              tradeTemplate,
              isPublic,
              postCaption: description.trim() || null,
            })

            if (!copyResult.ok) {
              showPopup(persistentError("Save Failed", copyResult.message))
              throw new Error(copyResult.message)
            }

            notifyGettingStartedChecklistMaybeCompleted()
            if (!hasMoreQueuedTrades) {
              showPopup(
                isPublic
                  ? feedbackPresets.postPublished()
                  : feedbackPresets.tradeSaveSuccess()
              )
            }
            onSaved?.()
            if (hasMoreQueuedTrades) {
              advanceCsvQueue(queueIndexSnapshot + 1, queuePatchesSnapshot)
            }
            return
          }

          const result = await saveManualTrade(
            supabase,
            userId,
            toManualTradeAccount(selectedAccount),
            {
              ticker: ticker.trim().toUpperCase(),
              direction,
              pnl: parsedPnl,
              points: parsedPoints,
              contracts: parsedContracts,
              entryDate,
              exitDate,
              entryTime: entryTime || undefined,
              exitTime: exitTime || undefined,
              entryPrice:
                entryVal != null && Number.isFinite(entryVal) ? entryVal : null,
              exitPrice:
                exitVal != null && Number.isFinite(exitVal) ? exitVal : null,
              rr: parseOptionalRr(rr),
              publicDescription: description,
              isPublic,
              imageFile: image,
            },
            { onProgress: report }
          )

          if (!result.ok) {
            if (result.code === "account_limit") {
              showPopup(feedbackPresets.accountLimit())
              throw new Error("Account limit reached.")
            }
            if (result.code === "account_locked") {
              showPopup(feedbackPresets.accountLocked())
              throw new Error("Account is locked.")
            }
            const failureTitle =
              result.code === "post" ? "Post Failed" : "Save Failed"
            showPopup(
              result.error != null
                ? supabaseMutationFeedback(result.error, failureTitle)
                : persistentError(failureTitle, result.message)
            )
            throw new Error(result.message)
          }

          if (reelFile && result.trade?.id) {
            report({ percent: 68, stage: "Uploading replay…" })
            const reelResult = await publishTradeReel(supabase, {
              tradeId: String(result.trade.id),
              userId,
              file: reelFile,
              onProgress: (update) => {
                report({
                  percent: 68 + (update.percent / 100) * 28,
                  stage: update.stage,
                })
              },
            })
            if ("error" in reelResult) {
              throw new Error(
                `Trade saved, but replay could not be uploaded: ${reelResult.error}`
              )
            }
          }

          notifyGettingStartedChecklistMaybeCompleted()
          if (!hasMoreQueuedTrades) {
            showPopup(
              result.posted
                ? feedbackPresets.postPublished()
                : feedbackPresets.tradeSaveSuccess()
            )
          }
          onSaved?.()
          if (hasMoreQueuedTrades) {
            advanceCsvQueue(queueIndexSnapshot + 1, queuePatchesSnapshot)
          }
        },
      })
    } catch {
      // Error UI handled by upload progress overlay (retry/cancel).
    } finally {
      uploadingRef.current = false
      setBusy(false)
    }
  }

  if (!open) return null

  const canCreateMoreAccounts =
    isPro || entryEnabledAccountCount < FREE_PLAN_ACCOUNT_LIMIT

  const csvQueueTotal = csvQueuePatches.length
  const isMultiTradeSession = csvQueueTotal > 1
  const hasMoreQueuedTrades =
    isMultiTradeSession && csvQueueIndex < csvQueueTotal - 1
  const currentTradeNumber = csvQueueIndex + 1
  const progressPercent =
    csvQueueTotal > 0 ? (currentTradeNumber / csvQueueTotal) * 100 : 0
  const saveTradeLabel = hasMoreQueuedTrades ? "Save & Next" : "Save Trade"
  const postTradeLabel = hasMoreQueuedTrades ? "Post & Next" : "Post Trade"

  function selectTradeImage(file: File | undefined) {
    imageCrop.handleFileSelected(file)
  }

  function handleCropCancel() {
    imageCrop.handleCropCancel()
  }

  function handleCropSave(cropped: File) {
    imageCrop.handleCropSave(cropped)
  }

  return (
    <>
      <ScrollableModalShell
        open={open}
        onClose={handleClose}
        ariaLabel="Quick Trade"
        belowNavbar
        closeDisabled={busy || communityPreviewOpen}
        overlayClassName="z-[150] bg-black/75 backdrop-blur-md"
        backdropClassName="bg-transparent"
        panelClassName="max-w-lg rounded-2xl border-white/10 bg-gradient-to-br from-[#0f172a] via-[#0b1532] to-[#0a2230] shadow-2xl shadow-blue-900/20 sm:max-w-xl md:max-w-2xl"
        headerClassName="border-white/10 px-4 pb-4 pt-4 sm:px-6"
        bodyClassName="px-4 sm:px-6"
        footerClassName="border-white/10 px-4 py-4 sm:px-6"
        header={
          <>
            <h2 className="text-xl font-semibold tracking-tight text-white">
              Quick Trade
            </h2>
            {isMultiTradeSession ? (
              <div className="mt-3">
                <p className="text-sm font-medium text-blue-300">
                  Trade {currentTradeNumber} of {csvQueueTotal}
                </p>
                <div
                  className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-white/10"
                  role="progressbar"
                  aria-valuenow={currentTradeNumber}
                  aria-valuemin={1}
                  aria-valuemax={csvQueueTotal}
                  aria-label={`Trade ${currentTradeNumber} of ${csvQueueTotal}`}
                >
                  <div
                    className="h-full rounded-full bg-blue-500 transition-[width] duration-300 ease-out"
                    style={{ width: `${progressPercent}%` }}
                  />
                </div>
              </div>
            ) : (
              <p className={cn("mt-1 text-sm", READABLE_SECONDARY_CLASS)}>
                Log the essentials in under 30 seconds.
              </p>
            )}
          </>
        }
        footer={
          <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
            <button
              type="button"
              disabled={busy}
              onClick={handleClose}
              className="h-11 rounded-lg border border-white/20 bg-white/5 px-4 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={
                accountLoading ||
                uploadingRef.current ||
                (isPublic && !communityPreviewPost)
              }
              onClick={handlePrimaryAction}
              className={QUICK_TRADE_PRIMARY_BUTTON_CLASS}
            >
              {isPublic ? "Preview Public Trade Post" : saveTradeLabel}
            </button>
          </div>
        }
      >
        <div className="space-y-5">
            <div>
              <FieldLabel>Trading Account</FieldLabel>
              <TradeAccountPicker
                className="mt-2"
                triggerId="quick-trade-account-trigger"
                accounts={accounts}
                isPro={isPro}
                copyGroups={copyGroups}
                selectedAccount={selectedAccount}
                selectedCopyGroupId={selectedCopyGroupId}
                onSelect={setSelectedAccount}
                onSelectCopyGroup={setSelectedCopyGroupId}
                onOpenCreate={() => setShowCreateAccountModal(true)}
                disableCreate={!canCreateMoreAccounts}
                showExternalCreateButton={false}
              />
            </div>

            <div className="rounded-xl border border-white/10 bg-white/[0.03] px-4 py-4">
              <p className="text-sm font-medium text-white">Quick CSV Import</p>
              <p className="mt-1 text-sm leading-relaxed text-gray-400">
                Autofill one or more trades from your broker CSV. Review and save
                them one at a time.
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
                    className={cn(
                      "w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 py-3 font-mono text-sm text-white outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20",
                      READABLE_PLACEHOLDER_CLASS
                    )}
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

            {/* Row 2: Points · Contracts · RR · Direction */}
            <div className={FIELD_METRICS_ROW_CLASS}>
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
              <div>
                <FieldLabel htmlFor="quick-trade-direction">Direction</FieldLabel>
                <CustomSelect
                  id="quick-trade-direction"
                  value={direction}
                  onChange={handleDirectionChange}
                  className="mt-2"
                  triggerClassName={SELECT_TRIGGER_COMPACT_CLASS}
                  options={[
                    { label: "Long", value: "Long" },
                    { label: "Short", value: "Short" },
                  ]}
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

            {/* Advanced */}
            <div className="rounded-xl border border-white/10 bg-white/[0.03]">
              <button
                type="button"
                onClick={() => setAdvancedOpen((prev) => !prev)}
                className="flex w-full items-center justify-between px-4 py-3.5 text-left text-sm font-medium text-gray-200"
                aria-expanded={advancedOpen}
              >
                Advanced Details
                <span className="text-gray-400" aria-hidden>
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
                      onChange={handleEntryPriceChange}
                      onDecimalError={setDecimalError}
                      inputClassName={QUICK_CURRENCY_INPUT_CLASS}
                    />
                  </div>
                  <div>
                    <FieldLabel htmlFor="quick-exit-price">Exit Price</FieldLabel>
                    <TradeFormCurrencyInput
                      id="quick-exit-price"
                      value={exitPrice}
                      onChange={handleExitPriceChange}
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
                onChange={(e) => selectTradeImage(e.target.files?.[0])}
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
                  className="mt-3 w-full rounded-lg border border-white/10"
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
                className={cn("mt-2", INPUT_CLASS, "h-auto py-3")}
              />
            </div>

            {/* Share to Community */}
            <TradePublicShareToggle
              isPublic={isPublic}
              onToggle={() => {
                setIsPublic((prev) => {
                  const next = !prev
                  if (!next) setCommunityPreviewOpen(false)
                  return next
                })
              }}
            />
        </div>
      </ScrollableModalShell>
      <CommunitySharePreviewModal
        open={communityPreviewOpen}
        onClose={() => setCommunityPreviewOpen(false)}
        onPostTrade={() => void handleSave()}
        submitting={busy}
        postTradeDisabled={accountLoading || uploadingRef.current}
        title="Preview Public Trade Post"
        subtitle="This is how your trade will appear in the feed."
        postTradeLabel={postTradeLabel}
        submittingLabel="Posting…"
        post={communityPreviewPost}
        user={communityPreviewUser}
      />
      <CreateAccountModal
        open={showCreateAccountModal}
        onClose={() => setShowCreateAccountModal(false)}
        onSave={handleCreateAccountSave}
        overlayClassName="z-[160]"
      />
      <FeedbackModal {...feedbackModalProps} />
      <ImageCropModal
        open={imageCrop.cropSourceFile != null}
        file={imageCrop.cropSourceFile}
        preset={CONTENT_IMAGE_CROP_PRESET}
        onCancel={handleCropCancel}
        onSave={handleCropSave}
      />
    </>
  )
}
