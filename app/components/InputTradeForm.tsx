"use client"

import { useState, useRef, useEffect, useCallback, useMemo } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabaseClient"
import { uploadContentImageToStorage, CONTENT_IMAGE_CROP_PRESET } from "@/lib/contentImagePipeline"
import { consumeAppRateLimit } from "@/lib/consumeAppRateLimit"
import { devLog } from "@/lib/devLog"
import {
  assertCanCreateTradingAccount,
  FREE_PLAN_ACCOUNT_LIMIT,
} from "@/lib/tradingAccounts"
import {
  ACCOUNT_READ_ONLY_BADGE,
  countTradeEntryEnabledAccounts,
  filterAccountsForTradeEntry,
} from "@/lib/freePlanAccountSlots"
import {
  assertCsvImportAllowedForFreePlan,
  FREE_PLAN_CSV_IMPORT_COOLDOWN_DAYS,
  markProfileCsvImportUsed,
} from "@/lib/csvImportGate"
import { ensureManualUserAccountRegistered } from "@/lib/ensureManualUserAccount"
import { ACCOUNTS_SELECT } from "@/lib/appDataCache"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { isProActive } from "@/lib/subscription"
import { insertCsvTradesWithAccount } from "@/lib/insertCsvTradesWithAccount"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"
import { assertRequiredAccountValue } from "@/lib/createAccountForm"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { supabaseMutationFeedback } from "@/lib/supabaseMutationFeedback"
import { getSessionFromDate } from "@/lib/getSession"
import {
  buildDateTime,
  dateTimeFieldsFromTrade,
  getESTDate,
  getTradeFormDuration,
  isExitBeforeEntry,
  toTimeInputValue,
} from "@/lib/inputTradeDateTime"
import { tradeFormHasFutureDate, csvTradesHaveFutureDate, isDateAfterToday } from "@/lib/tradeDateValidation"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import { profilePath } from "@/lib/profileRoutes"
import { hasStoredTradePoints } from "@/lib/resolveTradePoints"
import { parseOptionalRr } from "@/lib/tradeRr"
import {
  resolveCopyGroupAccounts,
} from "@/lib/copyTradingGroups"
import { insertCopyTradedTrades } from "@/lib/tradeCopyTrading"
import { useCopyTradingGroups } from "@/lib/useCopyTradingGroups"
import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import TradeAccountPicker from "@/app/components/TradeAccountPicker"
import CustomSelect from "@/app/components/CustomSelect"
import { SELECT_TRIGGER_COMPACT_CLASS } from "@/lib/accountDropdownStyles"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import NativeTimeInput from "@/app/components/ui/NativeTimeInput"
import CsvImportUnsupportedBanner from "@/app/components/CsvImportUnsupportedBanner"
import CsvImportDiagnosticsPanel from "@/app/components/CsvImportDiagnosticsPanel"
import type { CsvImportDiagnostics } from "@/lib/csvImportDiagnostics"
import { buildCommunitySharePreviewPost } from "@/lib/buildCommunitySharePreviewPost"
import CommunitySharePreviewModal from "@/app/components/CommunitySharePreviewModal"
import TradePublicShareToggle from "@/app/components/TradePublicShareToggle"
import TradeReelAttachment from "@/app/components/TradeReelAttachment"
import ImageCropModal from "@/app/components/ImageCropModal"
import { useTradeImageCropUpload } from "@/lib/useTradeImageCropUpload"
import {
  fetchImageUrlAsFile,
  type TradeScreenshotDisplayMode,
} from "@/lib/tradeScreenshotDisplayMode"
import {
  DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE,
  resolveTradeScreenshotDisplayMode,
  tradeScreenshotObjectFitClass,
} from "@/lib/tradeScreenshotDisplay"
import TradeFormCurrencyInput from "@/app/components/trade/TradeFormCurrencyInput"
import {
  getTradeFormCurrencyInputDisplayValue,
  handleTradeNumericInput,
} from "@/lib/formatMoney"
import {
  TRADE_FIELD_CHECKBOX_LABEL_CLASS,
  TRADE_FIELD_CONTROL_CLASS,
  TRADE_FIELD_CONTROL_LG_CLASS,
  TRADE_FIELD_CURRENCY_CONTROL_CLASS,
  TRADE_FIELD_HELPER_CLASS,
  TRADE_FIELD_LABEL_CLASS,
  TRADE_FIELD_PUBLIC_NOTES_CLASS,
  TRADE_FIELD_SECTION_TITLE_CLASS,
  TRADE_FIELD_TEXTAREA_CLASS,
  TRADE_FULL_INPUT_MEDIA_UPLOAD_CLASS,
} from "@/lib/tradeFormUi"
import {
  deleteReel,
  fetchTradeReel,
  publishTradeReel,
  replaceTradeReelVideo,
  syncTradeLinkedReelVisibility,
  type ReelRow,
} from "@/lib/reels"
import type { UploadProgressReporter } from "@/lib/uploadProgress/types"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import { postImageSrc } from "@/app/components/feed/feedPostHelpers"
import { ConfirmModal, FeedbackModal, Modal, useDeleteReelConfirmation, useFeedbackPopup } from "@/app/components/ui"
import ScrollableModalShell from "@/app/components/ui/ScrollableModalShell"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import {
  formatAccountNameWithSizeDisplay,
  safeAccountNumberLabel,
} from "@/lib/tradeAccountDisplay"
import {
  invalidateTradesCache,
  prependTradeInCache,
  upsertAccountInCache,
  upsertTradeInCache,
} from "@/lib/appDataCache"

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

const TRADE_TIMEFRAME_PRESETS = [
  "15s",
  "30s",
  "1m",
  "5m",
  "15m",
  "30m",
  "1hr",
  "4hr",
] as const

const TRADE_TIMEFRAME_OPTIONS = [...TRADE_TIMEFRAME_PRESETS, "Custom"] as const

function isTradeTimeframePreset(value: string): boolean {
  return (TRADE_TIMEFRAME_PRESETS as readonly string[]).includes(value)
}

function modeLabelFromDb(raw: string | null | undefined): string {
  const s = String(raw ?? "").toLowerCase().trim()
  if (s === "eval") return "Eval"
  if (s === "funded") return "Funded"
  if (s === "live") return "Live"
  if (s === "sim") return "Sim"
  if (s === "backtest") return "Backtest"
  return "Live"
}

export type InputTradeFormProps = {
  existingTrade?: any | null
  onSave?: () => void
  onClose?: () => void
  forceMarkReviewedOnSave?: boolean
  onUploadCsvClick?: () => void
  onQuickInputClick?: () => void
  onReviewCsvClick?: () => void
  reviewCount?: number
  csvLoading?: boolean
  /** Parsed CSV rows on parent (e.g. home); when non-empty, show Import next to Upload CSV */
  parsedTrades?: any[]
  /** Called after successful CSV import so parent can clear `parsedTrades` */
  onParsedTradesClear?: () => void
  /** Parent detected zero parseable rows from an uploaded CSV */
  csvUnrecognized?: boolean
  csvBrokerHint?: string | null
  csvDiagnostics?: CsvImportDiagnostics | null
  /** Original CSV file for diagnostics submit CTA */
  csvSupportFile?: File | null
  /** Data row count for diagnostics submit notes */
  csvDataRowCount?: number
  /** Source label for admin CSV import completed email */
  csvImportSource?: string
}

