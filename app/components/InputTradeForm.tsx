"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { supabase } from "@/lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { ensureManualUserAccountRegistered } from "@/lib/ensureManualUserAccount"
import { isProActive } from "@/lib/subscription"
import { tradesInsertRowsPrivate } from "@/lib/csvTradeParsers"
import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

function modeLabelFromDb(raw: string | null | undefined): string {
  const s = String(raw ?? "").toLowerCase().trim()
  if (s === "eval") return "Eval"
  if (s === "funded") return "Funded"
  if (s === "live") return "Live"
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
}

function getESTDate() {
  const now = new Date()
  const est = new Date(
    now.toLocaleString("en-US", { timeZone: "America/New_York" })
  )
  const y = est.getFullYear()
  const m = String(est.getMonth() + 1).padStart(2, "0")
  const d = String(est.getDate()).padStart(2, "0")
  return `${y}-${m}-${d}`
}

function toTimeInputValue(raw: unknown): string {
  if (raw == null || raw === "") return ""
  const s = String(raw).trim()
  if (/^\d{2}:\d{2}$/.test(s)) return s
  if (/^\d{1,2}:\d{2}/.test(s)) {
    const parts = s.slice(0, 5).split(":")
    return `${String(Number(parts[0])).padStart(2, "0")}:${parts[1] || "00"}`
  }
  const d = new Date(s)
  if (!Number.isNaN(d.getTime())) {
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`
  }
  return ""
}

/** Combine trade date (YYYY-MM-DD) + time input (HH:MM) into a full ISO datetime for DB. */
function buildDateTime(
  date: string | null | undefined,
  time: string | null | undefined
): string | null {
  if (!date || !time) return null
  const dateStr = String(date).trim()
  const timeStr = String(time).trim()
  if (!dateStr || !timeStr) return null
  const parsed = new Date(`${dateStr} ${timeStr}`)
  if (Number.isNaN(parsed.getTime())) return null
  return parsed.toISOString()
}

function tradeDateFromRow(t: any): string {
  if (t?.created_at) return String(t.created_at).split("T")[0]
  if (t?.date) return String(t.date).split("T")[0]
  return getESTDate()
}

function formatAccountSize(size: any) {
  if (!size) return ""
  const num = Number(size)

  if (!isNaN(num) && num >= 1000) {
    return `${num / 1000}K`
  }

  return size
}

function formatMode(mode: any) {
  if (!mode) return "Live"

  const m = String(mode).toLowerCase()

  if (m === "eval") return "Eval"
  if (m === "funded") return "Funded"
  if (m === "live") return "Live"

  return mode
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
  onParsedTradesClear,
}: InputTradeFormProps) {
  const isEditMode = Boolean(existingTrade?.id)
  const showAsModal = isEditMode && Boolean(onClose)

  const [accounts, setAccounts] = useState<any[]>([])
  const [selectedAccount, setSelectedAccount] = useState<any | null>(null)
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [showAccountWarning, setShowAccountWarning] = useState(false)

  const [submitting, setSubmitting] = useState(false)
  const [confidence, setConfidence] = useState("")
  const [psychologyNotes, setPsychologyNotes] = useState("")
  const [tradeType, setTradeType] = useState("")
  const [showSettings, setShowSettings] = useState(false)
  const [popupMessage, setPopupMessage] = useState("")
  const [popupType, setPopupType] = useState<"success" | "error">("success")
  const [showPopup, setShowPopup] = useState(false)

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

    let regex

    if (allowDecimal && allowNegative) {
      regex = /^-?\d*\.?\d*$/
    } else if (allowDecimal) {
      regex = /^\d*\.?\d*$/
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
      cleaned === "-."
    ) {
      setter(cleaned)
      return
    }

    if (!regex.test(cleaned)) return

    setter(cleaned)
  }

  const [tradeDate, setTradeDate] = useState(getESTDate())
  const [ticker, setTicker] = useState("")
  const [direction, setDirection] = useState("Long")
  const [pnl, setPnl] = useState("")
  const [rr, setRR] = useState("")
  const [points, setPoints] = useState("")
  const [session, setSession] = useState("NY")
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
  const [entryTimeTouched, setEntryTimeTouched] = useState(false)
  const [exitTimeTouched, setExitTimeTouched] = useState(false)

  const fileInputRef = useRef<HTMLInputElement>(null)
  const dateRef = useRef<HTMLInputElement>(null)

  const [planProfile, setPlanProfile] = useState<{
    is_pro?: boolean | null
    subscription_status?: string | null
    locked_account_type?: string | null
    locked_account_size?: string | null
    locked_account_name?: string | null
    locked_account_number?: string | null
  } | null>(null)
  const [accountFieldsLocked, setAccountFieldsLocked] = useState(false)

  const refreshPlanAndAccountLock = useCallback(async () => {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user?.id) {
      setPlanProfile(null)
      setAccountFieldsLocked(false)
      return
    }
    const { data: prof } = await supabase
      .from("profiles")
      .select(
        "is_pro, subscription_status, locked_account_type, locked_account_size, locked_account_name, locked_account_number"
      )
      .eq("id", user.id)
      .maybeSingle()
    setPlanProfile(prof ?? null)
    if (isProActive(prof)) {
      setAccountFieldsLocked(false)
      return
    }
    const { data: rows } = await supabase
      .from("user_accounts")
      .select("account_type")
      .eq("user_id", user.id)
    const manualCount = (rows ?? []).filter(
      (t) =>
        String(t.account_type ?? "").toLowerCase().trim() !== "imported"
    ).length
    setAccountFieldsLocked(manualCount >= 1)
  }, [])

  useEffect(() => {
    void refreshPlanAndAccountLock()
  }, [refreshPlanAndAccountLock, existingTrade?.id])

  useEffect(() => {
    async function loadAccounts() {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user?.id) return

      const { data, error } = await supabase
        .from("accounts")
        .select("*")
        .eq("user_id", user.id)

      if (error) {
        console.error(error)
        return
      }

      const formatted = (data || []).map((acc) => ({
        name: acc.name,
        size: acc.account_size,
        id: acc.account_number,
        mode: acc.mode,
        category: acc.category,
      }))

      setAccounts(formatted)
    }

    void loadAccounts()
  }, [])

  useEffect(() => {
    if (showPopup) {
      const timer = setTimeout(() => setShowPopup(false), 2500)
      return () => clearTimeout(timer)
    }
  }, [showPopup])

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
    setTradeDate(tradeDateFromRow(t))
    setTicker(t.ticker ?? "")
    setDirection(t.direction || "Long")
    setPnl(
      t.pnl != null && t.pnl !== "" ? String(t.pnl).replace(/,/g, "") : ""
    )
    setRR(t.rr != null && t.rr !== "" ? String(t.rr) : "")
    setPoints(t.points != null && t.points !== "" ? String(t.points) : "")
    setSession(t.session || "NY")
    setConfluences(t.top_confluences ?? t.notes ?? "")
    setPublicDescription(t.public_description ?? "")
    setPostToFeed(false)
    setIsPublic(Boolean(t.is_public))
    setImage(null)
    setStrategy(t.strategy ?? "")
    const acctCat = (t as { account_category?: string | null }).account_category
    setSelectedAccount({
      name: String(t.account_name ?? "").trim(),
      size:
        t.account_size != null && t.account_size !== ""
          ? String(t.account_size)
          : "",
      id: t.account_id != null && t.account_id !== "" ? String(t.account_id) : "",
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
    setEntryTime(toTimeInputValue(t.entry_time))
    setExitTime(toTimeInputValue(t.exit_time))
    setEntryTimeTouched(false)
    setExitTimeTouched(false)
  }, [existingTrade])

  function resetCreateForm() {
    setTicker("")
    setDirection("Long")
    setPnl("")
    setRR("")
    setPoints("")
    setSession("NY")
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
    setTradeDate(getESTDate())
    setPostToFeed(false)
    setStrategy("")
  }

  async function handleSubmit() {
    if (submitting) return

    if (!selectedAccount) {
      setShowAccountWarning(true)
      return
    }

    const acct = selectedAccount

    setSubmitting(true)

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user?.id) {
      setPopupMessage("Failed to save trade")
      setPopupType("error")
      setShowPopup(true)
      setSubmitting(false)
      return
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

    const sessionToSave = (session && String(session).trim()) || "NY"
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
      id: String(acct.id ?? "").trim() || null,
      mode: String(acct.mode ?? "live"),
      category: acct.category ?? null,
    }

    const { data: profileRow } = await supabase
      .from("profiles")
      .select(
        "is_pro, subscription_status, locked_account_type, locked_account_size, locked_account_name, locked_account_number"
      )
      .eq("id", user.id)
      .maybeSingle()
    const userIsPro = isProActive(profileRow)

    if (!userIsPro && modeLower !== "backtest" && modeLower !== "imported") {
      const lockedType = String(profileRow?.locked_account_type ?? "").trim().toLowerCase()
      const lockedSize = String(profileRow?.locked_account_size ?? "").trim()
      const lockedName = String(profileRow?.locked_account_name ?? "").trim()
      const lockedNumber = String(profileRow?.locked_account_number ?? "").trim()
      const incomingType = String(modeLower).trim().toLowerCase()
      const incomingSize = String(rowAcct.size ?? "").trim()
      const incomingName = String(rowAcct.name ?? "").trim()
      const incomingNumber = String(rowAcct.id ?? "").trim()

      if (!lockedType) {
        const { error: lockErr } = await supabase
          .from("profiles")
          .update({
            locked_account_type: incomingType || null,
            locked_account_size: incomingSize || null,
            locked_account_name: incomingName || null,
            locked_account_number: incomingNumber || null,
          })
          .eq("id", user.id)
        if (lockErr) {
          console.error("locked account update:", lockErr)
          setPopupMessage("Failed to save trade")
          setPopupType("error")
          setShowPopup(true)
          setSubmitting(false)
          return
        }
      } else {
        rowAcct = {
          type: lockedType || modeLower,
          size: lockedSize || null,
          name: lockedName || null,
          id: lockedNumber || null,
          mode: lockedType || modeLower,
          category: rowAcct.category,
        }

        if (
          incomingType !== lockedType ||
          incomingSize !== lockedSize ||
          incomingName !== lockedName ||
          incomingNumber !== lockedNumber
        ) {
          setPopupMessage("Failed to save trade")
          setPopupType("error")
          setShowPopup(true)
          setSelectedAccount({
            name: lockedName,
            size: lockedSize,
            id: lockedNumber,
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
      setPopupMessage("Failed to save trade")
      setPopupType("error")
      setShowPopup(true)
      setSubmitting(false)
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
        entry_time: entryTimeTouched
          ? buildDateTime(tradeDate, entryTime)
          : existingTrade.entry_time ?? null,
        exit_time: exitTimeTouched
          ? buildDateTime(tradeDate, exitTime)
          : existingTrade.exit_time ?? null,
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
        setPopupMessage("Failed to save trade")
        setPopupType("error")
        setShowPopup(true)
        setSubmitting(false)
        return
      }

      if (isPublic) {
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
        if (postErr) console.error("posts upsert:", postErr)
      } else {
        const { error: delErr } = await supabase
          .from("posts")
          .delete()
          .eq("trade_id", existingTrade.id)
        if (delErr) console.error("posts delete:", delErr)
      }

      void refreshPlanAndAccountLock()
      onSave?.()
      onClose?.()
      setPopupMessage("Trade saved successfully")
      setPopupType("success")
      setShowPopup(true)
      setSubmitting(false)
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
      entry_price: parsedTrade.entry_price,
      exit_price: parsedTrade.exit_price,
      entry_time: buildDateTime(tradeDate, entryTime),
      exit_time: buildDateTime(tradeDate, exitTime),
      psychology_notes: psychologyVal,
      trade_type: tradeTypeToSave,
      confidence: confidence ? Number(confidence) : null,
      emotion: emotion || null,
      followed_plan: followedPlan,
      mistake_type: mistakeType || null,
      market_condition: market || null,
      news_event: newsEvent,
      timeframe: timeframe || null,
      is_public: postToFeed,
    }

    const { data: newTradeData, error } = await supabase
      .from("trades")
      .insert([tradeData])
      .select()
      .single()

    if (error) {
      console.error("Trade insert error:", error)
      setPopupMessage("Failed to save trade")
      setPopupType("error")
      setShowPopup(true)
      setSubmitting(false)
      return
    }

    if (postToFeed && newTradeData) {
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
      }
    }

    void refreshPlanAndAccountLock()
    resetCreateForm()
    setPopupMessage("Trade saved successfully")
    setPopupType("success")
    setShowPopup(true)
    setSubmitting(false)
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
      setPopupMessage("Failed to save trade")
      setPopupType("error")
      setShowPopup(true)
      return
    }

    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("is_pro, has_used_csv_import")
      .eq("id", user.id)
      .single()

    if (profileErr || !profile) {
      console.error("Profile fetch failed:", profileErr)
      setPopupMessage("Failed to save trade")
      setPopupType("error")
      setShowPopup(true)
      return
    }

    console.log("CSV BLOCK CHECK:", profile)

    if (!profile.is_pro && profile.has_used_csv_import) {
      setPopupMessage("Failed to save trade")
      setPopupType("error")
      setShowPopup(true)
      return
    }

    onUploadCsvClick()
  }

  async function handleCsvManualImport() {
    if (!selectedAccount) {
      alert("Please select an account first")
      return
    }

    try {
      const finalTrades = parsedTrades.map((trade: any) => ({
        ...trade,
        account_name: selectedAccount.name,
        account_size: selectedAccount.size,
        account_id: selectedAccount.id,
        mode: selectedAccount.mode,
      }))

      const rows = tradesInsertRowsPrivate(finalTrades)

      const { error } = await supabase.from("trades").insert(rows)

      if (error) {
        console.error(error)
        alert("Import failed")
        return
      }

      alert(`Imported ${parsedTrades.length} trades`)

      onParsedTradesClear?.()
      setSelectedAccount(null)
    } catch (err) {
      console.error(err)
      alert("Something went wrong")
    }
  }

  async function handleCreateAccountSave(newAccount: CreateAccountSavePayload) {
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) return

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
      alert("Failed to create account")
      return
    }

    if (!data) return

    setAccounts((prev) => [
      ...prev,
      {
        name: data.name,
        size: data.account_size,
        id: data.account_number,
        mode: data.mode,
        category: data.category,
      },
    ])

    setSelectedAccount({
      name: data.name,
      size: data.account_size,
      id: data.account_number,
      mode: data.mode,
      category: data.category,
    })

    setShowCreateModal(false)
  }

  const formBody = (
    <>
      <div className="mb-4">
        <div className="flex flex-col gap-2 md:hidden">
          <div className="flex gap-2 flex-wrap">
            {onUploadCsvClick ? (
              <select
                value={selectedAccount ? JSON.stringify(selectedAccount) : ""}
                onChange={(e) => {
                  const val = e.target.value

                  if (!val) {
                    setSelectedAccount(null)
                    return
                  }

                  if (val === "NEW_ACCOUNT") {
                    setShowCreateModal(true)
                    return
                  }

                  try {
                    setSelectedAccount(JSON.parse(val))
                  } catch {
                    setSelectedAccount(null)
                  }
                }}
                className="ml-2 px-2 py-2 bg-black/30 border border-white/10 rounded text-sm min-w-0"
              >
                <option value="">Select Account</option>
                {accounts.map((acc, i) => (
                  <option key={i} value={JSON.stringify(acc)}>
                    {acc.name} • {formatAccountSize(acc.size)} • {acc.category || "Personal"} •{" "}
                    {formatMode(acc.mode)} • #{acc.id}
                  </option>
                ))}
                <option value="NEW_ACCOUNT">+ Create New Account</option>
              </select>
            ) : null}
            <button
              type="button"
              onClick={() => void handleUploadCsvGuardClick()}
              disabled={!onUploadCsvClick || csvLoading}
              className="flex-1 px-3 py-2 text-sm rounded-lg bg-blue-500 disabled:opacity-60"
            >
              Upload CSV
            </button>
            {parsedTrades.length > 0 ? (
              <button
                type="button"
                onClick={() => void handleCsvManualImport()}
                disabled={!selectedAccount}
                className={`ml-2 px-4 py-2 rounded ${
                  selectedAccount
                    ? "bg-green-500/20 text-green-400"
                    : "bg-gray-700 text-gray-400 cursor-not-allowed"
                }`}
              >
                Import {parsedTrades.length}
              </button>
            ) : null}
            <button
              type="button"
              onClick={onReviewCsvClick}
              disabled={!onReviewCsvClick}
              className="relative flex-1 px-3 py-2 text-sm rounded-lg bg-emerald-500 disabled:opacity-60"
            >
              Review CSV Inputs
              {reviewCount > 0 ? (
                <span className="absolute -top-1 -right-1 bg-red-500 text-white rounded-full text-[10px] px-1.5 py-0.5">
                  {reviewCount > 99 ? "99+" : reviewCount}
                </span>
              ) : null}
            </button>
          </div>

          <div className="flex justify-end">
            <button
              type="button"
              onClick={() => setShowSettings(true)}
              className="px-3 py-2 bg-[#1f2937] rounded-lg flex items-center justify-center"
              aria-label="Settings"
            >
              ⚙️
            </button>
          </div>
        </div>

        <div className="hidden md:flex items-center w-full">
          <div className="flex items-center gap-3">
            {onUploadCsvClick ? (
              <select
                value={selectedAccount ? JSON.stringify(selectedAccount) : ""}
                onChange={(e) => {
                  const val = e.target.value

                  if (!val) {
                    setSelectedAccount(null)
                    return
                  }

                  if (val === "NEW_ACCOUNT") {
                    setShowCreateModal(true)
                    return
                  }

                  try {
                    setSelectedAccount(JSON.parse(val))
                  } catch {
                    setSelectedAccount(null)
                  }
                }}
                className="ml-2 px-2 py-2 bg-black/30 border border-white/10 rounded text-sm min-w-0"
              >
                <option value="">Select Account</option>
                {accounts.map((acc, i) => (
                  <option key={i} value={JSON.stringify(acc)}>
                    {acc.name} • {formatAccountSize(acc.size)} • {acc.category || "Personal"} •{" "}
                    {formatMode(acc.mode)} • #{acc.id}
                  </option>
                ))}
                <option value="NEW_ACCOUNT">+ Create New Account</option>
              </select>
            ) : null}

            <button
              type="button"
              onClick={() => void handleUploadCsvGuardClick()}
              disabled={!onUploadCsvClick || csvLoading}
              className="px-4 py-2 text-sm rounded-lg bg-blue-500 disabled:opacity-60"
            >
              Upload CSV
            </button>

            {parsedTrades.length > 0 ? (
              <button
                type="button"
                onClick={() => void handleCsvManualImport()}
                disabled={!selectedAccount}
                className={`ml-2 px-4 py-2 rounded ${
                  selectedAccount
                    ? "bg-green-500/20 text-green-400"
                    : "bg-gray-700 text-gray-400 cursor-not-allowed"
                }`}
              >
                Import {parsedTrades.length}
              </button>
            ) : null}

            <button
              type="button"
              onClick={onReviewCsvClick}
              disabled={!onReviewCsvClick}
              className="relative px-4 py-2 text-sm rounded-lg bg-emerald-500 disabled:opacity-60"
            >
              Review CSV Inputs
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

      {selectedAccount && (
        <div className="mb-4 px-4 py-2 rounded-lg bg-green-500/10 border border-green-500/20 text-green-400 text-sm">
          Trading on: {selectedAccount.name} • {selectedAccount.size} •{" "}
          {selectedAccount.category}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="p-4 rounded-xl bg-[#0b1220]/60 border border-white/5">
          <h3 className="text-sm text-gray-400 mb-2">Trade</h3>
          <div className="space-y-3">
          <input
            ref={dateRef}
            type="date"
            value={tradeDate}
            onChange={(e) => setTradeDate(e.target.value)}
            className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10 text-white [color-scheme:dark]"
          />

          <div className="relative w-full">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
              $
            </span>

            <input
              type="text"
              value={
                pnl === "-" || pnl === "." || pnl === "-."
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

          <input
            type="text"
            placeholder="Symbol / Ticker (e.g. MNQ, ES, AAPL)"
            value={ticker}
            onChange={(e) => setTicker(e.target.value.toUpperCase())}
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
          />

          <input
            type="text"
            placeholder="Strategy used (e.g. Breakout, Liquidity Sweep)"
            value={strategy}
            onChange={(e) => setStrategy(e.target.value)}
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
          />

          <select
            value={direction}
            onChange={(e) => setDirection(e.target.value)}
            className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
          >
            <option>Long</option>
            <option>Short</option>
          </select>

          <select
            value={session}
            onChange={(e) => setSession(e.target.value)}
            className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
          >
            <option value="NY">NY</option>
            <option value="London">London</option>
            <option value="Asia">Asia</option>
          </select>

          {inputSettings.showRR && (
            <input
              placeholder="Risk Reward"
              type="text"
              value={rr}
              onChange={(e) =>
                handleNumericInput(e.target.value, setRR, { allowDecimal: true })
              }
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          {inputSettings.showPoints && (
            <input
              placeholder="Points"
              type="text"
              value={
                points === "-" || points === "." || points === "-."
                  ? points
                  : formatWithCommas(points)
              }
              onChange={(e) =>
                handleNumericInput(e.target.value, setPoints, {
                  allowDecimal: true,
                  allowNegative: true,
                })
              }
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          {inputSettings.showContracts && (
            <input
              placeholder="Contracts"
              type="text"
              value={formatWithCommas(contracts)}
              onChange={(e) => handleNumericInput(e.target.value, setContracts)}
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          <label className="text-gray-400 text-sm mb-1 block">Top Confluences</label>
          {inputSettings.showNotes && (
            <textarea
              placeholder="What confirmations led to this trade?"
              value={confluences}
              onChange={(e) => setConfluences(e.target.value)}
              className="w-full p-2 lg:p-2.5 h-24 lg:h-28 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          {accountControlsDisabled ? (
            <p className="text-xs text-amber-400/90">
              Free plan: account details are locked to your existing prop firm. Upgrade
              to Pro for unlimited accounts.
            </p>
          ) : null}

          </div>
        </div>

        <div className="p-4 rounded-xl bg-[#0b1220]/60 border border-white/5">
          <h3 className="text-sm text-gray-400 mb-2">Execution</h3>
          <div className="space-y-3">
          {inputSettings.showEntryExit && (
            <div className="space-y-2 mb-4">
              <div>
                <label className="text-xs text-gray-400">Entry Price</label>
                <div className="relative w-full">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                    $
                  </span>

                  <input
                    type="text"
                    value={
                      entryPrice === "-" ||
                      entryPrice === "." ||
                      entryPrice === "-."
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
                <label className="text-xs text-gray-400">Exit Price</label>
                <div className="relative w-full">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                    $
                  </span>

                  <input
                    type="text"
                    value={
                      exitPrice === "-" || exitPrice === "." || exitPrice === "-."
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
              <div>
                <label className="text-xs text-gray-400">Entry Time</label>
                <input
                  type="time"
                  value={entryTime}
                  onChange={(e) => {
                    setEntryTimeTouched(true)
                    setEntryTime(e.target.value)
                  }}
                  className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10 [color-scheme:dark]"
                />
              </div>
              <div>
                <label className="text-xs text-gray-400">Exit Time</label>
                <input
                  type="time"
                  value={exitTime}
                  onChange={(e) => {
                    setExitTimeTouched(true)
                    setExitTime(e.target.value)
                  }}
                  className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10 [color-scheme:dark]"
                />
              </div>
            </div>
          )}

          <div className="mt-0">
            <label className="text-gray-400 text-sm mb-1 block">
              Public Description
            </label>
            <textarea
              value={publicDescription}
              onChange={(e) => setPublicDescription(e.target.value)}
              placeholder="Insert public thoughts..."
              className="w-full p-2 lg:p-2.5 rounded-lg bg-[#0f172a] text-white border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[96px] lg:min-h-[120px]"
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
              onClick={() => setIsPublic(!isPublic)}
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
          </div>
        </div>

        <div className="p-4 rounded-xl bg-[#0b1220]/60 border border-white/5">
          <h3 className="text-sm text-gray-400 mb-2">Psychology</h3>
          <div className="space-y-3">
          <select
            value={confidence}
            onChange={(e) => setConfidence(e.target.value)}
            className="w-full p-2 lg:p-2.5 bg-[#0f172a] border border-white/10 rounded"
          >
            <option value="">Confidence (bad to great)</option>
            <option>1</option>
            <option>2</option>
            <option>3</option>
            <option>4</option>
            <option>5</option>
          </select>
          <input
            type="text"
            placeholder="Emotion"
            value={emotion}
            onChange={(e) => setEmotion(e.target.value)}
            list="emotion-options"
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
          />
          <datalist id="emotion-options">
            <option value="Confident" />
            <option value="Fearful" />
            <option value="FOMO" />
            <option value="Calm" />
            <option value="Overconfident" />
          </datalist>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={followedPlan}
              onChange={(e) => setFollowedPlan(e.target.checked)}
            />
            Followed Plan?
          </label>
          <p className="text-sm text-gray-400 mt-0">Context</p>
          <input
            type="text"
            placeholder="Market"
            value={market}
            onChange={(e) => setMarket(e.target.value)}
            list="market-options"
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
          />
          <datalist id="market-options">
            <option value="Trending" />
            <option value="Ranging" />
            <option value="Choppy" />
            <option value="News-driven" />
          </datalist>
          <select
            value={timeframe}
            onChange={(e) => setTimeframe(e.target.value)}
            className="w-full p-2 lg:p-2.5 bg-[#0f172a] border border-white/10 rounded"
          >
            <option value="">Timeframe</option>
            <option>1m</option>
            <option>5m</option>
            <option>15m</option>
          </select>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={newsEvent}
              onChange={(e) => setNewsEvent(e.target.checked)}
            />
            News Event?
          </label>
          <p className="text-sm text-gray-400 mt-0">Psychology Notes</p>
          <textarea
            placeholder="What were you thinking in the moment?"
            value={psychologyNotes}
            onChange={(e) => setPsychologyNotes(e.target.value)}
            className="w-full p-2 lg:p-2.5 h-28 lg:h-36 xl:h-40 rounded bg-[#0f172a] border border-white/10 text-white"
          />

          <div
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

          <button
            type="button"
            disabled={submitting}
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

  const settingsModal = showSettings && (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-[110]">
      <div className="bg-[#0f172a] border border-white/10 rounded-xl p-6 w-[400px] space-y-4 max-h-[90vh] overflow-y-auto">
        <h2 className="text-lg font-semibold text-white">Input Settings</h2>
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

  const popupModal = showPopup && (
    <div className="fixed inset-0 flex items-center justify-center z-50">
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />
      <div
        className={`relative w-full max-w-sm rounded-xl border px-6 py-5 text-center shadow-xl ${
          popupType === "success" ? "border-green-500 bg-green-900/20" : "border-red-500 bg-red-900/20"
        }`}
      >
        <p className={`text-sm font-medium ${popupType === "success" ? "text-green-400" : "text-red-400"}`}>
          {popupMessage}
        </p>
        <button
          type="button"
          onClick={() => setShowPopup(false)}
          className="mt-4 text-xs text-gray-400 hover:underline"
        >
          Close
        </button>
      </div>
    </div>
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
            className="w-full max-w-md md:max-w-4xl xl:max-w-7xl mx-auto rounded-xl p-4 md:p-6 lg:p-7 bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 shadow-xl max-h-[92vh] overflow-y-auto my-auto"
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
        {popupModal}
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
      {popupModal}
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
