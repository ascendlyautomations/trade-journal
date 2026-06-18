"use client"

import { useState, useRef, useEffect, useCallback, useMemo } from "react"
import { supabase } from "@/lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { ensureManualUserAccountRegistered } from "@/lib/ensureManualUserAccount"
import { isProActive } from "@/lib/subscription"
import { insertCsvTradesWithAccount } from "@/lib/insertCsvTradesWithAccount"
import { hasReachedRowLimit, last24hIso, assessFreePlanTradeUpload, FREE_PLAN_TRADES_PER_24H } from "@/lib/freePlanLimits"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import {
  mirrorAccountSettingsHasUsedCsvImport,
  mirrorAccountSettingsLockedAccount,
} from "@/lib/profileSplitMirrorWrites"
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
import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import TradeAccountPicker from "@/app/components/TradeAccountPicker"
import CsvImportUnsupportedBanner from "@/app/components/CsvImportUnsupportedBanner"
import CsvImportDiagnosticsPanel from "@/app/components/CsvImportDiagnosticsPanel"
import type { CsvImportDiagnostics } from "@/lib/csvImportDiagnostics"
import { buildCommunitySharePreviewPost } from "@/lib/buildCommunitySharePreviewPost"
import CommunitySharePreviewModal from "@/app/components/CommunitySharePreviewModal"
import { postImageSrc } from "@/app/components/feed/feedPostHelpers"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

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
}

function formatAccountSize(size: any) {
  if (!size) return ""
  const num = Number(size)

  if (!isNaN(num) && num >= 1000) {
    return `${num / 1000}K`
  }

  return size
}