export default function InputTradeForm({
  existingTrade,
  onSave,
  onClose,
  forceMarkReviewedOnSave = false,
  onUploadCsvClick,
  onQuickInputClick,
  onReviewCsvClick,
  reviewCount = 0,
  csvLoading = false,
  parsedTrades = [],
  csvUnrecognized = false,
  csvBrokerHint = null,
  csvDiagnostics = null,
  csvSupportFile = null,
  csvDataRowCount = 0,
  csvImportSource = "input_trade_page",
  onParsedTradesClear,
}: InputTradeFormProps) {
  const router = useRouter()
  const { user, profile: contextProfile } = useUserProfile()
  const userId = user?.id ?? null
  const isEditMode = Boolean(existingTrade?.id)
  const showAsModal = isEditMode && Boolean(onClose)

  const [accounts, setAccounts] = useState<any[]>([])
  const [selectedAccount, setSelectedAccount] = useState<any | null>(null)
  const [selectedCopyGroupId, setSelectedCopyGroupId] = useState<string | null>(
    null
  )
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [showAccountWarning, setShowAccountWarning] = useState(false)

  const [submitting, setSubmitting] = useState(false)
  const submittingRef = useRef(false)
  const [creatingAccount, setCreatingAccount] = useState(false)
  const creatingAccountRef = useRef(false)
  const [csvImporting, setCsvImporting] = useState(false)
  const csvImportingRef = useRef(false)
  const [togglingAccountId, setTogglingAccountId] = useState<string | null>(null)
  const [savingNoteId, setSavingNoteId] = useState<string | null>(null)
  const [confidence, setConfidence] = useState("")
  const [psychologyNotes, setPsychologyNotes] = useState("")
  const [tradeType, setTradeType] = useState("")
  const [showSettings, setShowSettings] = useState(false)
  const [showAllAccounts, setShowAllAccounts] = useState(false)
  const [openMenuId, setOpenMenuId] = useState<string | null>(null)
  const [editingAccount, setEditingAccount] = useState<any | null>(null)
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const uploadReportRef = useRef<UploadProgressReporter | null>(null)
  const { runUpload } = useUploadProgress()

  function releaseSubmit() {
    submittingRef.current = false
    setSubmitting(false)
  }

  const [emotion, setEmotion] = useState("")
  const [followedPlan, setFollowedPlan] = useState(false)
  const [mistakeType, setMistakeType] = useState("")
  const [market, setMarket] = useState("")
  const [newsEvent, setNewsEvent] = useState(false)
  const [timeframe, setTimeframe] = useState("")
  const [customTimeframe, setCustomTimeframe] = useState("")

  function handleNumberInput(value: string) {
    if (/^-?\d*\.?\d*$/.test(value)) return value
    return null
  }

  function formatWithCommas(value: string) {
    if (!value) return ""

    const num = Number(value.replace(/,/g, ""))
    if (isNaN(num)) return ""

    return num.toLocaleString("en-US")
  }

  const [entryDate, setEntryDate] = useState(getESTDate())
  const [exitDate, setExitDate] = useState(getESTDate())
  const [ticker, setTicker] = useState("")
  const [direction, setDirection] = useState("Long")
  const [pnl, setPnl] = useState("")
  const [rr, setRR] = useState("")
  const [points, setPoints] = useState("")
  const [session, setSession] = useState("NY")
  const [sessionManuallySet, setSessionManuallySet] = useState(false)
  const [decimalError, setDecimalError] = useState("")
  const [confluences, setConfluences] = useState("")
  const [publicDescription, setPublicDescription] = useState("")
  const [postToFeed, setPostToFeed] = useState(false)
  const [isPublic, setIsPublic] = useState(false)
  const [image, setImage] = useState<File | null>(null)
  const [removeScreenshot, setRemoveScreenshot] = useState(false)
  const [screenshotDisplayMode, setScreenshotDisplayMode] =
    useState<TradeScreenshotDisplayMode>(DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE)
  const [screenshotModeBusy, setScreenshotModeBusy] = useState(false)
  const screenshotSourceRef = useRef<File | null>(null)
  const imageCrop = useTradeImageCropUpload({
    onCropped: (cropped) => {
      setRemoveScreenshot(false)
      setImage(cropped)
    },
    onValidationError: (message) =>
      showPopup(persistentError("Invalid Image", message)),
  })
  const [pendingReelFile, setPendingReelFile] = useState<File | null>(null)
  const pendingReelFileRef = useRef<File | null>(null)
  const [attachedReel, setAttachedReel] = useState<ReelRow | null>(null)
  const [reelDeleteBusy, setReelDeleteBusy] = useState(false)

  const [strategy, setStrategy] = useState("")

  const [entryPrice, setEntryPrice] = useState("")
  const [exitPrice, setExitPrice] = useState("")
  const [contracts, setContracts] = useState("")
  const [entryTime, setEntryTime] = useState("")
  const [exitTime, setExitTime] = useState("")
  const fileInputRef = imageCrop.fileInputRef

  const [planProfile, setPlanProfile] = useState<{
    is_pro?: boolean | null
    subscription_status?: string | null
    locked_account_type?: string | null
    locked_account_size?: string | null
    locked_account_name?: string | null
    locked_account_number?: string | null
    username?: string | null
    avatar_url?: string | null
  } | null>(null)
  const [accountFieldsLocked, setAccountFieldsLocked] = useState(false)
  const [csvImportBlocked, setCsvImportBlocked] = useState(false)
  const [csvDaysUntilNextImport, setCsvDaysUntilNextImport] = useState<
    number | null
  >(null)
  const [communityPreviewOpen, setCommunityPreviewOpen] = useState(false)
  const [screenshotPreviewUrl, setScreenshotPreviewUrl] = useState<string | null>(
    null
  )

  const applyPlanAndAccountLock = useCallback(async (uid: string | null) => {
    if (!uid) {
      setPlanProfile(null)
      setAccountFieldsLocked(false)
      setCsvImportBlocked(false)
      setCsvDaysUntilNextImport(null)
      return
    }

    const fromContext =
      contextProfile?.id === uid
        ? {
            is_pro: contextProfile.is_pro,
            subscription_status: contextProfile.subscription_status,
            username: contextProfile.username,
            avatar_url: contextProfile.avatar_url,
          }
        : null

    const { data: lockedRow } = await supabase
      .from("profiles")
      .select(
        "is_pro, subscription_status, trial_end, locked_account_type, locked_account_size, locked_account_name, locked_account_number, username, avatar_url, last_csv_import_at"
      )
      .eq("id", uid)
      .maybeSingle()

    const prof = {
      ...fromContext,
      ...(lockedRow ?? {}),
    }
    setPlanProfile(Object.keys(prof).length ? prof : null)

    if (isProActive(prof)) {
      setAccountFieldsLocked(false)
      setCsvImportBlocked(false)
      setCsvDaysUntilNextImport(null)
      return
    }

    const { data: existingAccounts, error: countErr } = await supabase
      .from("accounts")
      .select("id, can_add_trades")
      .eq("user_id", uid)

    if (countErr) {
      console.error(countErr)
      setAccountFieldsLocked(false)
    } else {
      setAccountFieldsLocked(
        countTradeEntryEnabledAccounts(existingAccounts ?? []) >=
          FREE_PLAN_ACCOUNT_LIMIT
      )
    }

    const csvGate = await assertCsvImportAllowedForFreePlan(supabase, uid)
    if (!csvGate.ok) {
      setCsvImportBlocked(true)
      setCsvDaysUntilNextImport(csvGate.daysUntilNextImport)
    } else {
      setCsvImportBlocked(false)
      setCsvDaysUntilNextImport(null)
    }
  }, [contextProfile])

  const fetchAccountsForUser = useCallback(async (userId: string) => {
    const { data, error } = await supabase
      .from("accounts")
      .select(ACCOUNTS_SELECT)
      .eq("user_id", userId)

    if (error) {
      console.error(error)
      return
    }

    const formatted = (data || []).map((acc) => ({
      name: acc.name,
      size: acc.account_size,
      id: acc.id,
      account_number: acc.account_number ?? null,
      mode: acc.mode,
      category: acc.category,
      is_active: acc.is_active !== false,
      can_add_trades: acc.can_add_trades !== false,
      note: acc.note ?? "",
    }))

    setAccounts(formatted)
  }, [])

  const refreshPlanAndAccountLock = useCallback(async () => {
    await applyPlanAndAccountLock(userId)
  }, [applyPlanAndAccountLock, userId])

  useEffect(() => {
    void applyPlanAndAccountLock(userId)
    if (userId) {
      void fetchAccountsForUser(userId)
    }
  }, [userId, applyPlanAndAccountLock, fetchAccountsForUser])

  useEffect(() => {
    if (!userId) return
    void applyPlanAndAccountLock(userId)
  }, [existingTrade?.id, userId, applyPlanAndAccountLock])

  useEffect(() => {
    if (!image) {
      setScreenshotPreviewUrl(null)
      return
    }
    const url = URL.createObjectURL(image)
    setScreenshotPreviewUrl(url)
    return () => URL.revokeObjectURL(url)
  }, [image])

  useEffect(() => {
    if (!isPublic) setCommunityPreviewOpen(false)
  }, [isPublic])

  const updateNote = useCallback(async (accountId: string, note: string) => {
    const { error } = await supabase
      .from("accounts")
      .update({ note: note || null })
      .eq("id", accountId)

    if (error) {
      console.error(error)
      showPopup(
        supabaseMutationFeedback(error, "Save Failed")
      )
      return false
    }
    return true
  }, [])

  useEffect(() => {
    if (!showSettings || !userId) return
    void fetchAccountsForUser(userId)
  }, [showSettings, userId, fetchAccountsForUser])

  useEffect(() => {
    if (showSettings) return
    setShowAllAccounts(false)
    setOpenMenuId(null)
    setEditingAccount(null)
  }, [showSettings])

  useEffect(() => {
    if (!openMenuId) return
    function handlePointerDown(e: MouseEvent) {
      const t = e.target as HTMLElement
      if (t.closest("[data-account-settings-menu]")) return
      setOpenMenuId(null)
    }
    document.addEventListener("mousedown", handlePointerDown)
    return () => document.removeEventListener("mousedown", handlePointerDown)
  }, [openMenuId])

  const activeAccounts = useMemo(
    () => filterAccountsForTradeEntry(accounts),
    [accounts]
  )

  const sortedAccountsForSettings = useMemo(
    () =>
      [...accounts].sort((a, b) => {
        const aActive = a.is_active !== false
        const bActive = b.is_active !== false
        if (aActive === bActive) return 0
        return aActive ? -1 : 1
      }),
    [accounts]
  )

  useEffect(() => {
    if (!selectedAccount?.id) return
    // Accounts still loading — don't clear the hydrated edit selection.
    if (accounts.length === 0) return

    const selectedId = String(selectedAccount.id)
    const stillSelectable = activeAccounts.some(
      (a) => String(a.id) === selectedId
    )
    if (stillSelectable) return

    // Keep the trade's own account selectable while editing (incl. read-only / inactive).
    const inAllAccounts = accounts.some((a) => String(a.id) === selectedId)
    const isCurrentEditAccount =
      isEditMode &&
      existingTrade?.account_id != null &&
      String(existingTrade.account_id) === selectedId

    if (!inAllAccounts && !isCurrentEditAccount) {
      setSelectedAccount(null)
    }
  }, [
    selectedAccount,
    activeAccounts,
    accounts,
    isEditMode,
    existingTrade?.account_id,
  ])

  const pickerAccounts = useMemo(() => {
    const list = [...activeAccounts]
    if (!selectedAccount?.id) return list
    const selectedId = String(selectedAccount.id)
    if (list.some((a) => String(a.id) === selectedId)) return list
    const fromAll = accounts.find((a) => String(a.id) === selectedId)
    list.push(fromAll ?? selectedAccount)
    return list
  }, [activeAccounts, accounts, selectedAccount])

  const effectiveModeLower = String(
    selectedAccount?.mode ??
      (existingTrade?.mode ?? existingTrade?.account_type ?? "")
  ).toLowerCase()

  const accountInputsDisabled =
    accountFieldsLocked &&
    effectiveModeLower !== "backtest" &&
    !isProActive(planProfile)
  const isPro = isProActive(planProfile)
  const { copyGroups } = useCopyTradingGroups(
    userId,
    isPro && !isEditMode
  )
  const isLocked = !isPro && Boolean(planProfile?.locked_account_type)
  const lockedMode = modeLabelFromDb(planProfile?.locked_account_type)

  useEffect(() => {
    if (isEditMode) {
      setSelectedCopyGroupId(null)
      return
    }
    setSelectedCopyGroupId((prev) =>
      prev && copyGroups.some((group) => group.id === prev) ? prev : null
    )
  }, [copyGroups, isEditMode])

  const displayedMode = isLocked
    ? lockedMode
    : modeLabelFromDb(
        String(
          selectedAccount?.mode ??
            (existingTrade?.mode ?? existingTrade?.account_type ?? "")
        )
      )
  const accountControlsDisabled = accountInputsDisabled || isLocked

  useEffect(() => {
    if (!existingTrade?.id) return

    const t = existingTrade
    const dtFields = dateTimeFieldsFromTrade(t)
    setEntryDate(dtFields.entryDate)
    setExitDate(dtFields.exitDate)
    setTicker(t.ticker ?? "")
    setDirection(t.direction || "Long")
    setPnl(
      t.pnl != null && t.pnl !== "" ? String(t.pnl).replace(/,/g, "") : ""
    )
    setRR(t.rr != null && t.rr !== "" ? String(t.rr) : "")
    setPoints(t.points != null && t.points !== "" ? String(t.points) : "")
    setSession(t.session || "NY")
    // Preserve the saved session; do not let auto-detect overwrite while editing.
    setSessionManuallySet(true)
    setConfluences(t.top_confluences ?? t.notes ?? "")
    setPublicDescription(t.public_description ?? "")
    setPostToFeed(false)
    setIsPublic(Boolean(t.is_public))
    setImage(null)
    setRemoveScreenshot(false)
    setScreenshotDisplayMode(
      resolveTradeScreenshotDisplayMode(t.image_display_mode)
    )
    screenshotSourceRef.current = null
    setStrategy(t.strategy ?? "")
    const acctCat = (t as { account_category?: string | null }).account_category
    const tradeAcctNum = (t as { account_number?: string | null }).account_number
    setSelectedAccount({
      name: String(t.account_name ?? "").trim(),
      size:
        t.account_size != null && t.account_size !== ""
          ? String(t.account_size)
          : "",
      id: t.account_id != null && t.account_id !== "" ? String(t.account_id) : "",
      account_number:
        tradeAcctNum != null && String(tradeAcctNum).trim() !== ""
          ? String(tradeAcctNum).trim()
          : null,
      mode: String(t.mode ?? t.account_type ?? "live"),
      category:
        acctCat != null && String(acctCat).trim() !== ""
          ? String(acctCat).trim()
          : undefined,
    })
    setTradeType(t.trade_type ?? "")
    setConfidence(
      t.confidence != null && t.confidence !== "" ? String(t.confidence) : ""
    )
    setEmotion(t.emotion ?? "")
    setFollowedPlan(Boolean(t.followed_plan))
    setMistakeType(t.mistake_type ?? "")
    setMarket(t.market_condition ?? "")
    setNewsEvent(Boolean(t.news_event))
    const savedTimeframe = String(t.timeframe ?? "").trim()
    if (!savedTimeframe) {
      setTimeframe("")
      setCustomTimeframe("")
    } else if (isTradeTimeframePreset(savedTimeframe)) {
      setTimeframe(savedTimeframe)
      setCustomTimeframe("")
    } else {
      setTimeframe("Custom")
      setCustomTimeframe(savedTimeframe === "Custom" ? "" : savedTimeframe)
    }
    setPsychologyNotes(t.psychology_notes ?? "")
    setEntryPrice(
      t.entry_price != null && t.entry_price !== ""
        ? String(t.entry_price)
        : ""
    )
    setExitPrice(
      t.exit_price != null && t.exit_price !== "" ? String(t.exit_price) : ""
    )
    setContracts(
      t.contracts != null && t.contracts !== "" ? String(t.contracts) : ""
    )
    setEntryTime(dtFields.entryTime)
    setExitTime(dtFields.exitTime)
    setPendingReelFile(null)
    // Re-hydrate only when switching to a different trade. Parent list refreshes
    // often create a new `existingTrade` object for the same id and must not wipe edits.
  }, [existingTrade?.id])

  useEffect(() => {
    if (!existingTrade?.id) {
      setAttachedReel(null)
      return
    }

    let cancelled = false
    void fetchTradeReel(supabase, String(existingTrade.id)).then((reel) => {
      if (!cancelled) setAttachedReel(reel)
    })

    return () => {
      cancelled = true
    }
  }, [existingTrade?.id])

  useEffect(() => {
    pendingReelFileRef.current = pendingReelFile
  }, [pendingReelFile])

  function resetCreateForm() {
    setTicker("")
    setDirection("Long")
    setPnl("")
    setRR("")
    setPoints("")
    setSession("NY")
    setSessionManuallySet(false)
    setConfluences("")
    setPublicDescription("")
    setImage(null)
    setRemoveScreenshot(false)
    setScreenshotDisplayMode(DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE)
    screenshotSourceRef.current = null
    setPendingReelFile(null)
    setAttachedReel(null)
    setEntryPrice("")
    setExitPrice("")
    setContracts("")
    setEntryTime("")
    setExitTime("")
    setSelectedAccount(null)
    setSelectedCopyGroupId(null)
    setConfidence("")
    setEmotion("")
    setFollowedPlan(false)
    setMistakeType("")
    setMarket("")
    setNewsEvent(false)
    setTimeframe("")
    setCustomTimeframe("")
    setPsychologyNotes("")
    setTradeType("")
    const today = getESTDate()
    setEntryDate(today)
    setExitDate(today)
    setPostToFeed(false)
    setStrategy("")
  }

  const performDeleteAttachedReel = useCallback(
    async (post: ReelRow) => {
      if (!userId) return

      setReelDeleteBusy(true)
      const result = await deleteReel(supabase, {
        reelId: post.id,
        userId,
      })
      setReelDeleteBusy(false)

      if ("error" in result) {
        showPopup(
          persistentError("Delete Failed", handleSupabaseError(result.error))
        )
        return
      }

      setAttachedReel(null)
      setPendingReelFile(null)
    },
    [showPopup, userId]
  )

  const {
    requestDelete: requestDeleteAttachedReel,
    confirmModalProps: deleteAttachedReelConfirmProps,
  } = useDeleteReelConfirmation(performDeleteAttachedReel)

  const syncTradeReplayAfterSave = useCallback(
    async (
      userId: string,
      tradeId: string,
      reelFile?: File | null,
      onProgress?: UploadProgressReporter
    ): Promise<string | null> => {
      const file = reelFile ?? pendingReelFileRef.current
      if (!file) {
        devLog("[InputTradeForm] no replay file at save time")
        return null
      }

      devLog("[InputTradeForm] replay upload starting", {
        tradeId,
        userId,
        fileName: file.name,
        replacing: Boolean(attachedReel),
      })

      if (attachedReel) {
        onProgress?.({ percent: 70, stage: "Uploading replay…" })
        const result = await replaceTradeReelVideo(supabase, {
          reelId: attachedReel.id,
          userId,
          file,
        })
        if ("error" in result) {
          console.error("[InputTradeForm] replay replace failed", result.error)
          return result.error
        }
        setAttachedReel(result.reel)
        setPendingReelFile(null)
        devLog("[InputTradeForm] replay replace succeeded", {
          reelId: result.reel.id,
          tradeId: result.reel.trade_id,
        })
        return null
      }

      onProgress?.({ percent: 68, stage: "Uploading replay…" })
      const result = await publishTradeReel(supabase, {
        tradeId,
        userId,
        file,
        onProgress,
      })
      if ("error" in result) {
        console.error("[InputTradeForm] replay upload failed", result.error)
        return result.error
      }
      setAttachedReel(result.reel)
      setPendingReelFile(null)
      devLog("[InputTradeForm] replay upload succeeded", {
        reelId: result.reel.id,
        tradeId: result.reel.trade_id,
      })
      return null
    },
    [attachedReel]
  )

  async function handleSubmit() {
    if (submittingRef.current || submitting) return

    if (!selectedCopyGroupId && !selectedAccount) {
      setShowAccountWarning(true)
      return
    }

    if (
      entryTime &&
      exitTime &&
      isExitBeforeEntry(entryDate, entryTime, exitDate, exitTime)
    ) {
      showPopup(
        persistentError(
          "Invalid Trade Times",
          "Exit date and time must be after entry date and time."
        )
      )
      return
    }

    if (tradeFormHasFutureDate({ entryDate, exitDate })) {
      showPopup(feedbackPresets.invalidTradeDate())
      return
    }

    const reelFileAtSubmit = pendingReelFileRef.current ?? pendingReelFile
    const uploadTitle = isPublic
      ? image || reelFileAtSubmit
        ? "Uploading Trade"
        : "Posting Trade"
      : image || reelFileAtSubmit
        ? "Uploading Trade"
        : "Saving Trade"

    try {
      await runUpload({
        title: uploadTitle,
        onDismissCompose: () => {
          setCommunityPreviewOpen(false)
          onClose?.()
        },
        execute: async (report) => {
          uploadReportRef.current = report
          submittingRef.current = true
          setSubmitting(true)

    if (!userId) {
      showPopup(
        persistentError("Sign In Required", "Please log in to save your trade.")
      )
      throw new Error("Please log in to save your trade.")
    }

    const profileRow = planProfile ?? contextProfile
    const userIsPro = isProActive(profileRow)

    let screenshotUrl: string | null = null

    if (image) {
      const uploaded = await uploadContentImageToStorage(supabase, userId, image, {
        onProgress: report,
        uploadProgressRange: { start: 20, end: 62 },
      })
      if (uploaded.error) {
        const safeMessage = handleSupabaseError(
          uploaded.error,
          "We couldn't upload your trade image."
        )
        showPopup(
          persistentError(
            safeMessage.toLowerCase().includes("image")
              ? "Invalid Image"
              : "Upload Failed",
            safeMessage
          )
        )
        throw new Error(safeMessage)
      }
      screenshotUrl = uploaded.path
    } else {
      report({ percent: 35, stage: "Saving trade…" })
    }

    const parsedPnl = parseFloat(pnl) || 0
    const parsedRR = parseOptionalRr(rr)
    const parsedPoints = parseFloat(points) || 0
    const parsedContracts = Number.parseInt(contracts, 10)
    const contractsNum = Number.isFinite(parsedContracts) ? parsedContracts : 0

    const entryTimeForSave = buildDateTime(entryDate, entryTime)
    const autoDetectedSession = entryTimeForSave
      ? getSessionFromDate(entryTimeForSave)
      : null
    const cleanedSession = (session && String(session).trim()) || ""
    const sessionToSave = sessionManuallySet
      ? cleanedSession || "NY"
      : autoDetectedSession || cleanedSession || "NY"
    const tradeTypeToSave =
      tradeType != null && String(tradeType).trim() !== ""
        ? String(tradeType).trim()
        : null

    const psychologyVal =
      psychologyNotes != null && String(psychologyNotes).trim() !== ""
        ? String(psychologyNotes).trim()
        : null

    const timeframeToSave =
      timeframe === "Custom"
        ? customTimeframe.trim() || null
        : timeframe.trim() || null

    const selectedCopyGroup = selectedCopyGroupId
      ? (copyGroups.find((group) => group.id === selectedCopyGroupId) ?? null)
      : null

    if (selectedCopyGroup && !isEditMode) {
      const groupAccounts = resolveCopyGroupAccounts(selectedCopyGroup, accounts)
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
        ticker,
        direction,
        pnl: pnl ? Number(pnl) : null,
        rr: parsedRR,
        points: hasStoredTradePoints(points) ? Number(points) : null,
        contracts: contracts ? Number(contracts) : null,
        session: sessionToSave,
        notes: confluences || null,
        public_description: publicDescription,
        image_url: screenshotUrl,
        image_display_mode: screenshotDisplayMode,
        strategy: strategy || null,
        user_id: userId,
        created_at: now.toISOString(),
        date: now.toISOString(),
        trade_date: entryDate,
        entry_price: entryPrice ? Number(entryPrice) : null,
        exit_price: exitPrice ? Number(exitPrice) : null,
        entry_time: buildDateTime(entryDate, entryTime),
        exit_time: buildDateTime(exitDate, exitTime),
        psychology_notes: psychologyVal,
        trade_type: tradeTypeToSave,
        confidence: confidence ? Number(confidence) : null,
        emotion: emotion || null,
        followed_plan: followedPlan,
        mistake_type: mistakeType || null,
        market_condition: market || null,
        news_event: newsEvent,
        timeframe: timeframeToSave,
        is_public: isPublic,
      }

      const copyResult = await insertCopyTradedTrades({
        client: supabase,
        userId,
        isPro: userIsPro,
        groupId: selectedCopyGroup.id,
        accounts: groupAccounts,
        tradeTemplate,
        isPublic,
        postCaption: confluences,
      })

      if (!copyResult.ok) {
        showPopup(
          persistentError(
            "Save Failed",
            handleSupabaseError(copyResult.message)
          )
        )
        throw new Error(copyResult.message)
      }

      for (const trade of copyResult.trades) {
        const replayError = await syncTradeReplayAfterSave(
          userId,
          String(trade.id),
          reelFileAtSubmit,
          report
        )
        if (replayError) {
          showPopup(
            persistentError(
              "Clip Upload Failed",
              `Trades saved, but replay could not be uploaded for every account: ${replayError}`
            )
          )
        }
      }

      void refreshPlanAndAccountLock()
      setCommunityPreviewOpen(false)
      resetCreateForm()
      onSave?.()
      showPopup(
        isPublic
          ? feedbackPresets.postPublished()
          : feedbackPresets.tradeSaveSuccess()
      )
      notifyGettingStartedChecklistMaybeCompleted()
      releaseSubmit()
      return
    }

    const acct = selectedAccount
    if (!acct) {
      showPopup(
        persistentError("Select an Account", "Choose a trading account before saving.")
      )
      throw new Error("No account selected")
    }

    const modeLower = String(acct.mode ?? "live").trim().toLowerCase()

    const rowAcct = {
      type: modeLower,
      name: String(acct.name ?? "").trim() || null,
      size: String(acct.size ?? "").trim() || null,
      id: acct.id != null ? String(acct.id).trim() || null : null,
      account_number:
        String(acct.account_number ?? "").trim() || null,
      mode: String(acct.mode ?? "live"),
      category: acct.category ?? null,
    }

    const skipAccountRegistry =
      rowAcct.type === "backtest" || rowAcct.type === "imported"

    const ensured = await ensureManualUserAccountRegistered(supabase, {
      userId: userId,
      accountName: rowAcct.name ?? "",
      tradeAccountType: rowAcct.type,
      isPro: userIsPro,
      skipRegistry: skipAccountRegistry,
    })

    if (!ensured.ok) {
      if (ensured.reason === "limit") {
        showPopup(feedbackPresets.accountLimit())
        throw new Error("Account limit reached.")
      }
      showPopup(
        persistentError(
          "Save Failed",
          "Could not complete save. Please try again."
        )
      )
      throw new Error("Could not complete save. Please try again.")
    }

    if (isEditMode && existingTrade?.id) {
      let redirectToProfileAfterFirstPublic = false
      if (isPublic && existingTrade.is_public !== true) {
        const { count: publicTradeCount } = await supabase
          .from("trades")
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId)
          .eq("is_public", true)
        redirectToProfileAfterFirstPublic = (publicTradeCount ?? 0) === 0
      }

      const prevImg = existingTrade.image_url ?? null
      const imageUrlOut = removeScreenshot
        ? null
        : (screenshotUrl ?? prevImg)

      const entryVal = entryPrice.trim() === "" ? null : Number(entryPrice)
      const exitVal = exitPrice.trim() === "" ? null : Number(exitPrice)

      const updateRow: Record<string, unknown> = {
        ticker: ticker || null,
        direction,
        pnl: Number.isFinite(parsedPnl) ? parsedPnl : 0,
        rr: parsedRR,
        points: Number.isFinite(parsedPoints) ? parsedPoints : 0,
        contracts: contractsNum,
        session: sessionToSave,
        top_confluences: confluences || null,
        public_description: publicDescription ?? "",
        image_url: imageUrlOut,
        image_display_mode: screenshotDisplayMode,
        account_name: rowAcct.name,
        account_type: rowAcct.type,
        mode: rowAcct.mode,
        account_category: rowAcct.category,
        strategy:
          String(strategy).trim() !== "" ? String(strategy).trim() : null,
        account_size: rowAcct.size,
        account_id: rowAcct.id,
        created_at: existingTrade.created_at,
        entry_price:
          entryVal !== null && Number.isFinite(entryVal) ? entryVal : null,
        exit_price:
          exitVal !== null && Number.isFinite(exitVal) ? exitVal : null,
        entry_time: entryTime
          ? buildDateTime(entryDate, entryTime)
          : existingTrade.entry_time ?? null,
        exit_time: exitTime
          ? buildDateTime(exitDate, exitTime)
          : existingTrade.exit_time ?? null,
        trade_date: entryDate,
        psychology_notes: psychologyVal,
        trade_type: tradeTypeToSave,
        confidence: confidence ? Number(confidence) : null,
        emotion: emotion || null,
        followed_plan: followedPlan,
        mistake_type: mistakeType || null,
        market_condition: market || null,
        news_event: newsEvent,
        timeframe: timeframeToSave,
        is_public: isPublic,
        notes: confluences || null,
      }
      const csvReviewPending =
        existingTrade.is_initial_import === true &&
        existingTrade.reviewed === false
      if (forceMarkReviewedOnSave || csvReviewPending) {
        updateRow.reviewed = true
      }

      const { error } = await supabase
        .from("trades")
        .update(updateRow)
        .eq("id", existingTrade.id)

      if (error) {
        console.error("UPDATE ERROR:", error)
        showPopup(
        supabaseMutationFeedback(error, "Save Failed")
      )
        throw new Error(handleSupabaseError(error))
      }

      upsertTradeInCache(userId, {
        ...existingTrade,
        ...updateRow,
        id: existingTrade.id,
      })

      if (isPublic) {
        const { error: postErr } = await supabase.from("posts").upsert(
          {
            trade_id: existingTrade.id,
            user_id: userId,
            image_url: imageUrlOut,
            pnl: parsedPnl,
            rr: parsedRR,
            caption: confluences ?? "",
          },
          { onConflict: "trade_id" }
        )
        if (postErr) {
          console.error("posts upsert:", postErr)
          showPopup(
            supabaseMutationFeedback(postErr, "Post Failed")
          )
          throw new Error(handleSupabaseError(postErr))
        }
      } else {
        const { error: delErr } = await supabase
          .from("posts")
          .delete()
          .eq("trade_id", existingTrade.id)
        if (delErr) console.error("posts delete:", delErr)
      }

      if (existingTrade.is_public !== isPublic) {
        await syncTradeLinkedReelVisibility(
          supabase,
          String(existingTrade.id),
          isPublic
        )
      }

      const replayError = await syncTradeReplayAfterSave(
        userId,
        String(existingTrade.id),
        reelFileAtSubmit,
        report
      )
      if (replayError) {
        showPopup(
          persistentError(
            "Clip Upload Failed",
            `Trade saved, but replay could not be updated: ${replayError}`
          )
        )
      }

      void refreshPlanAndAccountLock()
      setCommunityPreviewOpen(false)
      onSave?.()
      onClose?.()
      showPopup(feedbackPresets.tradeSaveSuccess())
      notifyGettingStartedChecklistMaybeCompleted()
      if (redirectToProfileAfterFirstPublic) {
        const { data: navProfile } = await supabase
          .from("profiles")
          .select("username")
          .eq("id", userId)
          .maybeSingle()
        router.push(
          `${profilePath({
            id: userId,
            username: navProfile?.username,
          })}?trade=${encodeURIComponent(String(existingTrade.id))}`
        )
      }
      releaseSubmit()
      return
    }

    const now = new Date()

    devLog("FINAL SAVED DATE:", now.toISOString())

    const parsedTrade = {
      pnl: pnl ? Number(pnl) : null,
      entry_price: entryPrice ? Number(entryPrice) : null,
      exit_price: exitPrice ? Number(exitPrice) : null,
      contracts: contracts ? Number(contracts) : null,
      points: hasStoredTradePoints(points) ? Number(points) : null,
      rr: parseOptionalRr(rr),
    }

    const selectedDate = entryDate
    devLog("Saving trade_date:", selectedDate)

    const tradeData = {
      ticker,
      direction,
      pnl: parsedTrade.pnl,
      rr: parsedTrade.rr,
      points: parsedTrade.points,
      contracts: parsedTrade.contracts,
      session: sessionToSave,
      notes: confluences || null,
      public_description: publicDescription,
      image_url: screenshotUrl,
      image_display_mode: screenshotDisplayMode,
      account_name: rowAcct.name,
      account_size: rowAcct.size,
      account_id: rowAcct.id,
      mode: rowAcct.mode,
      account_category: rowAcct.category ?? null,
      account_type: rowAcct.type,
      strategy: strategy || null,
      user_id: userId,
      created_at: now.toISOString(),
      date: now.toISOString(),
      trade_date: selectedDate,
      entry_price: parsedTrade.entry_price,
      exit_price: parsedTrade.exit_price,
      entry_time: buildDateTime(entryDate, entryTime),
      exit_time: buildDateTime(exitDate, exitTime),
      psychology_notes: psychologyVal,
      trade_type: tradeTypeToSave,
      confidence: confidence ? Number(confidence) : null,
      emotion: emotion || null,
      followed_plan: followedPlan,
      mistake_type: mistakeType || null,
      market_condition: market || null,
      news_event: newsEvent,
      timeframe: timeframeToSave,
      is_public: isPublic,
    }

    const { data: newTradeData, error } = await supabase
      .from("trades")
      .insert([tradeData])
      .select()
      .single()

    if (error) {
      console.error("Trade insert error:", error)
      showPopup(
        supabaseMutationFeedback(error, "Save Failed")
      )
      throw new Error(handleSupabaseError(error))
    }

    if (newTradeData) {
      prependTradeInCache(userId, newTradeData)
      devLog("[InputTradeForm] trade created", {
        tradeId: newTradeData.id,
        isPublic,
      })
    }

    if (isPublic && newTradeData) {
      const { error: postError } = await supabase.from("posts").insert([
        {
          user_id: userId,
          trade_id: newTradeData.id,
          image_url: screenshotUrl,
          pnl: parsedPnl,
          rr: parsedRR,
          caption: confluences,
        },
      ])
      if (postError) {
        console.error("Post insert error:", postError)
        showPopup(
          supabaseMutationFeedback(postError, "Post Failed")
        )
        throw new Error(handleSupabaseError(postError))
      }

      const replayError = await syncTradeReplayAfterSave(
        userId,
        String(newTradeData.id),
        reelFileAtSubmit,
        report
      )
      if (replayError) {
        showPopup(
          persistentError(
            "Clip Upload Failed",
            `Trade posted, but replay could not be uploaded: ${replayError}`
          )
        )
      }

      void refreshPlanAndAccountLock()
      setCommunityPreviewOpen(false)
      resetCreateForm()
      onSave?.()
      showPopup(feedbackPresets.postPublished())
      notifyGettingStartedChecklistMaybeCompleted()
      releaseSubmit()
      return
    }

    if (newTradeData?.id) {
      const replayErrorPrivate = await syncTradeReplayAfterSave(
        userId,
        String(newTradeData.id),
        reelFileAtSubmit,
        report
      )
      if (replayErrorPrivate) {
        showPopup(
          persistentError(
            "Clip Upload Failed",
            `Trade saved, but replay could not be uploaded: ${replayErrorPrivate}`
          )
        )
      }
    }

    void refreshPlanAndAccountLock()
    setCommunityPreviewOpen(false)
    resetCreateForm()
    onSave?.()
    showPopup(feedbackPresets.tradeSaveSuccess())
    notifyGettingStartedChecklistMaybeCompleted()
    releaseSubmit()
        },
      })
    } catch {
      // Upload overlay handles retry/cancel.
    } finally {
      releaseSubmit()
    }
  }

  async function handlePublicToggle() {
    const nextIsPublic = !isPublic
    setIsPublic(nextIsPublic)
  }

  function selectTradeImage(file: File | undefined) {
    imageCrop.handleFileSelected(file)
  }

  function handleCropCancel() {
    imageCrop.handleCropCancel()
  }

  function handleCropSave(cropped: File) {
    if (imageCrop.cropSourceFile) {
      screenshotSourceRef.current = imageCrop.cropSourceFile
    }
    setRemoveScreenshot(false)
    setScreenshotDisplayMode(DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE)
    imageCrop.handleCropSave(cropped)
  }

  function handleDrop(e: React.DragEvent<HTMLDivElement>) {
    e.preventDefault()
    selectTradeImage(e.dataTransfer.files[0])
  }

  function handleClickUpload() {
    fileInputRef.current?.click()
  }

  async function ensureScreenshotSourceFile(): Promise<File | null> {
    if (screenshotSourceRef.current) return screenshotSourceRef.current
    if (image) {
      screenshotSourceRef.current = image
      return image
    }
    const existingUrl =
      existingTrade?.image_url != null
        ? postImageSrc(existingTrade.image_url)
        : null
    if (!existingUrl) return null
    const file = await fetchImageUrlAsFile(existingUrl, "trade-screenshot.jpg")
    screenshotSourceRef.current = file
    return file
  }

  function applyScreenshotDisplayMode(mode: TradeScreenshotDisplayMode) {
    if (screenshotModeBusy || submitting) return
    setScreenshotDisplayMode(mode)
    setRemoveScreenshot(false)
  }

  async function handleAdjustExistingScreenshot() {
    if (screenshotModeBusy || submitting) return
    setScreenshotModeBusy(true)
    try {
      const source = await ensureScreenshotSourceFile()
      if (!source) {
        showPopup(
          persistentError(
            "Screenshot Unavailable",
            "Could not load the current screenshot."
          )
        )
        return
      }
      imageCrop.handleFileSelected(source)
    } catch {
      showPopup(
        persistentError(
          "Adjust Failed",
          "Could not open the screenshot editor."
        )
      )
    } finally {
      setScreenshotModeBusy(false)
    }
  }

  function handleRemoveScreenshot() {
    setImage(null)
    setRemoveScreenshot(true)
    setScreenshotDisplayMode(DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE)
    screenshotSourceRef.current = null
    imageCrop.resetFileInput()
  }

  function handleUploadCsvGuardClick() {
    if (!onUploadCsvClick) return
    if (csvImportBlocked) {
      showPopup(feedbackPresets.csvSubscriptionLimit(csvDaysUntilNextImport ?? undefined))
      return
    }
    // Mobile Safari requires file input activation in the same user gesture — no await before click().
    onUploadCsvClick()
  }

  async function handleCsvManualImport() {
    if (csvImportingRef.current || csvImporting) return
    if (!selectedAccount) {
      showPopup(
        feedbackPresets.importFailed(
          "Please create or select an account before importing trades."
        )
      )
      return
    }

    csvImportingRef.current = true
    setCsvImporting(true)

    try {
      if (!userId) {
        showPopup(feedbackPresets.importFailed("Please log in first."))
        return
      }

      const rateLimit = await consumeAppRateLimit("csv_import")
      if (!rateLimit.ok) {
        showPopup(feedbackPresets.importFailed(rateLimit.message))
        return
      }

      const csvGate = await assertCsvImportAllowedForFreePlan(supabase, userId)
      if (!csvGate.ok) {
        setCsvImportBlocked(true)
        setCsvDaysUntilNextImport(csvGate.daysUntilNextImport)
        showPopup(
          feedbackPresets.csvSubscriptionLimit(csvGate.daysUntilNextImport)
        )
        return
      }

      if (csvTradesHaveFutureDate(parsedTrades)) {
        showPopup(feedbackPresets.csvImportFutureTradeDate())
        return
      }

      const { error } = await insertCsvTradesWithAccount(supabase, parsedTrades, {
        id: selectedAccount.id,
        name: selectedAccount.name,
        size: selectedAccount.size,
        mode: selectedAccount.mode,
        category: selectedAccount.category ?? null,
      })

      if (error) {
        console.error(error)
        showPopup(feedbackPresets.importFailed(handleSupabaseError(error)))
        return
      }

      showPopup(feedbackPresets.importSuccess(parsedTrades.length))
      notifyGettingStartedChecklistMaybeCompleted()

      if (!isProActive(planProfile ?? contextProfile)) {
        const { error: flagErr } = await markProfileCsvImportUsed(supabase, userId)
        if (flagErr) {
          console.error("markProfileCsvImportUsed:", flagErr)
        } else {
          setCsvImportBlocked(true)
          setCsvDaysUntilNextImport(FREE_PLAN_CSV_IMPORT_COOLDOWN_DAYS)
        }
      }

      onParsedTradesClear?.()
      setSelectedAccount(null)
      invalidateTradesCache(userId)
    } catch (err) {
      console.error(err)
      showPopup(supabaseMutationFeedback(err, "Import Failed"))
    } finally {
      csvImportingRef.current = false
      setCsvImporting(false)
    }
  }

  async function toggleAccount(account: { id: string; is_active?: boolean }) {
    if (togglingAccountId) return
    setTogglingAccountId(account.id)
    const currentlyActive = account.is_active !== false
    const nextActive = !currentlyActive

    const { error } = await supabase
      .from("accounts")
      .update({ is_active: nextActive })
      .eq("id", account.id)

    if (error) {
      console.error(error)
      showPopup(
        supabaseMutationFeedback(error, "Save Failed")
      )
      setTogglingAccountId(null)
      return
    }

    setAccounts((prev) =>
      prev.map((a) =>
        String(a.id) === String(account.id)
          ? { ...a, is_active: nextActive }
          : a
      )
    )

    if (selectedAccount && String(selectedAccount.id) === String(account.id)) {
      if (!nextActive) {
        setSelectedAccount(null)
      } else {
        setSelectedAccount({ ...selectedAccount, is_active: true })
      }
    }
    setTogglingAccountId(null)
  }

  async function handleCreateAccountSave(newAccount: CreateAccountSavePayload) {
    if (creatingAccountRef.current || creatingAccount) return

    creatingAccountRef.current = true
    setCreatingAccount(true)

    try {
    if (!userId) return

    const profile = planProfile ?? contextProfile

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

    const { data, error } = await supabase
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

    if (error) {
      console.error(error)
      showPopup(
        supabaseMutationFeedback(error, "Save Failed")
      )
      return
    }

    if (!data) return

    upsertAccountInCache(userId, data)

    setAccounts((prev) => [
      ...prev,
      {
        name: data.name,
        size: data.account_size,
        id: data.id,
        account_number: data.account_number ?? null,
        mode: data.mode,
        category: data.category,
        is_active: data.is_active !== false,
        can_add_trades: data.can_add_trades !== false,
        note: data.note ?? "",
      },
    ])

    setSelectedAccount({
      name: data.name,
      size: data.account_size,
      id: data.id,
      account_number: data.account_number ?? null,
      mode: data.mode,
      category: data.category,
      is_active: data.is_active !== false,
      can_add_trades: data.can_add_trades !== false,
      note: data.note ?? "",
    })

    setShowCreateModal(false)
    void refreshPlanAndAccountLock()
    } finally {
      creatingAccountRef.current = false
      setCreatingAccount(false)
    }
  }

  const entryDateTime = entryTime ? buildDateTime(entryDate, entryTime) : null
  const exitDateTime = exitTime ? buildDateTime(exitDate, exitTime) : null
  const duration = getTradeFormDuration(entryDateTime, exitDateTime)
  const invalidTimeRange =
    entryTime &&
    exitTime &&
    isExitBeforeEntry(entryDate, entryTime, exitDate, exitTime)

  const invalidFutureDate = tradeFormHasFutureDate({ entryDate, exitDate })

  function handleEntryDateChange(nextEntryDate: string) {
    if (isDateAfterToday(nextEntryDate)) {
      showPopup(feedbackPresets.invalidTradeDate())
    }
    setEntryDate((prevEntry) => {
      setExitDate((prevExit) => (prevExit === prevEntry ? nextEntryDate : prevExit))
      return nextEntryDate
    })
  }

  function handleExitDateChange(nextExitDate: string) {
    if (isDateAfterToday(nextExitDate)) {
      showPopup(feedbackPresets.invalidTradeDate())
    }
    setExitDate(nextExitDate)
  }

  useEffect(() => {
    if (sessionManuallySet || !entryDateTime) return
    const detected = getSessionFromDate(entryDateTime)
    if (detected && (session === "" || session === "NY")) {
      setSession(detected)
    }
  }, [entryDateTime, session, sessionManuallySet])

  const fieldLabelClass = TRADE_FIELD_LABEL_CLASS

  const communityPreviewImageUrl = useMemo(() => {
    if (removeScreenshot) return null
    if (screenshotPreviewUrl) return screenshotPreviewUrl
    if (existingTrade?.image_url) {
      return postImageSrc(existingTrade.image_url)
    }
    return null
  }, [removeScreenshot, screenshotPreviewUrl, existingTrade?.image_url])

  const editScreenshotPreviewSrc = useMemo(() => {
    if (!isEditMode || removeScreenshot) return null
    if (screenshotPreviewUrl) return screenshotPreviewUrl
    if (existingTrade?.image_url) {
      return postImageSrc(existingTrade.image_url)
    }
    return null
  }, [
    isEditMode,
    removeScreenshot,
    screenshotPreviewUrl,
    existingTrade?.image_url,
  ])

  const editScreenshotHasImage = Boolean(editScreenshotPreviewSrc)
  const editScreenshotPreviewObjectClass = tradeScreenshotObjectFitClass(
    screenshotDisplayMode
  )

  const communityPreviewPost = useMemo(() => {
    if (!userId) return null
    const previewEntryTime = entryTime
      ? buildDateTime(entryDate, entryTime)
      : null
    const previewExitTime = exitTime
      ? buildDateTime(exitDate, exitTime)
      : null
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
      accountType:
        selectedAccount?.account_type ??
        existingTrade?.account_type ??
        existingTrade?.mode,
      lockedAccountType: planProfile?.locked_account_type,
      isPro,
      publicDescription,
      imageUrl: communityPreviewImageUrl,
      entryTime: previewEntryTime,
      exitTime: previewExitTime,
      entryPrice: entryPrice.trim() === "" ? null : entryPrice,
      exitPrice: exitPrice.trim() === "" ? null : exitPrice,
      tradeDate: entryDate,
      attachedReel: pendingReelFile ? true : attachedReel,
    })
  }, [
    userId,
    planProfile?.username,
    planProfile?.avatar_url,
    planProfile?.locked_account_type,
    pnl,
    rr,
    points,
    ticker,
    direction,
    selectedAccount,
    existingTrade?.account_type,
    existingTrade?.mode,
    isPro,
    publicDescription,
    communityPreviewImageUrl,
    entryDate,
    entryTime,
    exitDate,
    exitTime,
    entryPrice,
    exitPrice,
    pendingReelFile,
    attachedReel,
  ])

  const communityPreviewUser = useMemo(
    () => (userId ? { id: userId } : null),
    [userId]
  )

  const tradeTimeframeOptions = TRADE_TIMEFRAME_OPTIONS

  const quickInputButtonClass =
    "shrink-0 rounded-lg border border-blue-500/30 bg-blue-500/10 px-3 py-2 text-sm font-medium text-blue-100 transition hover:bg-blue-500/20 disabled:cursor-not-allowed disabled:opacity-60 md:px-4"

  const formBody = (
    <>
      <div className={isEditMode ? "mb-2" : "mb-4"}>
        <div className="flex flex-col gap-3 md:hidden">
          <div className="flex items-center gap-2">
            <TradeAccountPicker
              className="min-w-0 flex-1 md:flex-none"
              accounts={pickerAccounts}
              isPro={isPro}
              copyGroups={copyGroups}
              selectedAccount={selectedAccount}
              selectedCopyGroupId={selectedCopyGroupId}
              onSelect={setSelectedAccount}
              onSelectCopyGroup={setSelectedCopyGroupId}
              onOpenCreate={() => setShowCreateModal(true)}
              disableCreate={accountFieldsLocked}
              showExternalCreateButton={false}
            />
            {!isEditMode && onQuickInputClick ? (
              <button
                type="button"
                onClick={onQuickInputClick}
                className={quickInputButtonClass}
              >
                Quick Input
              </button>
            ) : null}
            <button
              type="button"
              onClick={() => setShowSettings(true)}
              className="p-2 bg-[#1f2937] rounded-lg flex items-center justify-center"
              aria-label="Settings"
            >
              ⚙️
            </button>
          </div>
          {!isEditMode ? (
            <div className="flex gap-2">
              <button
                type="button"
                onClick={handleUploadCsvGuardClick}
                disabled={!onUploadCsvClick || csvLoading || csvImportBlocked}
                className="shrink-0 flex-1 px-3 py-2 text-sm rounded-lg bg-blue-500 text-white disabled:opacity-60"
              >
                Upload CSV
              </button>
              <button
                type="button"
                onClick={onReviewCsvClick}
                disabled={!onReviewCsvClick}
                className="shrink-0 relative flex-1 px-3 py-2 text-sm rounded-lg bg-blue-500 text-white hover:bg-blue-600 disabled:opacity-60 disabled:hover:bg-blue-500"
              >
                Review CSV
                {reviewCount > 0 ? (
                  <span className="absolute -top-1 -right-1 bg-red-500 text-white rounded-full text-[10px] px-1.5 py-0.5">
                    {reviewCount > 99 ? "99+" : reviewCount}
                  </span>
                ) : null}
              </button>
            </div>
          ) : null}
          {!isEditMode && parsedTrades.length > 0 && !csvDiagnostics ? (
            <button
              type="button"
              onClick={() => void handleCsvManualImport()}
              disabled={!selectedAccount || csvImporting}
              className={`w-full px-4 py-2 rounded text-sm disabled:cursor-not-allowed disabled:opacity-50 ${
                selectedAccount
                  ? "bg-green-500/20 text-green-400"
                  : "bg-gray-700 text-gray-400 cursor-not-allowed"
              }`}
            >
              {csvImporting
                ? "Importing…"
                : `Import ${parsedTrades.length}`}
            </button>
          ) : null}
        </div>

        <div className="hidden md:flex items-center w-full gap-3 min-w-0">
          <div className="flex min-w-0 flex-1 items-center gap-3 flex-wrap">
            <TradeAccountPicker
              className="shrink-0"
              accounts={pickerAccounts}
              isPro={isPro}
              copyGroups={copyGroups}
              selectedAccount={selectedAccount}
              selectedCopyGroupId={selectedCopyGroupId}
              onSelect={setSelectedAccount}
              onSelectCopyGroup={setSelectedCopyGroupId}
              onOpenCreate={() => setShowCreateModal(true)}
              disableCreate={accountFieldsLocked}
              showExternalCreateButton={false}
            />

            {!isEditMode && onQuickInputClick ? (
              <button
                type="button"
                onClick={onQuickInputClick}
                className={quickInputButtonClass}
              >
                Quick Input
              </button>
            ) : null}

            {!isEditMode ? (
              <>
                <button
                  type="button"
                  onClick={handleUploadCsvGuardClick}
                  disabled={!onUploadCsvClick || csvLoading || csvImportBlocked}
                  className="shrink-0 px-4 py-2 text-sm rounded-lg bg-blue-500 text-white disabled:opacity-60"
                >
                  Upload CSV
                </button>

                {parsedTrades.length > 0 && !csvDiagnostics ? (
                  <button
                    type="button"
                    onClick={() => void handleCsvManualImport()}
                    disabled={!selectedAccount || csvImporting}
                    className={`ml-2 px-4 py-2 rounded disabled:cursor-not-allowed disabled:opacity-50 ${
                      selectedAccount
                        ? "bg-green-500/20 text-green-400"
                        : "bg-gray-700 text-gray-400 cursor-not-allowed"
                    }`}
                  >
                    {csvImporting
                      ? "Importing…"
                      : `Import ${parsedTrades.length}`}
                  </button>
                ) : null}

                <button
                  type="button"
                  onClick={onReviewCsvClick}
                  disabled={!onReviewCsvClick}
                  className="shrink-0 relative px-4 py-2 text-sm rounded-lg bg-blue-500 text-white hover:bg-blue-600 disabled:opacity-60 disabled:hover:bg-blue-500"
                >
                  Review CSV
                  {reviewCount > 0 ? (
                    <span className="absolute -top-1 -right-1 bg-red-500 text-white rounded-full text-[10px] px-1.5 py-0.5">
                      {reviewCount > 99 ? "99+" : reviewCount}
                    </span>
                  ) : null}
                </button>
              </>
            ) : null}
          </div>

          <div className="ml-auto">
            <button
              type="button"
              onClick={() => setShowSettings(true)}
              className="p-2 bg-[#1f2937] rounded-lg flex items-center justify-center"
              aria-label="Settings"
            >
              ⚙️
            </button>
          </div>
        </div>
      </div>

      {csvUnrecognized && parsedTrades.length === 0 ? (
        <CsvImportUnsupportedBanner brokerHint={csvBrokerHint} className="mb-4" />
      ) : null}

      {csvDiagnostics ? (
        <CsvImportDiagnosticsPanel
          diagnostics={csvDiagnostics}
          className="mb-4"
          csvFile={csvSupportFile}
          brokerName={csvBrokerHint ?? csvDiagnostics.formatLabel}
          importedRowCount={
            csvDataRowCount > 0 ? csvDataRowCount : parsedTrades.length
          }
          importableRowCount={parsedTrades.length}
          canImport={Boolean(selectedAccount)}
          importDisabledHint="Select an account above before importing."
          importing={csvImporting}
          onImportRows={handleCsvManualImport}
        />
      ) : null}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="px-4 pb-4 pt-3 rounded-xl bg-[#0b1220]/60 border border-white/5">
          <h3 className={TRADE_FIELD_SECTION_TITLE_CLASS}>Trade</h3>
          <div className="space-y-2">
          <div>
            <label className={fieldLabelClass}>P&amp;L</label>
            <TradeFormCurrencyInput
              value={pnl}
              onChange={setPnl}
              allowNegative
              onDecimalError={setDecimalError}
              tabIndex={1}
              inputClassName={TRADE_FIELD_CURRENCY_CONTROL_CLASS}
            />
          </div>
          {decimalError && (
            <p className="text-red-400 text-xs mt-1">
              {decimalError}
            </p>
          )}

          <div>
            <label className={fieldLabelClass}>Symbol / Ticker</label>
            <input
              type="text"
              placeholder="e.g. MNQ, ES, AAPL"
              tabIndex={2}
              value={ticker}
              onChange={(e) => setTicker(e.target.value.toUpperCase())}
              className={TRADE_FIELD_CONTROL_CLASS}
            />
          </div>

          <div>
            <label className={fieldLabelClass}>Strategy Used</label>
            <input
              type="text"
              placeholder="e.g. Breakout, Liquidity Sweep"
              tabIndex={3}
              value={strategy}
              onChange={(e) => setStrategy(e.target.value)}
              className={TRADE_FIELD_CONTROL_CLASS}
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
          <div>
            <label className={fieldLabelClass}>Direction</label>
            <CustomSelect
              tabIndex={4}
              value={direction}
              onChange={setDirection}
              triggerClassName={SELECT_TRIGGER_COMPACT_CLASS}
              options={[
                { label: "Long", value: "Long" },
                { label: "Short", value: "Short" },
              ]}
            />
          </div>

          <div>
            <label className={fieldLabelClass}>Session</label>
            <CustomSelect
              tabIndex={5}
              value={session}
              onChange={(val) => {
                setSessionManuallySet(true)
                setSession(val)
              }}
              triggerClassName={SELECT_TRIGGER_COMPACT_CLASS}
              options={[
                { label: "NY", value: "NY" },
                { label: "London", value: "London" },
                { label: "Asia", value: "Asia" },
                { label: "After", value: "After" },
              ]}
            />
          </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
            <div>
              <label className={fieldLabelClass}>Risk Reward</label>
              <input
                placeholder="e.g. 2.5"
                type="text"
                tabIndex={6}
                value={rr}
                onChange={(e) =>
                  handleTradeNumericInput(e.target.value, setRR, {
                    allowDecimal: true,
                    onDecimalError: setDecimalError,
                  })
                }
                className={TRADE_FIELD_CONTROL_CLASS}
              />
            </div>
            <div>
              <label className={fieldLabelClass}>Points</label>
              <input
                placeholder="e.g. 15.5"
                type="text"
                tabIndex={7}
                value={getTradeFormCurrencyInputDisplayValue(points)}
                onChange={(e) =>
                  handleTradeNumericInput(e.target.value, setPoints, {
                    allowDecimal: true,
                    allowNegative: true,
                    onDecimalError: setDecimalError,
                  })
                }
                className={TRADE_FIELD_CONTROL_CLASS}
              />
            </div>
          </div>

          <div>
            <label className={fieldLabelClass}>Contracts</label>
            <input
              placeholder="e.g. 4"
              type="text"
              tabIndex={8}
              value={formatWithCommas(contracts)}
              onChange={(e) =>
                handleTradeNumericInput(e.target.value, setContracts, {
                  onDecimalError: setDecimalError,
                })
              }
              className={TRADE_FIELD_CONTROL_CLASS}
            />
          </div>

          <div>
            <label className={fieldLabelClass}>Top Confluences</label>
            <textarea
              placeholder="What confirmations led to this trade?"
              tabIndex={9}
              value={confluences}
              onChange={(e) => setConfluences(e.target.value)}
              className={TRADE_FIELD_TEXTAREA_CLASS}
            />
          </div>

          </div>
        </div>

        <div className="px-4 pb-4 pt-3 rounded-xl bg-[#0b1220]/60 border border-white/5">
          <h3 className={TRADE_FIELD_SECTION_TITLE_CLASS}>Execution</h3>
          <div className="space-y-2">
          <div className="space-y-2 mb-4">
            <div>
              <label className={fieldLabelClass}>Entry Price</label>
              <TradeFormCurrencyInput
                value={entryPrice}
                onChange={setEntryPrice}
                onDecimalError={setDecimalError}
                tabIndex={10}
                inputClassName={TRADE_FIELD_CURRENCY_CONTROL_CLASS}
              />
            </div>
            <div>
              <label className={fieldLabelClass}>Exit Price</label>
              <TradeFormCurrencyInput
                value={exitPrice}
                onChange={setExitPrice}
                onDecimalError={setDecimalError}
                tabIndex={11}
                inputClassName={TRADE_FIELD_CURRENCY_CONTROL_CLASS}
              />
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
              <div>
                <label className={fieldLabelClass} htmlFor="entry-date">
                  Entry Date
                </label>
                <NativeDateInput
                  id="entry-date"
                  tabIndex={12}
                  value={entryDate}
                  onChange={(e) => handleEntryDateChange(e.target.value)}
                  className="tt-date-field--compact mt-0 rounded border border-white/10 bg-[#0f172a]"
                />
              </div>
              <div>
                <label className={fieldLabelClass} htmlFor="entry-time">
                  Entry Time
                </label>
                <NativeTimeInput
                  id="entry-time"
                  tabIndex={13}
                  value={entryTime}
                  onChange={(e) => setEntryTime(e.target.value)}
                  className="mt-0"
                />
              </div>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
              <div>
                <label className={fieldLabelClass} htmlFor="exit-date">
                  Exit Date
                </label>
                <NativeDateInput
                  id="exit-date"
                  tabIndex={14}
                  value={exitDate}
                  onChange={(e) => handleExitDateChange(e.target.value)}
                  className="tt-date-field--compact mt-0 rounded border border-white/10 bg-[#0f172a]"
                />
              </div>
              <div>
                <label className={fieldLabelClass} htmlFor="exit-time">
                  Exit Time
                </label>
                <NativeTimeInput
                  id="exit-time"
                  tabIndex={15}
                  value={exitTime}
                  onChange={(e) => setExitTime(e.target.value)}
                  className="mt-0"
                />
              </div>
            </div>
            {duration && (
              <p className={TRADE_FIELD_HELPER_CLASS}>
                Duration: {duration}
              </p>
            )}
            {invalidTimeRange && (
              <p className="text-xs text-red-400">
                Exit date and time must be after entry date and time
              </p>
            )}
          </div>

          <div className="mt-0">
            <label className={fieldLabelClass}>Public Description</label>
            <textarea
              tabIndex={16}
              value={publicDescription}
              onChange={(e) => setPublicDescription(e.target.value)}
              placeholder="Insert public thoughts..."
              className={TRADE_FIELD_PUBLIC_NOTES_CLASS}
            />
          </div>

          <TradePublicShareToggle
            isPublic={isPublic}
            onToggle={() => void handlePublicToggle()}
          />

          </div>
        </div>

        <div className="px-4 pb-4 pt-3 rounded-xl bg-[#0b1220]/60 border border-white/5">
          <h3 className={TRADE_FIELD_SECTION_TITLE_CLASS}>Psychology</h3>
          <div className="space-y-2">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
          <div>
            <label className={fieldLabelClass}>Trade Conviction</label>
            <CustomSelect
              tabIndex={18}
              value={confidence}
              onChange={setConfidence}
              placeholder="Conviction Level"
              triggerClassName={SELECT_TRIGGER_COMPACT_CLASS}
              options={[
                { label: "1 - Bad", value: "1" },
                { label: "2", value: "2" },
                { label: "3", value: "3" },
                { label: "4", value: "4" },
                { label: "5 - Good", value: "5" },
              ]}
            />
          </div>
          <div>
            <label className={fieldLabelClass}>Timeframe</label>
            <CustomSelect
              tabIndex={21}
              value={timeframe}
              onChange={setTimeframe}
              placeholder="Select timeframe"
              triggerClassName={SELECT_TRIGGER_COMPACT_CLASS}
              options={tradeTimeframeOptions.map((option) => ({
                label: option,
                value: option,
              }))}
            />
            {timeframe === "Custom" ? (
              <div className="mt-2">
                <label className={fieldLabelClass}>Custom Timeframe</label>
                <input
                  type="text"
                  tabIndex={22}
                  value={customTimeframe}
                  onChange={(e) => setCustomTimeframe(e.target.value)}
                  placeholder="e.g. 45 Second, 2 Minute, 12 Minute, 3 Hour"
                  className={TRADE_FIELD_CONTROL_LG_CLASS}
                />
              </div>
            ) : null}
          </div>
          </div>
          <div>
            <label className={fieldLabelClass}>Emotion</label>
            <CustomSelect
              tabIndex={19}
              value={emotion}
              onChange={setEmotion}
              placeholder="Select emotion"
              triggerClassName={SELECT_TRIGGER_COMPACT_CLASS}
              options={[
                { label: "Confident", value: "Confident" },
                { label: "Calm", value: "Calm" },
                { label: "Focused", value: "Focused" },
                { label: "Fearful", value: "Fearful" },
                { label: "FOMO", value: "FOMO" },
                { label: "Overconfident", value: "Overconfident" },
                { label: "Hesitant", value: "Hesitant" },
                { label: "Frustrated", value: "Frustrated" },
              ]}
            />
          </div>
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-6">
            <label className={TRADE_FIELD_CHECKBOX_LABEL_CLASS}>
              <input
                type="checkbox"
                tabIndex={22}
                checked={followedPlan}
                onChange={(e) => setFollowedPlan(e.target.checked)}
              />
              Followed Bias?
            </label>
            <label className={TRADE_FIELD_CHECKBOX_LABEL_CLASS}>
              <input
                type="checkbox"
                tabIndex={23}
                checked={newsEvent}
                onChange={(e) => setNewsEvent(e.target.checked)}
              />
              News Event?
            </label>
          </div>
          <div>
            <label className={fieldLabelClass}>Market</label>
            <CustomSelect
              tabIndex={20}
              value={market}
              onChange={setMarket}
              placeholder="Select market condition"
              triggerClassName={SELECT_TRIGGER_COMPACT_CLASS}
              options={[
                { label: "Trending", value: "Trending" },
                { label: "Strong Trend", value: "Strong Trend" },
                { label: "Ranging", value: "Ranging" },
                { label: "Choppy", value: "Choppy" },
                { label: "Low Volume", value: "Low Volume" },
                { label: "High Volume", value: "High Volume" },
                { label: "News Driven", value: "News Driven" },
                { label: "Volatile", value: "Volatile" },
              ]}
            />
          </div>
          <div className="space-y-1">
          <div>
            <label className={fieldLabelClass}>Psychology Notes</label>
            <textarea
              placeholder="Describe your thought process before, during, and after the trade."
              tabIndex={24}
              value={psychologyNotes}
              onChange={(e) => setPsychologyNotes(e.target.value)}
              className={`${TRADE_FIELD_TEXTAREA_CLASS} xl:h-28`}
            />
          </div>

          <div>
            <label className={fieldLabelClass}>Screenshot</label>
            {isEditMode ? (
              <div className="mt-2 space-y-2">
                {editScreenshotHasImage ? (
                  <div
                    className="relative aspect-[4/3] w-full overflow-hidden rounded-lg border border-white/10 bg-[#0f172a]"
                    onDrop={handleDrop}
                    onDragOver={(e) => e.preventDefault()}
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={editScreenshotPreviewSrc ?? undefined}
                      alt="Trade screenshot preview"
                      className={`h-full w-full ${editScreenshotPreviewObjectClass}`}
                    />
                    {screenshotModeBusy ? (
                      <div className="absolute inset-0 flex items-center justify-center bg-black/40 text-sm text-white">
                        Updating…
                      </div>
                    ) : null}
                  </div>
                ) : (
                  <div
                    tabIndex={25}
                    onClick={handleClickUpload}
                    onDrop={handleDrop}
                    onDragOver={(e) => e.preventDefault()}
                    className={TRADE_FULL_INPUT_MEDIA_UPLOAD_CLASS}
                  >
                    <p>Upload Screenshot</p>
                  </div>
                )}

                {editScreenshotHasImage ? (
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      disabled={screenshotModeBusy || submitting}
                      onClick={() => applyScreenshotDisplayMode("fit")}
                      className={`rounded-lg border px-3 py-1.5 text-xs font-medium transition disabled:opacity-40 ${
                        screenshotDisplayMode === "fit"
                          ? "border-blue-500 bg-blue-500/20 text-white"
                          : "border-white/15 bg-white/5 text-gray-200 hover:bg-white/10"
                      }`}
                    >
                      Fit
                    </button>
                    <button
                      type="button"
                      disabled={screenshotModeBusy || submitting}
                      onClick={() => applyScreenshotDisplayMode("fill")}
                      className={`rounded-lg border px-3 py-1.5 text-xs font-medium transition disabled:opacity-40 ${
                        screenshotDisplayMode === "fill"
                          ? "border-blue-500 bg-blue-500/20 text-white"
                          : "border-white/15 bg-white/5 text-gray-200 hover:bg-white/10"
                      }`}
                    >
                      Fill
                    </button>
                    <button
                      type="button"
                      disabled={screenshotModeBusy || submitting}
                      onClick={() => void handleAdjustExistingScreenshot()}
                      className="rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-40"
                    >
                      Adjust
                    </button>
                  </div>
                ) : null}

                <div className="flex flex-wrap gap-2">
                  {editScreenshotHasImage ? (
                    <>
                      <button
                        type="button"
                        tabIndex={25}
                        disabled={screenshotModeBusy || submitting}
                        onClick={handleClickUpload}
                        className="rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-40"
                      >
                        Replace image
                      </button>
                      <button
                        type="button"
                        disabled={screenshotModeBusy || submitting}
                        onClick={handleRemoveScreenshot}
                        className="rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-medium text-red-300 transition hover:bg-white/10 disabled:opacity-40"
                      >
                        Remove
                      </button>
                    </>
                  ) : null}
                </div>

                <input
                  ref={fileInputRef}
                  type="file"
                  className="hidden"
                  accept="image/*"
                  onChange={(e) => {
                    selectTradeImage(e.target.files?.[0])
                  }}
                />
              </div>
            ) : (
              <div
                tabIndex={25}
                onClick={handleClickUpload}
                onDrop={handleDrop}
                onDragOver={(e) => e.preventDefault()}
                className={TRADE_FULL_INPUT_MEDIA_UPLOAD_CLASS}
              >
                {image ? (
                  <p>{image.name}</p>
                ) : (
                  <p>Upload Screenshot</p>
                )}
                <input
                  ref={fileInputRef}
                  type="file"
                  className="hidden"
                  accept="image/*"
                  onChange={(e) => {
                    selectTradeImage(e.target.files?.[0])
                  }}
                />
              </div>
            )}

          <TradeReelAttachment
            variant="full"
            disabled={submitting}
            pendingFile={pendingReelFile}
            onPendingFileChange={setPendingReelFile}
            attachedReel={isEditMode ? attachedReel : null}
            onDeleteAttached={
              isEditMode && attachedReel
                ? () => requestDeleteAttachedReel(attachedReel)
                : undefined
            }
            deleteBusy={reelDeleteBusy}
          />
          </div>
          </div>

          <button
            type="button"
            tabIndex={26}
            disabled={
              submitting ||
              invalidFutureDate ||
              (!isEditMode && isPublic && !communityPreviewPost)
            }
            onClick={() => {
              if (isEditMode || !isPublic) {
                void handleSubmit()
                return
              }
              setCommunityPreviewOpen(true)
            }}
            className="w-full py-3 text-lg font-semibold rounded bg-blue-500 hover:bg-blue-600 text-white disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500"
          >
            {isEditMode
              ? "Save changes"
              : isPublic
                ? "Preview Post"
                : "Save Trade"}
          </button>
          </div>
        </div>
      </div>
    </>
  )

  const visibleAccountsInSettings = showAllAccounts
    ? sortedAccountsForSettings
    : sortedAccountsForSettings.slice(0, 3)

  function toggleMenu(id: string) {
    setOpenMenuId((prev) => (prev === id ? null : id))
  }

  function openNoteEditor(account: any) {
    setOpenMenuId(null)
    setEditingAccount({ ...account, note: account.note ?? "" })
  }

  async function saveNote(account: { id: string; note?: string }) {
    if (savingNoteId) return
    const noteVal = account.note ?? ""
    setSavingNoteId(String(account.id))
    const ok = await updateNote(String(account.id), noteVal)
    setSavingNoteId(null)
    if (!ok) return
    setAccounts((prev) =>
      prev.map((a) =>
        String(a.id) === String(account.id) ? { ...a, note: noteVal } : a
      )
    )
    if (selectedAccount && String(selectedAccount.id) === String(account.id)) {
      setSelectedAccount({ ...selectedAccount, note: noteVal })
    }
    setEditingAccount(null)
  }

  const settingsModal = (
    <Modal
      open={showSettings}
      onClose={() => setShowSettings(false)}
      title="Account Settings"
      size="sm"
      panelClassName="w-[min(440px,92vw)]"
      footer={
        <button
          type="button"
          onClick={() => setShowSettings(false)}
          className="w-full rounded-lg bg-blue-500 py-2 font-semibold text-white transition hover:bg-blue-600"
        >
          Done
        </button>
      }
    >
      <div className="rounded-lg border border-white/10 bg-white/5 p-3 space-y-2">
          <p className="text-sm font-medium text-white">Accounts</p>
          <p className="text-xs text-gray-400">
            Inactive accounts stay linked to trades but are hidden from the
            account picker. Read-only accounts keep full history and cannot
            receive new trades on Free.
          </p>
          {accounts.length === 0 ? (
            <p className="text-sm text-gray-400">No accounts yet.</p>
          ) : (
            <>
              {visibleAccountsInSettings.map((account) => {
                const title = formatAccountNameWithSizeDisplay(
                  account.name,
                  account.size
                )
                const accountIdLabel =
                  safeAccountNumberLabel(account.account_number) ?? "--"
                return (
                  <div
                    key={String(account.id)}
                    className="relative rounded-lg border border-white/10 bg-white/[0.03] p-3"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <span className="block truncate text-sm text-white">
                          {title || "—"}
                        </span>
                        <span className="mt-0.5 block truncate text-xs text-gray-400">
                          · ID: {accountIdLabel}
                        </span>
                        {account.can_add_trades === false ? (
                          <span className="mt-1 inline-flex rounded bg-amber-500/15 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-amber-200">
                            {ACCOUNT_READ_ONLY_BADGE}
                          </span>
                        ) : null}
                        {account.note?.trim() ? (
                          <p className="mt-1 truncate text-xs text-gray-400">
                            {account.note.trim()}
                          </p>
                        ) : null}
                      </div>
                      <div className="flex shrink-0 items-center gap-3">
                        <button
                          type="button"
                          disabled={togglingAccountId === String(account.id)}
                          onClick={() => void toggleAccount(account)}
                          className={`rounded px-3 py-1 text-xs font-medium disabled:cursor-not-allowed disabled:opacity-50 ${
                            account.is_active !== false
                              ? "bg-green-500/20 text-green-300"
                              : "bg-red-500/20 text-red-300"
                          }`}
                        >
                          {account.is_active !== false ? "Active" : "Inactive"}
                        </button>
                        <div
                          className="relative"
                          data-account-settings-menu
                        >
                          <button
                            type="button"
                            aria-label="Account options"
                            onClick={() => toggleMenu(String(account.id))}
                            className="rounded px-1.5 py-0.5 text-lg leading-none text-gray-400 hover:bg-white/10 hover:text-white"
                          >
                            ⋯
                          </button>
                          {openMenuId === String(account.id) ? (
                            <div className="absolute right-0 top-full z-[120] mt-1 w-44 rounded-lg border border-white/10 bg-[#0b1f3a] p-1.5 shadow-lg">
                              <button
                                type="button"
                                onClick={() => openNoteEditor(account)}
                                className="w-full rounded px-2 py-1.5 text-left text-sm text-white hover:bg-white/10"
                              >
                                Add / Edit Note
                              </button>
                            </div>
                          ) : null}
                        </div>
                      </div>
                    </div>
                    {editingAccount &&
                    String(editingAccount.id) === String(account.id) ? (
                      <div className="mt-3 space-y-2 rounded border border-white/10 bg-white/[0.04] p-3">
                        <input
                          value={editingAccount.note ?? ""}
                          onChange={(e) =>
                            setEditingAccount({
                              ...editingAccount,
                              note: e.target.value,
                            })
                          }
                          placeholder="Note (e.g. blown, passed...)"
                          className="w-full rounded border border-white/10 bg-white/5 px-2 py-1.5 text-sm text-white placeholder:text-gray-400"
                        />
                        <div className="flex flex-wrap items-center gap-3">
                          <button
                            type="button"
                            disabled={
                              savingNoteId === String(editingAccount.id)
                            }
                            onClick={() => void saveNote(editingAccount)}
                            className="text-sm font-medium text-blue-400 hover:text-blue-300 disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            {savingNoteId === String(editingAccount.id)
                              ? "Saving…"
                              : "Save"}
                          </button>
                          <button
                            type="button"
                            disabled={
                              savingNoteId === String(editingAccount.id)
                            }
                            onClick={() => setEditingAccount(null)}
                            className="text-sm text-gray-400 hover:text-gray-300 disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    ) : null}
                  </div>
                )
              })}
              {sortedAccountsForSettings.length > 3 ? (
                <button
                  type="button"
                  onClick={() => setShowAllAccounts(!showAllAccounts)}
                  className="mt-2 text-sm text-blue-400 hover:text-blue-300"
                >
                  {showAllAccounts ? "Show Less" : "Show All Accounts"}
                </button>
              ) : null}
            </>
          )}
        </div>
    </Modal>
  )

  const feedbackModal = <FeedbackModal {...feedbackModalProps} />
  const deleteAttachedReelModal = (
    <ConfirmModal {...deleteAttachedReelConfirmProps} />
  )
  const communitySharePreviewModal = (
    <CommunitySharePreviewModal
      open={communityPreviewOpen}
      onClose={() => setCommunityPreviewOpen(false)}
      onPostTrade={() => void handleSubmit()}
      submitting={submitting}
      postTradeDisabled={invalidFutureDate}
      title={isPublic ? "Preview Post" : "Preview Trade"}
      subtitle={
        isPublic
          ? "This is how your trade will appear in the feed."
          : "Review your trade before saving."
      }
      postTradeLabel={
        isEditMode ? "Save changes" : isPublic ? "Post Trade" : "Save Trade"
      }
      submittingLabel={isPublic ? "Post Trade" : "Save Trade"}
      post={communityPreviewPost}
      user={communityPreviewUser}
    />
  )

  if (showAsModal) {
    return (
      <>
        <ScrollableModalShell
          open
          onClose={() => onClose?.()}
          ariaLabel="Edit Trade"
          showCloseButton={false}
          overlayClassName="z-[10050] bg-black/70 py-3 backdrop-blur-sm md:py-4"
          backdropClassName="bg-transparent"
          panelClassName="!h-[min(92dvh,calc(100dvh-1.5rem))] !max-h-[min(92dvh,calc(100dvh-1.5rem))] !w-[min(95vw,90rem)] !max-w-[95vw] rounded-xl bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46]"
          headerClassName="border-white/10 px-4 py-3 md:px-6 lg:px-7"
          bodyClassName="px-4 pt-3 pb-4 md:px-6 md:pt-4 md:pb-5 lg:px-7"
          header={
            <div className="flex items-center justify-between gap-4">
              <h2
                id="input-trade-modal-title"
                className="text-xl font-semibold text-blue-300"
              >
                Edit Trade
              </h2>
              <ModalCloseButton onClick={() => onClose?.()} />
            </div>
          }
        >
          {formBody}
        </ScrollableModalShell>
        {settingsModal}
        {feedbackModal}
        {deleteAttachedReelModal}
        {communitySharePreviewModal}
        <ImageCropModal
          open={imageCrop.cropSourceFile != null}
          file={imageCrop.cropSourceFile}
          preset={CONTENT_IMAGE_CROP_PRESET}
          onCancel={handleCropCancel}
          onSave={handleCropSave}
        />
        <CreateAccountModal
          open={showCreateModal}
          onClose={() => setShowCreateModal(false)}
          onSave={handleCreateAccountSave}
        />

        {showAccountWarning && (
          <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50">
            <div className="bg-[#0f172a] border border-white/10 rounded-xl p-6 w-[320px] text-center">
              <h2 className="text-white text-lg font-semibold mb-2">Select an Account</h2>

              <p className="text-gray-400 text-sm mb-4">
                Choose or create an account before logging a trade.
              </p>

              <button
                type="button"
                onClick={() => setShowAccountWarning(false)}
                className="px-4 py-2 rounded bg-blue-500 hover:bg-blue-600 text-white w-full"
              >
                Got it
              </button>
            </div>
          </div>
        )}
      </>
    )
  }

  return (
    <>
      {formBody}
      {settingsModal}
      {feedbackModal}
      {deleteAttachedReelModal}
      {communitySharePreviewModal}
      <ImageCropModal
        open={imageCrop.cropSourceFile != null}
        file={imageCrop.cropSourceFile}
        preset={CONTENT_IMAGE_CROP_PRESET}
        onCancel={handleCropCancel}
        onSave={handleCropSave}
      />

      <CreateAccountModal
        open={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSave={handleCreateAccountSave}
      />

      {showAccountWarning && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50">
          <div className="bg-[#0f172a] border border-white/10 rounded-xl p-6 w-[320px] text-center">
            <h2 className="text-white text-lg font-semibold mb-2">Select an Account</h2>

            <p className="text-gray-400 text-sm mb-4">
              Choose or create an account before logging a trade.
            </p>

            <button
              type="button"
              onClick={() => setShowAccountWarning(false)}
              className="px-4 py-2 rounded bg-blue-500 hover:bg-blue-600 text-white w-full"
            >
              Got it
            </button>
          </div>
        </div>
      )}
    </>
  )
}