export default function InputTradeForm({
  existingTrade,
  onSave,
  onClose,
  forceMarkReviewedOnSave = false,
  onUploadCsvClick,
  onReviewCsvClick,
  reviewCount = 0,
  csvLoading = false,
  parsedTrades = [],
  csvUnrecognized = false,
  csvBrokerHint = null,
  csvDiagnostics = null,
  onParsedTradesClear,
}: InputTradeFormProps) {
  const isEditMode = Boolean(existingTrade?.id)
  const showAsModal = isEditMode && Boolean(onClose)

  const [accounts, setAccounts] = useState<any[]>([])
  const [selectedAccount, setSelectedAccount] = useState<any | null>(null)
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

  function releaseSubmit() {
    submittingRef.current = false
    setSubmitting(false)
  }

  const [inputSettings, setInputSettings] = useState({
    showRR: true,
    showPoints: true,
    showContracts: true,
    showEntryExit: true,
    showPsychology: true,
    showMistakes: true,
    showContext: true,
    showNotes: true,
  })

  const [emotion, setEmotion] = useState("")
  const [followedPlan, setFollowedPlan] = useState(false)
  const [mistakeType, setMistakeType] = useState("")
  const [market, setMarket] = useState("")
  const [newsEvent, setNewsEvent] = useState(false)
  const [timeframe, setTimeframe] = useState("")

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

  function formatCurrency(value: string) {
    if (!value) return ""

    const num = Number(value.replace(/,/g, ""))
    if (isNaN(num)) return ""

    return num.toLocaleString("en-US", {
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    })
  }

  function handleNumericInput(
    value: string,
    setter: (val: string) => void,
    options?: {
      allowDecimal?: boolean
      allowNegative?: boolean
    }
  ) {
    let cleaned = value.replace(/,/g, "")
    const { allowDecimal = false, allowNegative = false } = options || {}
    // 🚫 BLOCK MULTIPLE DECIMALS
    if (allowDecimal) {
      const decimalCount = (cleaned.match(/\./g) || []).length
      if (decimalCount > 1) {
        setDecimalError("Only one decimal point allowed")
        return
      } else {
        setDecimalError("")
      }
    }

    let regex

    if (allowDecimal && allowNegative) {
      regex = /^-?\d*(\.\d*)?$/
    } else if (allowDecimal) {
      regex = /^\d*(\.\d*)?$/
    } else if (allowNegative) {
      regex = /^-?\d*$/
    } else {
      regex = /^\d*$/
    }

    // ALLOW INTERMEDIATE STATES
    if (
      cleaned === "" ||
      cleaned === "-" ||
      cleaned === "." ||
      cleaned === "-." ||
      cleaned.endsWith(".")
    ) {
      setter(cleaned)
      return
    }

    if (!regex.test(cleaned)) return

    setter(cleaned)
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

  const [strategy, setStrategy] = useState("")

  const [entryPrice, setEntryPrice] = useState("")
  const [exitPrice, setExitPrice] = useState("")
  const [contracts, setContracts] = useState("")
  const [entryTime, setEntryTime] = useState("")
  const [exitTime, setExitTime] = useState("")
  const fileInputRef = useRef<HTMLInputElement>(null)
  const entryDateRef = useRef<HTMLInputElement>(null)
  const exitDateRef = useRef<HTMLInputElement>(null)

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
  const [authUserId, setAuthUserId] = useState<string | null>(null)
  const [accountFieldsLocked, setAccountFieldsLocked] = useState(false)
  const [communityPreviewOpen, setCommunityPreviewOpen] = useState(false)
  const [screenshotPreviewUrl, setScreenshotPreviewUrl] = useState<string | null>(
    null
  )

  const applyPlanAndAccountLock = useCallback(async (userId: string | null) => {
    if (!userId) {
      setPlanProfile(null)
      setAuthUserId(null)
      setAccountFieldsLocked(false)
      return
    }
    setAuthUserId(userId)
    const { data: prof } = await supabase
      .from("profiles")
      .select(
        "is_pro, subscription_status, locked_account_type, locked_account_size, locked_account_name, locked_account_number, username, avatar_url"
      )
      .eq("id", userId)
      .maybeSingle()
    setPlanProfile(prof ?? null)
    if (isProActive(prof)) {
      setAccountFieldsLocked(false)
      return
    }
    const { data: rows } = await supabase
      .from("user_accounts")
      .select("account_type")
      .eq("user_id", userId)
    const manualCount = (rows ?? []).filter(
      (t) =>
        String(t.account_type ?? "").toLowerCase().trim() !== "imported"
    ).length
    setAccountFieldsLocked(manualCount >= 1)
  }, [])

  const fetchAccountsForUser = useCallback(async (userId: string) => {
    const { data, error } = await supabase
      .from("accounts")
      .select("*")
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
      note: acc.note ?? "",
    }))

    setAccounts(formatted)
  }, [])

  const refreshPlanAndAccountLock = useCallback(async () => {
    if (authUserId) {
      await applyPlanAndAccountLock(authUserId)
      return
    }
    const {
      data: { user },
    } = await supabase.auth.getUser()
    await applyPlanAndAccountLock(user?.id ?? null)
  }, [applyPlanAndAccountLock, authUserId])

  useEffect(() => {
    let cancelled = false

    void (async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      const userId = user?.id ?? null
      if (cancelled) return

      await Promise.all([
        applyPlanAndAccountLock(userId),
        userId ? fetchAccountsForUser(userId) : Promise.resolve(),
      ])
    })()

    return () => {
      cancelled = true
    }
  }, [applyPlanAndAccountLock, fetchAccountsForUser])

  useEffect(() => {
    if (!authUserId) return
    void applyPlanAndAccountLock(authUserId)
  }, [existingTrade?.id, authUserId, applyPlanAndAccountLock])

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
        persistentError("Save Failed", handleSupabaseError(error))
      )
      return false
    }
    return true
  }, [])

  useEffect(() => {
    if (!showSettings || !authUserId) return
    void fetchAccountsForUser(authUserId)
  }, [showSettings, authUserId, fetchAccountsForUser])

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
    () => accounts.filter((a) => a.is_active !== false),
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
    if (selectedAccount.is_active === false) {
      setSelectedAccount(null)
    }
  }, [selectedAccount])

  const effectiveModeLower = String(
    selectedAccount?.mode ??
      (existingTrade?.mode ?? existingTrade?.account_type ?? "")
  ).toLowerCase()

  const accountInputsDisabled =
    accountFieldsLocked &&
    effectiveModeLower !== "backtest" &&
    !isProActive(planProfile)
  const isPro = isProActive(planProfile)
  const isLocked = !isPro && Boolean(planProfile?.locked_account_type)
  const lockedMode = modeLabelFromDb(planProfile?.locked_account_type)
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
    setSessionManuallySet(false)
    setConfluences(t.top_confluences ?? t.notes ?? "")
    setPublicDescription(t.public_description ?? "")
    setPostToFeed(false)
    setIsPublic(Boolean(t.is_public))
    setImage(null)
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
    setTimeframe(t.timeframe ?? "")
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
  }, [existingTrade])

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
    setEntryPrice("")
    setExitPrice("")
    setContracts("")
    setEntryTime("")
    setExitTime("")
    setSelectedAccount(null)
    setConfidence("")
    setEmotion("")
    setFollowedPlan(false)
    setMistakeType("")
    setMarket("")
    setNewsEvent(false)
    setTimeframe("")
    setPsychologyNotes("")
    setTradeType("")
    const today = getESTDate()
    setEntryDate(today)
    setExitDate(today)
    setPostToFeed(false)
    setStrategy("")
  }

  async function handleSubmit() {
    if (submittingRef.current || submitting) return

    if (!selectedAccount) {
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

    const acct = selectedAccount

    submittingRef.current = true
    setSubmitting(true)

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user?.id) {
      showPopup(
        persistentError("Sign In Required", "Please log in to save your trade.")
      )
      releaseSubmit()
      return
    }

    const sinceIso = last24hIso()

    const { data: profileRow } = await supabase
      .from("profiles")
      .select(
        "is_pro, subscription_status, locked_account_type, locked_account_size, locked_account_name, locked_account_number"
      )
      .eq("id", user.id)
      .maybeSingle()
    const userIsPro = isProActive(profileRow)

    if (!isEditMode && !userIsPro) {
      const tradeLimitReached = await hasReachedRowLimit(supabase as any, {
        table: "trades",
        userColumn: "user_id",
        userId: user.id,
        limit: FREE_PLAN_TRADES_PER_24H,
        sinceIso,
      })
      if (tradeLimitReached) {
        showPopup(feedbackPresets.tradeLimitReached())
        releaseSubmit()
        return
      }
    }

    if (!userIsPro && isPublic) {
      const publicTradeLimitReached = await hasReachedRowLimit(supabase as any, {
        table: "trades",
        userColumn: "user_id",
        userId: user.id,
        limit: 1,
        sinceIso,
        extraEquals: { is_public: true },
      })
      if (publicTradeLimitReached) {
        setIsPublic(false)
        showPopup(feedbackPresets.publicTradeLimit())
        releaseSubmit()
        return
      }
    }

    let screenshotUrl: string | null = null

    if (image) {
      let uploadFile: File = image
      if (image.type?.startsWith("image/")) {
        uploadFile = await compressImage(image)
      }
      const fileName = `${user.id}/${Date.now()}-${uploadFile.name}`
      const { error: upErr } = await supabase.storage
        .from("screenshots")
        .upload(fileName, uploadFile)
      if (upErr) {
        console.error("Upload error:", upErr)
      } else {
        screenshotUrl = fileName
      }
    }

    const parsedPnl = parseFloat(pnl) || 0
    const parsedRR = parseFloat(rr) || 0
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

    const modeLower = String(acct.mode ?? "live").trim().toLowerCase()

    let rowAcct = {
      type: modeLower,
      name: String(acct.name ?? "").trim() || null,
      size: String(acct.size ?? "").trim() || null,
      id: acct.id != null ? String(acct.id).trim() || null : null,
      account_number:
        String(acct.account_number ?? "").trim() || null,
      mode: String(acct.mode ?? "live"),
      category: acct.category ?? null,
    }

    if (!userIsPro && modeLower !== "backtest" && modeLower !== "imported") {
      const lockedType = String(profileRow?.locked_account_type ?? "").trim().toLowerCase()
      const lockedSize = String(profileRow?.locked_account_size ?? "").trim()
      const lockedName = String(profileRow?.locked_account_name ?? "").trim()
      const lockedNumber = String(profileRow?.locked_account_number ?? "").trim()
      const incomingType = String(modeLower).trim().toLowerCase()
      const incomingSize = String(rowAcct.size ?? "").trim()
      const incomingName = String(rowAcct.name ?? "").trim()
      const incomingNumber = String(rowAcct.account_number ?? "").trim()

      if (!lockedType) {
        const lockedAccountPatch = {
          locked_account_type: incomingType || null,
          locked_account_size: incomingSize || null,
          locked_account_name: incomingName || null,
          locked_account_number: incomingNumber || null,
        }
        const { error: lockErr } = await supabase
          .from("profiles")
          .update(lockedAccountPatch)
          .eq("id", user.id)
        if (lockErr) {
          console.error("locked account update:", lockErr)
          showPopup(
            persistentError("Save Failed", handleSupabaseError(lockErr))
          )
          releaseSubmit()
          return
        }
        const { error: mirrorErr } = await mirrorAccountSettingsLockedAccount(
          supabase,
          user.id,
          lockedAccountPatch
        )
        if (mirrorErr) {
          console.error("mirror account_settings locked_account_*:", mirrorErr)
        }
      } else {
        const { data: lockedAccountMatch } = await supabase
          .from("accounts")
          .select("id")
          .eq("user_id", user.id)
          .eq("account_number", lockedNumber)
          .maybeSingle()

        const lockedAccountId =
          lockedAccountMatch?.id != null
            ? String(lockedAccountMatch.id).trim()
            : null

        rowAcct = {
          type: lockedType || modeLower,
          size: lockedSize || null,
          name: lockedName || null,
          id: lockedAccountId,
          account_number: lockedNumber || null,
          mode: lockedType || modeLower,
          category: rowAcct.category,
        }

        if (
          incomingType !== lockedType ||
          incomingSize !== lockedSize ||
          incomingName !== lockedName ||
          incomingNumber !== lockedNumber
        ) {
          showPopup(feedbackPresets.accountLocked())
          setSelectedAccount({
            name: lockedName,
            size: lockedSize,
            id: lockedAccountId ?? "",
            account_number: lockedNumber,
            mode: lockedType || modeLower,
            category: rowAcct.category ?? undefined,
          })
        }
      }
    }

    const skipAccountRegistry =
      rowAcct.type === "backtest" || rowAcct.type === "imported"

    const ensured = await ensureManualUserAccountRegistered(supabase, {
      userId: user.id,
      accountName: rowAcct.name ?? "",
      tradeAccountType: rowAcct.type,
      isPro: userIsPro,
      skipRegistry: skipAccountRegistry,
    })

    if (!ensured.ok) {
      showPopup(
        persistentError(
          "Save Failed",
          "Could not complete save. Please try again."
        )
      )
      releaseSubmit()
      return
    }

    if (isEditMode && existingTrade?.id) {
      const prevImg = existingTrade.image_url ?? null
      const imageUrlOut = screenshotUrl ?? prevImg

      const entryVal = entryPrice.trim() === "" ? null : Number(entryPrice)
      const exitVal = exitPrice.trim() === "" ? null : Number(exitPrice)

      const updateRow: Record<string, unknown> = {
        ticker: ticker || null,
        direction,
        pnl: Number.isFinite(parsedPnl) ? parsedPnl : 0,
        rr: Number.isFinite(parsedRR) ? parsedRR : 0,
        points: Number.isFinite(parsedPoints) ? parsedPoints : 0,
        contracts: contractsNum,
        session: sessionToSave,
        top_confluences: confluences || null,
        public_description: publicDescription ?? "",
        image_url: imageUrlOut,
        account_name: rowAcct.name,
        account_type: rowAcct.type,
        mode: rowAcct.mode,
        account_category: rowAcct.category,
        strategy:
          rowAcct.type === "backtest" && String(strategy).trim() !== ""
            ? String(strategy).trim()
            : null,
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
        timeframe: timeframe || null,
        is_public: isPublic,
      }
      const importedUnreviewed =
        ["imported"].includes(String(existingTrade.account_type ?? "").toLowerCase()) &&
        existingTrade.reviewed === false
      if (forceMarkReviewedOnSave || importedUnreviewed) {
        updateRow.reviewed = true
      }

      const { error } = await supabase
        .from("trades")
        .update(updateRow)
        .eq("id", existingTrade.id)

      if (error) {
        console.error("UPDATE ERROR:", error)
        showPopup(
        persistentError("Save Failed", handleSupabaseError(error))
      )
        releaseSubmit()
        return
      }

      if (isPublic) {
        if (!userIsPro) {
          const { data: existingPost } = await supabase
            .from("posts")
            .select("id")
            .eq("trade_id", existingTrade.id)
            .maybeSingle()

          if (!existingPost) {
            const postLimitReached = await hasReachedRowLimit(supabase as any, {
              table: "posts",
              userColumn: "user_id",
              userId: user.id,
              limit: 1,
              sinceIso,
            })
            if (postLimitReached) {
              showPopup(feedbackPresets.postLimit())
              releaseSubmit()
              return
            }
          }
        }

        const { error: postErr } = await supabase.from("posts").upsert(
          {
            trade_id: existingTrade.id,
            user_id: user.id,
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
            persistentError("Post Failed", handleSupabaseError(postErr))
          )
          releaseSubmit()
          return
        }
      } else {
        const { error: delErr } = await supabase
          .from("posts")
          .delete()
          .eq("trade_id", existingTrade.id)
        if (delErr) console.error("posts delete:", delErr)
      }

      void refreshPlanAndAccountLock()
      setCommunityPreviewOpen(false)
      onSave?.()
      onClose?.()
      showPopup(feedbackPresets.tradeSaveSuccess())
      notifyGettingStartedChecklistMaybeCompleted()
      releaseSubmit()
      return
    }

    const now = new Date()

    console.log("FINAL SAVED DATE:", now.toISOString())

    const parsedTrade = {
      pnl: pnl ? Number(pnl) : null,
      entry_price: entryPrice ? Number(entryPrice) : null,
      exit_price: exitPrice ? Number(exitPrice) : null,
      contracts: contracts ? Number(contracts) : null,
      points: points ? Number(points) : null,
      rr: rr ? Number(rr) : null,
    }

    const selectedDate = entryDate
    console.log("Saving trade_date:", selectedDate)

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
      account_name: rowAcct.name,
      account_size: rowAcct.size,
      account_id: rowAcct.id,
      mode: rowAcct.mode,
      account_category: rowAcct.category ?? null,
      account_type: rowAcct.type,
      strategy: strategy || null,
      user_id: user.id,
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
      timeframe: timeframe || null,
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
        persistentError("Save Failed", handleSupabaseError(error))
      )
      releaseSubmit()
      return
    }

    if (isPublic && newTradeData) {
      if (!userIsPro) {
        const postLimitReached = await hasReachedRowLimit(supabase as any, {
          table: "posts",
          userColumn: "user_id",
          userId: user.id,
          limit: 1,
          sinceIso,
        })
        if (postLimitReached) {
          showPopup(feedbackPresets.postLimit())
          releaseSubmit()
          return
        }
      }

      const { error: postError } = await supabase.from("posts").insert([
        {
          user_id: user.id,
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
          persistentError("Post Failed", handleSupabaseError(postError))
        )
        releaseSubmit()
        return
      }

      void refreshPlanAndAccountLock()
      setCommunityPreviewOpen(false)
      resetCreateForm()
      showPopup(feedbackPresets.postPublished())
      notifyGettingStartedChecklistMaybeCompleted()
      releaseSubmit()
      return
    }

    void refreshPlanAndAccountLock()
    setCommunityPreviewOpen(false)
    resetCreateForm()
    showPopup(feedbackPresets.tradeSaveSuccess())
    notifyGettingStartedChecklistMaybeCompleted()
    releaseSubmit()
  }

  async function handlePublicToggle() {
    const nextIsPublic = !isPublic
    if (!nextIsPublic) {
      setIsPublic(false)
      return
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user?.id) {
      setIsPublic(nextIsPublic)
      return
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("is_pro, subscription_status")
      .eq("id", user.id)
      .maybeSingle()

    if (!isProActive(profile)) {
      const publicTradeLimitReached = await hasReachedRowLimit(supabase as any, {
        table: "trades",
        userColumn: "user_id",
        userId: user.id,
        limit: 1,
        sinceIso: last24hIso(),
        extraEquals: { is_public: true },
      })
      if (publicTradeLimitReached) {
        showPopup(feedbackPresets.publicTradeLimit())
        setIsPublic(false)
        return
      }
    }

    setIsPublic(true)
  }

  function handleDrop(e: React.DragEvent<HTMLDivElement>) {
    e.preventDefault()
    const file = e.dataTransfer.files[0]
    if (file) setImage(file)
  }

  function handleClickUpload() {
    fileInputRef.current?.click()
  }

  async function handleUploadCsvGuardClick() {
    if (!onUploadCsvClick) return

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user?.id) {
      showPopup(
        persistentError("Sign In Required", "Please log in to save your trade.")
      )
      return
    }

    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("is_pro, has_used_csv_import")
      .eq("id", user.id)
      .single()

    if (profileErr || !profile) {
      console.error("Profile fetch failed:", profileErr)
      showPopup(
        persistentError(
          "Could Not Verify Account",
          profileErr ? handleSupabaseError(profileErr) : "Something went wrong"
        )
      )
      return
    }

    console.log("CSV BLOCK CHECK:", profile)

    if (!profile.is_pro && profile.has_used_csv_import) {
      showPopup(feedbackPresets.csvSubscriptionLimit())
      return
    }

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
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user?.id) {
        showPopup(feedbackPresets.importFailed("Please log in first."))
        return
      }

      const { data: profile, error: profileErr } = await supabase
        .from("profiles")
        .select("is_pro, has_used_csv_import")
        .eq("id", user.id)
        .single()
      if (profileErr || !profile) {
        console.error("Profile fetch failed:", profileErr)
        showPopup(feedbackPresets.importFailed("Could not verify account. Try again."))
        return
      }
      if (!profile.is_pro && profile.has_used_csv_import) {
        showPopup(feedbackPresets.csvSubscriptionLimit())
        return
      }

      let uploadCheck
      try {
        uploadCheck = await assessFreePlanTradeUpload(
          supabase,
          user.id,
          parsedTrades.length
        )
      } catch {
        showPopup(feedbackPresets.importVerifyFailed())
        return
      }

      if (!uploadCheck.allowed) {
        showPopup(
          feedbackPresets.csvImportLimitExceeded(
            parsedTrades.length,
            uploadCheck.remaining
          )
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

      if (!profile.is_pro) {
        const { error: flagErr } = await supabase
          .from("profiles")
          .update({ has_used_csv_import: true })
          .eq("id", user.id)
        if (flagErr) {
          console.error("markProfileCsvImportUsed:", flagErr)
        } else {
          const { error: mirrorErr } = await mirrorAccountSettingsHasUsedCsvImport(
            supabase,
            user.id,
            true
          )
          if (mirrorErr) {
            console.error("mirror account_settings.has_used_csv_import:", mirrorErr)
          }
        }
      }

      onParsedTradesClear?.()
      setSelectedAccount(null)
    } catch (err) {
      console.error(err)
      showPopup(
        persistentError("Import Failed", handleSupabaseError(err))
      )
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
        persistentError("Save Failed", handleSupabaseError(error))
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
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) return

    const { data: profile } = await supabase
      .from("profiles")
      .select("is_pro, subscription_status")
      .eq("id", user.id)
      .maybeSingle()
    const userIsPro = isProActive(profile)

    if (!userIsPro) {
      const { data: existingAccounts, error: countErr } = await supabase
        .from("accounts")
        .select("id")
        .eq("user_id", user.id)

      if (countErr) {
        console.error(countErr)
        showPopup(
          persistentError("Account Check Failed", handleSupabaseError(countErr))
        )
        return
      }

      if ((existingAccounts || []).length >= 1) {
        showPopup(feedbackPresets.accountLimit())
        return
      }
    }

    const { data, error } = await supabase
      .from("accounts")
      .insert([
        {
          user_id: user.id,
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
        },
      ])
      .select()
      .single()

    if (error) {
      console.error(error)
      showPopup(
        persistentError("Save Failed", handleSupabaseError(error))
      )
      return
    }

    if (!data) return

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
      note: data.note ?? "",
    })

    setShowCreateModal(false)
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

  const fieldLabelClass = "block text-xs text-gray-400 mb-1"

  const communityPreviewImageUrl = useMemo(() => {
    if (screenshotPreviewUrl) return screenshotPreviewUrl
    if (existingTrade?.image_url) {
      return postImageSrc(existingTrade.image_url)
    }
    return null
  }, [screenshotPreviewUrl, existingTrade?.image_url])

  const communityPreviewPost = useMemo(() => {
    if (!authUserId) return null
    const previewEntryTime = entryTime
      ? buildDateTime(entryDate, entryTime)
      : null
    const previewExitTime = exitTime
      ? buildDateTime(exitDate, exitTime)
      : null
    return buildCommunitySharePreviewPost({
      userId: authUserId,
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
    })
  }, [
    authUserId,
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
  ])

  const communityPreviewUser = useMemo(
    () => (authUserId ? { id: authUserId } : null),
    [authUserId]
  )

  const tradeTimeframeOptions = [
    "15s",
    "30s",
    "1m",
    "5m",
    "15m",
    "30m",
    "1hr",
    "4hr",
    "Custom",
  ] as const

  const formBody = (
    <>
      <div className="mb-4">
        <div className="flex flex-col gap-3 md:hidden">
          <div className="flex items-center gap-2">
            {onUploadCsvClick ? (
              <TradeAccountPicker
                className="min-w-0 flex-1"
                accounts={activeAccounts}
                selectedAccount={selectedAccount}
                onSelect={setSelectedAccount}
                onOpenCreate={() => setShowCreateModal(true)}
                disableCreate={accountFieldsLocked}
                showExternalCreateButton={false}
              />
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
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => void handleUploadCsvGuardClick()}
              disabled={!onUploadCsvClick || csvLoading}
              className="shrink-0 flex-1 px-3 py-2 text-sm rounded-lg bg-blue-500 disabled:opacity-60"
            >
              Upload CSV
            </button>
            <button
              type="button"
              onClick={onReviewCsvClick}
              disabled={!onReviewCsvClick}
              className="shrink-0 relative flex-1 px-3 py-2 text-sm rounded-lg bg-emerald-500 disabled:opacity-60"
            >
              Review CSV
              {reviewCount > 0 ? (
                <span className="absolute -top-1 -right-1 bg-red-500 text-white rounded-full text-[10px] px-1.5 py-0.5">
                  {reviewCount > 99 ? "99+" : reviewCount}
                </span>
              ) : null}
            </button>
          </div>
          {parsedTrades.length > 0 ? (
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
            {onUploadCsvClick ? (
              <TradeAccountPicker
                className="w-full max-w-[410px] shrink-0"
                accounts={activeAccounts}
                selectedAccount={selectedAccount}
                onSelect={setSelectedAccount}
                onOpenCreate={() => setShowCreateModal(true)}
                disableCreate={accountFieldsLocked}
                showExternalCreateButton={false}
              />
            ) : null}

            <button
              type="button"
              onClick={() => void handleUploadCsvGuardClick()}
              disabled={!onUploadCsvClick || csvLoading}
              className="shrink-0 px-4 py-2 text-sm rounded-lg bg-blue-500 disabled:opacity-60"
            >
              Upload CSV
            </button>

            {parsedTrades.length > 0 ? (
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
              className="shrink-0 relative px-4 py-2 text-sm rounded-lg bg-emerald-500 disabled:opacity-60"
            >
              Review CSV
              {reviewCount > 0 ? (
                <span className="absolute -top-1 -right-1 bg-red-500 text-white rounded-full text-[10px] px-1.5 py-0.5">
                  {reviewCount > 99 ? "99+" : reviewCount}
                </span>
              ) : null}
            </button>
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
        <CsvImportDiagnosticsPanel diagnostics={csvDiagnostics} className="mb-4" />
      ) : null}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="px-4 pb-4 pt-3 rounded-xl bg-[#0b1220]/60 border border-white/5">
          <h3 className="text-sm text-gray-400 mb-2">Trade</h3>
          <div className="space-y-2">
          <div>
            <label className={fieldLabelClass}>P&amp;L</label>
            <div className="relative w-full">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                $
              </span>

              <input
                type="text"
                tabIndex={1}
                value={
                  pnl === "-" ||
                  pnl === "." ||
                  pnl === "-." ||
                  pnl.endsWith(".")
                    ? pnl
                    : formatCurrency(pnl)
                }
                onChange={(e) =>
                  handleNumericInput(e.target.value, setPnl, {
                    allowDecimal: true,
                    allowNegative: true,
                  })
                }
                className="w-full pl-8 pr-3 py-2 rounded bg-[#0f172a] border border-white/10 focus:border-green-500 outline-none"
              />
            </div>
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
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
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
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
          <div>
            <label className={fieldLabelClass}>Direction</label>
            <select
              tabIndex={4}
              value={direction}
              onChange={(e) => setDirection(e.target.value)}
              className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
            >
              <option>Long</option>
              <option>Short</option>
            </select>
          </div>

          <div>
            <label className={fieldLabelClass}>Session</label>
            <select
              tabIndex={5}
              value={session}
              onChange={(e) => {
                setSessionManuallySet(true)
                setSession(e.target.value)
              }}
              className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
            >
              <option value="NY">NY</option>
              <option value="London">London</option>
              <option value="Asia">Asia</option>
              <option value="After">After</option>
            </select>
          </div>
          </div>

          {(inputSettings.showRR || inputSettings.showPoints) && (
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
              {inputSettings.showRR && (
                <div>
                  <label className={fieldLabelClass}>Risk Reward</label>
                  <input
                    placeholder="e.g. 2.5"
                    type="text"
                    tabIndex={6}
                    value={rr}
                    onChange={(e) =>
                      handleNumericInput(e.target.value, setRR, { allowDecimal: true })
                    }
                    className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
                  />
                </div>
              )}
              {inputSettings.showPoints && (
                <div>
                  <label className={fieldLabelClass}>Points</label>
                  <input
                    placeholder="e.g. 15.5"
                    type="text"
                    tabIndex={7}
                    value={
                      points === "-" ||
                      points === "." ||
                      points === "-." ||
                      points.endsWith(".")
                        ? points
                        : formatCurrency(points)
                    }
                    onChange={(e) =>
                      handleNumericInput(e.target.value, setPoints, {
                        allowDecimal: true,
                        allowNegative: true,
                      })
                    }
                    className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
                  />
                </div>
              )}
            </div>
          )}

          {inputSettings.showContracts && (
            <div>
              <label className={fieldLabelClass}>Contracts</label>
              <input
                placeholder="e.g. 4"
                type="text"
                tabIndex={8}
                value={formatWithCommas(contracts)}
                onChange={(e) => handleNumericInput(e.target.value, setContracts)}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
              />
            </div>
          )}

          {inputSettings.showNotes && (
            <div>
              <label className={fieldLabelClass}>Top Confluences</label>
              <textarea
                placeholder="What confirmations led to this trade?"
                tabIndex={9}
                value={confluences}
                onChange={(e) => setConfluences(e.target.value)}
                className="w-full p-2 lg:p-2.5 h-20 lg:h-24 rounded bg-[#0f172a] border border-white/10"
              />
            </div>
          )}

          </div>
        </div>

        <div className="px-4 pb-4 pt-3 rounded-xl bg-[#0b1220]/60 border border-white/5">
          <h3 className="text-sm text-gray-400 mb-2">Execution</h3>
          <div className="space-y-2">
          {inputSettings.showEntryExit && (
            <div className="space-y-2 mb-4">
              <div>
                <label className={fieldLabelClass}>Entry Price</label>
                <div className="relative w-full">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                    $
                  </span>

                  <input
                    type="text"
                    tabIndex={inputSettings.showNotes ? 10 : 9}
                    value={
                      entryPrice === "-" ||
                      entryPrice === "." ||
                      entryPrice === "-." ||
                      entryPrice.endsWith(".")
                        ? entryPrice
                        : formatCurrency(entryPrice)
                    }
                    onChange={(e) =>
                      handleNumericInput(e.target.value, setEntryPrice, {
                        allowDecimal: true,
                      })
                    }
                    className="w-full pl-8 pr-3 py-2 rounded bg-[#0f172a] border border-white/10 focus:border-green-500 outline-none"
                  />
                </div>
              </div>
              <div>
                <label className={fieldLabelClass}>Exit Price</label>
                <div className="relative w-full">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                    $
                  </span>

                  <input
                    type="text"
                    tabIndex={inputSettings.showNotes ? 11 : 10}
                    value={
                      exitPrice === "-" ||
                      exitPrice === "." ||
                      exitPrice === "-." ||
                      exitPrice.endsWith(".")
                        ? exitPrice
                        : formatCurrency(exitPrice)
                    }
                    onChange={(e) =>
                      handleNumericInput(e.target.value, setExitPrice, {
                        allowDecimal: true,
                      })
                    }
                    className="w-full pl-8 pr-3 py-2 rounded bg-[#0f172a] border border-white/10 focus:border-green-500 outline-none"
                  />
                </div>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
                <div>
                  <label className={fieldLabelClass}>Entry Date</label>
                  <div
                    className="relative w-full cursor-pointer"
                    onClick={() => entryDateRef.current?.showPicker?.()}
                  >
                    <input
                      ref={entryDateRef}
                      id="entry-date"
                      type="date"
                      tabIndex={inputSettings.showNotes ? 12 : 11}
                      value={entryDate}
                      onChange={(e) => handleEntryDateChange(e.target.value)}
                      className="w-full p-2 pr-10 rounded bg-[#0f172a] border border-white/10 text-white"
                    />
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 text-white pointer-events-none">
                      📅
                    </div>
                  </div>
                </div>
                <div>
                  <label className={fieldLabelClass}>Entry Time</label>
                  <div
                    className="relative w-full cursor-pointer"
                    onClick={() =>
                      (
                        document.getElementById("entry-time") as HTMLInputElement | null
                      )?.showPicker?.()
                    }
                  >
                    <input
                      id="entry-time"
                      type="time"
                      tabIndex={inputSettings.showNotes ? 13 : 12}
                      value={entryTime}
                      onChange={(e) => setEntryTime(e.target.value)}
                      className="w-full p-2 pr-10 rounded bg-[#0f172a] border border-white/10 text-white"
                    />
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 text-white pointer-events-none">
                      🕒
                    </div>
                  </div>
                </div>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
                <div>
                  <label className={fieldLabelClass}>Exit Date</label>
                  <div
                    className="relative w-full cursor-pointer"
                    onClick={() => exitDateRef.current?.showPicker?.()}
                  >
                    <input
                      ref={exitDateRef}
                      id="exit-date"
                      type="date"
                      tabIndex={inputSettings.showNotes ? 14 : 13}
                      value={exitDate}
                      onChange={(e) => handleExitDateChange(e.target.value)}
                      className="w-full p-2 pr-10 rounded bg-[#0f172a] border border-white/10 text-white"
                    />
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 text-white pointer-events-none">
                      📅
                    </div>
                  </div>
                </div>
                <div>
                  <label className={fieldLabelClass}>Exit Time</label>
                  <div
                    className="relative w-full cursor-pointer"
                    onClick={() =>
                      (
                        document.getElementById("exit-time") as HTMLInputElement | null
                      )?.showPicker?.()
                    }
                  >
                    <input
                      id="exit-time"
                      type="time"
                      tabIndex={inputSettings.showNotes ? 15 : 14}
                      value={exitTime}
                      onChange={(e) => setExitTime(e.target.value)}
                      className="w-full p-2 pr-10 rounded bg-[#0f172a] border border-white/10 text-white"
                    />
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 text-white pointer-events-none">
                      🕒
                    </div>
                  </div>
                </div>
              </div>
              {duration && (
                <p className="text-xs text-gray-400">
                  Duration: {duration}
                </p>
              )}
              {invalidTimeRange && (
                <p className="text-xs text-red-400">
                  Exit date and time must be after entry date and time
                </p>
              )}
            </div>
          )}

          <div className="mt-0">
            <label className={fieldLabelClass}>Public Description</label>
            <textarea
              tabIndex={
                inputSettings.showEntryExit
                  ? inputSettings.showNotes
                    ? 16
                    : 15
                  : inputSettings.showNotes
                    ? 10
                    : 9
              }
              value={publicDescription}
              onChange={(e) => setPublicDescription(e.target.value)}
              placeholder="Insert public thoughts..."
              className="w-full p-2 lg:p-2.5 rounded-lg bg-[#0f172a] text-white border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[80px] lg:min-h-[96px]"
            />
          </div>

          <div className="flex items-center justify-between mt-2 p-3 rounded-xl bg-white/5 border border-white/10">
            <div>
              <p className="text-sm font-medium text-white">Share to Community</p>
              <p className="text-xs text-white/50">
                Make this trade visible on the public feed
              </p>
            </div>
            <button
              type="button"
              tabIndex={
                inputSettings.showEntryExit
                  ? inputSettings.showNotes
                    ? 17
                    : 16
                  : inputSettings.showNotes
                    ? 11
                    : 10
              }
              onClick={() => void handlePublicToggle()}
              className={`
                px-4 py-1.5 rounded-full text-xs font-medium
                transition
                ${
                  isPublic
                    ? "bg-green-500/20 text-green-400 border border-green-400/30"
                    : "bg-white/10 text-white/50 border border-white/10"
                }
              `}
            >
              {isPublic ? "Public" : "Private"}
            </button>
          </div>

          {isPublic ? (
            <button
              type="button"
              disabled={!communityPreviewPost}
              onClick={() => setCommunityPreviewOpen(true)}
              className="mt-2 w-full text-left text-sm font-medium text-emerald-400 transition hover:text-emerald-300 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Preview Community Post
            </button>
          ) : null}
          </div>
        </div>

        <div className="px-4 pb-4 pt-3 rounded-xl bg-[#0b1220]/60 border border-white/5">
          <h3 className="text-sm text-gray-400 mb-2">Psychology</h3>
          <div className="space-y-2">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
          <div>
            <label className={fieldLabelClass}>Confidence</label>
            <select
              tabIndex={
                inputSettings.showEntryExit
                  ? inputSettings.showNotes
                    ? 18
                    : 17
                  : inputSettings.showNotes
                    ? 12
                    : 11
              }
              value={confidence}
              onChange={(e) => setConfidence(e.target.value)}
              className="w-full p-2 lg:p-2.5 bg-[#0f172a] border border-white/10 rounded"
            >
              <option value="">Confidence Level</option>
              <option value="1">1 - Bad</option>
              <option value="2">2</option>
              <option value="3">3</option>
              <option value="4">4</option>
              <option value="5">5 - Good</option>
            </select>
          </div>
          <div>
            <label className={fieldLabelClass}>Timeframe</label>
            <select
              tabIndex={
                inputSettings.showEntryExit
                  ? inputSettings.showNotes
                    ? 21
                    : 20
                  : inputSettings.showNotes
                    ? 15
                    : 14
              }
              value={timeframe}
              onChange={(e) => setTimeframe(e.target.value)}
              className="w-full p-2 lg:p-2.5 bg-[#0f172a] border border-white/10 rounded"
            >
              <option value="">Select timeframe</option>
              {tradeTimeframeOptions.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
              {timeframe &&
                !(tradeTimeframeOptions as readonly string[]).includes(timeframe) && (
                  <option value={timeframe}>{timeframe}</option>
                )}
            </select>
          </div>
          </div>
          <div>
            <label className={fieldLabelClass}>Emotion</label>
            <select
              tabIndex={
                inputSettings.showEntryExit
                  ? inputSettings.showNotes
                    ? 19
                    : 18
                  : inputSettings.showNotes
                    ? 13
                    : 12
              }
              value={emotion}
              onChange={(e) => setEmotion(e.target.value)}
              className="w-full p-2 lg:p-2.5 bg-[#0f172a] border border-white/10 rounded"
            >
              <option value="">Select emotion</option>
              <option value="Confident">Confident</option>
              <option value="Calm">Calm</option>
              <option value="Focused">Focused</option>
              <option value="Fearful">Fearful</option>
              <option value="FOMO">FOMO</option>
              <option value="Overconfident">Overconfident</option>
              <option value="Hesitant">Hesitant</option>
              <option value="Frustrated">Frustrated</option>
            </select>
          </div>
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-6">
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                tabIndex={
                  inputSettings.showEntryExit
                    ? inputSettings.showNotes
                      ? 22
                      : 21
                    : inputSettings.showNotes
                      ? 16
                      : 15
                }
                checked={followedPlan}
                onChange={(e) => setFollowedPlan(e.target.checked)}
              />
              Followed Plan?
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                tabIndex={
                  inputSettings.showEntryExit
                    ? inputSettings.showNotes
                      ? 23
                      : 22
                    : inputSettings.showNotes
                      ? 17
                      : 16
                }
                checked={newsEvent}
                onChange={(e) => setNewsEvent(e.target.checked)}
              />
              News Event?
            </label>
          </div>
          <div>
            <label className={fieldLabelClass}>Market</label>
            <select
              tabIndex={
                inputSettings.showEntryExit
                  ? inputSettings.showNotes
                    ? 20
                    : 19
                  : inputSettings.showNotes
                    ? 14
                    : 13
              }
              value={market}
              onChange={(e) => setMarket(e.target.value)}
              className="w-full p-2 lg:p-2.5 bg-[#0f172a] border border-white/10 rounded"
            >
              <option value="">Select market condition</option>
              <option value="Trending">Trending</option>
              <option value="Strong Trend">Strong Trend</option>
              <option value="Ranging">Ranging</option>
              <option value="Choppy">Choppy</option>
              <option value="Low Volume">Low Volume</option>
              <option value="High Volume">High Volume</option>
              <option value="News Driven">News Driven</option>
              <option value="Volatile">Volatile</option>
            </select>
          </div>
          <div className="space-y-1">
          <div>
            <label className={fieldLabelClass}>Psychology Notes</label>
            <textarea
              placeholder="What were you thinking in the moment?"
              tabIndex={
                inputSettings.showEntryExit
                  ? inputSettings.showNotes
                    ? 24
                    : 23
                  : inputSettings.showNotes
                    ? 18
                    : 17
              }
              value={psychologyNotes}
              onChange={(e) => setPsychologyNotes(e.target.value)}
              className="w-full p-2 lg:p-2.5 h-20 lg:h-24 xl:h-28 rounded bg-[#0f172a] border border-white/10 text-white"
            />
          </div>

          <div>
            <label className={fieldLabelClass}>Screenshot</label>
            <div
              tabIndex={
                inputSettings.showEntryExit
                  ? inputSettings.showNotes
                    ? 25
                    : 24
                  : inputSettings.showNotes
                    ? 19
                    : 18
              }
              onClick={handleClickUpload}
              onDrop={handleDrop}
              onDragOver={(e) => e.preventDefault()}
              className="h-24 flex items-center justify-center border border-dashed border-white/10 rounded text-gray-400 text-sm"
            >
            {image ? (
              <p>{image.name}</p>
            ) : isEditMode && existingTrade?.image_url ? (
              <p className="text-gray-400 text-sm">Keep existing image / drop new</p>
            ) : (
              <p>Upload Screenshot</p>
            )}
            <input
              ref={fileInputRef}
              type="file"
              className="hidden"
              accept="image/*"
              onChange={(e) => {
                const file = e.target.files?.[0]
                if (file) setImage(file)
              }}
            />
          </div>
          </div>
          </div>

          <button
            type="button"
            tabIndex={
              inputSettings.showEntryExit
                ? inputSettings.showNotes
                  ? 26
                  : 25
                : inputSettings.showNotes
                  ? 20
                  : 19
            }
            disabled={submitting || invalidFutureDate}
            onClick={() => void handleSubmit()}
            className="w-full py-3 text-lg font-semibold rounded bg-green-500 hover:bg-green-600 text-white"
          >
            {submitting ? "Saving…" : isEditMode ? "Save changes" : "Add Trade"}
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

  const settingsModal = showSettings && (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-[110]">
      <div className="bg-[#0f172a] border border-white/10 rounded-xl p-6 w-[min(440px,92vw)] space-y-4 max-h-[90vh] overflow-y-auto">
        <h2 className="text-lg font-semibold text-white">Input Settings</h2>
        <div className="rounded-lg border border-white/10 bg-white/5 p-3 space-y-2">
          <p className="text-sm font-medium text-white">Accounts</p>
          <p className="text-xs text-gray-500">
            Inactive accounts stay linked to trades but are hidden from the account picker.
          </p>
          {accounts.length === 0 ? (
            <p className="text-sm text-gray-500">No accounts yet.</p>
          ) : (
            <>
              {visibleAccountsInSettings.map((account) => {
                const sizeDisplay =
                  account.size != null && String(account.size).trim() !== ""
                    ? `$${formatAccountSize(account.size)}`
                    : "—"
                return (
                  <div
                    key={String(account.id)}
                    className="relative rounded-lg border border-white/10 bg-white/[0.03] p-3"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <span className="block truncate text-sm text-white">
                          {account.name} • {sizeDisplay}
                        </span>
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
                          className="w-full rounded border border-white/10 bg-white/5 px-2 py-1.5 text-sm text-white placeholder:text-gray-500"
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
        {Object.entries(inputSettings).map(([key, value]) => (
          <div key={key} className="flex items-center justify-between">
            <span className="text-sm text-gray-300 capitalize">
              {key.replace("show", "")}
            </span>
            <button
              type="button"
              onClick={() =>
                setInputSettings((prev) => ({
                  ...prev,
                  [key]: !prev[key as keyof typeof prev],
                }))
              }
              className={`w-12 h-6 flex items-center rounded-full p-1 transition ${
                value ? "bg-emerald-500" : "bg-red-500"
              }`}
            >
              <div
                className={`bg-white w-4 h-4 rounded-full shadow-md transform transition ${
                  value ? "translate-x-6" : "translate-x-0"
                }`}
              />
            </button>
          </div>
        ))}
        <button
          type="button"
          onClick={() => setShowSettings(false)}
          className="w-full bg-blue-500 hover:bg-blue-600 py-2 rounded font-semibold mt-4"
        >
          Done
        </button>
      </div>
    </div>
  )

  const feedbackModal = <FeedbackModal {...feedbackModalProps} />
  const communitySharePreviewModal = (
    <CommunitySharePreviewModal
      open={communityPreviewOpen}
      onClose={() => setCommunityPreviewOpen(false)}
      onPostTrade={() => void handleSubmit()}
      submitting={submitting}
      postTradeDisabled={invalidFutureDate}
      postTradeLabel={isEditMode ? "Save changes" : "Post Trade"}
      post={communityPreviewPost}
      user={communityPreviewUser}
    />
  )

  if (showAsModal) {
    return (
      <>
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50 overflow-y-auto py-4 md:py-6 px-3 sm:px-4 lg:px-6"
          onClick={() => onClose?.()}
          role="presentation"
        >
          <div
            className="w-full max-w-md md:max-w-4xl xl:max-w-7xl mx-auto rounded-xl p-4 md:p-6 lg:p-7 bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 shadow-xl max-h-[92vh] overflow-y-auto my-auto translate-y-5"
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-modal="true"
            aria-labelledby="input-trade-modal-title"
          >
            <div className="flex justify-between items-center gap-4 mb-2">
              <h2
                id="input-trade-modal-title"
                className="text-xl font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent"
              >
                Edit Trade
              </h2>
              <button
                type="button"
                onClick={() => onClose?.()}
                className="px-3 py-1 rounded bg-white/10 hover:bg-white/20 text-sm"
              >
                Close
              </button>
            </div>
            {formBody}
          </div>
        </div>
        {settingsModal}
        {feedbackModal}
        {communitySharePreviewModal}
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
                className="px-4 py-2 rounded bg-green-500 text-white w-full"
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
      {communitySharePreviewModal}
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
              className="px-4 py-2 rounded bg-green-500 text-white w-full"
            >
              Got it
            </button>
          </div>
        </div>
      )}
    </>
  )
}
