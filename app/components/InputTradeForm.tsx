"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { supabase } from "@/lib/supabaseClient"
import { ensureManualUserAccountRegistered } from "@/lib/ensureManualUserAccount"
import { isProActive } from "@/lib/subscription"

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

export default function InputTradeForm({
  existingTrade,
  onSave,
  onClose,
  forceMarkReviewedOnSave = false,
  onUploadCsvClick,
  onReviewCsvClick,
  reviewCount = 0,
  csvLoading = false,
}: InputTradeFormProps) {
  const isEditMode = Boolean(existingTrade?.id)
  const showAsModal = isEditMode && Boolean(onClose)

  const [submitting, setSubmitting] = useState(false)
  const [pnlFocused, setPnlFocused] = useState(false)
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
  const [marketCondition, setMarketCondition] = useState("")
  const [newsEvent, setNewsEvent] = useState(false)
  const [timeframe, setTimeframe] = useState("")

  function handleNumberInput(value: string) {
    if (/^-?\d*\.?\d*$/.test(value)) return value
    return null
  }

  function formatWithCommas(value: string) {
    if (!value || value === "-") return value
    const isNegative = value.startsWith("-")
    const abs = isNegative ? value.slice(1) : value
    if (abs === "" || abs === ".") return value
    const parts = abs.split(".")
    const intPart = Number(parts[0]).toLocaleString("en-US")
    const decimalPart = parts[1] !== undefined ? "." + parts[1] : ""
    return (isNegative ? "-" : "") + intPart + decimalPart
  }

  const [tradeDate, setTradeDate] = useState(getESTDate())
  const [ticker, setTicker] = useState("")
  const [direction, setDirection] = useState("Long")
  const [pnl, setPnl] = useState("")
  const [rr, setRR] = useState("")
  const [points, setPoints] = useState("")
  const [session, setSession] = useState("NY")
  const [notes, setNotes] = useState("")
  const [publicDescription, setPublicDescription] = useState("")
  const [postToFeed, setPostToFeed] = useState(false)
  const [isPublic, setIsPublic] = useState(false)
  const [image, setImage] = useState<File | null>(null)

  const [mode, setMode] = useState("Live")
  const [strategy, setStrategy] = useState("")

  const [firm, setFirm] = useState("")
  const [accountSize, setAccountSize] = useState("")
  const [accountNumber, setAccountNumber] = useState("")

  const firmOptions = [
    "Alpha Futures",
    "Apex",
    "Topstep",
    "Goat Funded Futures",
    "Live Account",
  ]

  const accountSizes: Record<string, string[]> = {
    "Alpha Futures": ["25K", "50K", "100K", "150K"],
    Apex: ["25K", "50K", "75K", "100K", "150K", "300K"],
    Topstep: ["50K", "100K", "150K"],
    "Goat Funded Futures": ["25K", "50K", "100K", "150K"],
    "Live Account": ["Custom"],
  }

  const [advanced, setAdvanced] = useState(false)
  const [entryPrice, setEntryPrice] = useState("")
  const [exitPrice, setExitPrice] = useState("")
  const [contracts, setContracts] = useState("")
  const [entryTime, setEntryTime] = useState("")
  const [exitTime, setExitTime] = useState("")
  const [entryTimeTouched, setEntryTimeTouched] = useState(false)
  const [exitTimeTouched, setExitTimeTouched] = useState(false)

  const fileInputRef = useRef<HTMLInputElement>(null)
  const dateRef = useRef<HTMLInputElement>(null)

  const symbols = ["MNQ", "MES", "MGC", "MCL", "MYM", "M2K"]

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
    if (showPopup) {
      const timer = setTimeout(() => setShowPopup(false), 2500)
      return () => clearTimeout(timer)
    }
  }, [showPopup])

  useEffect(() => {
    if (isEditMode || mode === "Backtest" || !accountFieldsLocked) return
    let cancelled = false
    void (async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user?.id || cancelled) return
      const { data: rows } = await supabase
        .from("user_accounts")
        .select("account_name, account_type, created_at")
        .eq("user_id", user.id)
      const manual = (rows ?? []).filter(
        (r) =>
          String(r.account_type ?? "").toLowerCase().trim() !== "imported"
      )
      manual.sort(
        (a, b) =>
          new Date(String((b as { created_at?: string }).created_at ?? 0)).getTime() -
          new Date(String((a as { created_at?: string }).created_at ?? 0)).getTime()
      )
      const first = manual[0] as {
        account_name: string | null
        account_type: string | null
      } | undefined
      if (!first || cancelled) return
      setMode(modeLabelFromDb(first.account_type))
      setAccountSize("")
      setAccountNumber("")
      setFirm(first.account_name != null ? String(first.account_name) : "")
    })()
    return () => {
      cancelled = true
    }
  }, [isEditMode, mode, accountFieldsLocked, existingTrade?.id])

  const accountInputsDisabled =
    accountFieldsLocked && mode !== "Backtest" && !isProActive(planProfile)
  const isPro = isProActive(planProfile)
  const isLocked = !isPro && Boolean(planProfile?.locked_account_type)
  const lockedMode = modeLabelFromDb(planProfile?.locked_account_type)
  const displayedMode = isLocked ? lockedMode : mode
  const displayedFirm = isLocked ? String(planProfile?.locked_account_name ?? "") : firm
  const displayedAccountSize = isLocked
    ? String(planProfile?.locked_account_size ?? "")
    : accountSize
  const displayedAccountNumber = isLocked
    ? String(planProfile?.locked_account_number ?? "")
    : accountNumber
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
    setNotes(t.notes ?? "")
    setPublicDescription(t.public_description ?? "")
    setPostToFeed(false)
    setIsPublic(Boolean(t.is_public))
    setImage(null)
    const at = String(t.mode ?? t.account_type ?? "").toLowerCase().trim()
    let category: "funded" | "eval" | "live" | "backtest" = "eval"
    let firmFromLegacy = ""
    if (at === "funded" || at === "eval" || at === "live" || at === "backtest") {
      category = at
    } else if (at.includes("fund")) {
      category = "funded"
    } else if (at.includes("eval")) {
      category = "eval"
    } else if (at.includes("live")) {
      category = "live"
    } else if (at.includes("back")) {
      category = "backtest"
    } else if (t.account_type) {
      firmFromLegacy = String(t.account_type)
    }
    setMode(category.charAt(0).toUpperCase() + category.slice(1))
    setStrategy(t.strategy ?? "")
    const accountNameStr = String(t.account_name ?? "").trim()
    setFirm(accountNameStr || firmFromLegacy)
    setAccountSize(
      t.account_size != null && t.account_size !== ""
        ? String(t.account_size)
        : ""
    )
    setAccountNumber(
      t.account_id != null && t.account_id !== "" ? String(t.account_id) : ""
    )
    setTradeType(t.trade_type ?? "")
    setConfidence(
      t.confidence != null && t.confidence !== "" ? String(t.confidence) : ""
    )
    setEmotion(t.emotion ?? "")
    setFollowedPlan(Boolean(t.followed_plan))
    setMistakeType(t.mistake_type ?? "")
    setMarketCondition(t.market_condition ?? "")
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
    setAdvanced(
      Boolean(
        (t.entry_price != null && t.entry_price !== "") ||
          (t.exit_price != null && t.exit_price !== "") ||
          t.entry_time ||
          t.exit_time
      )
    )
  }, [existingTrade])

  function resetCreateForm() {
    setTicker("")
    setDirection("Long")
    setPnl("")
    setRR("")
    setPoints("")
    setSession("NY")
    setNotes("")
    setPublicDescription("")
    setImage(null)
    setEntryPrice("")
    setExitPrice("")
    setContracts("")
    setEntryTime("")
    setExitTime("")
    setFirm("")
    setAccountSize("")
    setAccountNumber("")
    setConfidence("")
    setEmotion("")
    setFollowedPlan(false)
    setMistakeType("")
    setMarketCondition("")
    setNewsEvent(false)
    setTimeframe("")
    setPsychologyNotes("")
    setTradeType("")
    setTradeDate(getESTDate())
    setPostToFeed(false)
    setMode("Live")
    setStrategy("")
  }

  async function handleSubmit() {
    if (submitting) return
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
      const fileName = `${user.id}/${Date.now()}-${image.name}`
      const { error: upErr } = await supabase.storage
        .from("screenshots")
        .upload(fileName, image)
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
    const firmToSaveRaw = String(firm || "").trim()
    const firmToSave = firmToSaveRaw !== "" ? firmToSaveRaw : null

    const { data: profileRow } = await supabase
      .from("profiles")
      .select(
        "is_pro, subscription_status, locked_account_type, locked_account_size, locked_account_name, locked_account_number"
      )
      .eq("id", user.id)
      .maybeSingle()
    const userIsPro = isProActive(profileRow)

    const modeLower = mode.toLowerCase()
    let finalAccount = {
      type: modeLower,
      size: accountSize || null,
      name: firmToSave,
      number: accountNumber || null,
    }
    if (!userIsPro && modeLower !== "backtest" && modeLower !== "imported") {
      const lockedType = String(profileRow?.locked_account_type ?? "").trim().toLowerCase()
      const lockedSize = String(profileRow?.locked_account_size ?? "").trim()
      const lockedName = String(profileRow?.locked_account_name ?? "").trim()
      const lockedNumber = String(profileRow?.locked_account_number ?? "").trim()
      const incomingType = String(modeLower).trim().toLowerCase()
      const incomingSize = String(accountSize ?? "").trim()
      const incomingName = String(firmToSave ?? "").trim()
      const incomingNumber = String(accountNumber ?? "").trim()

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
        finalAccount = {
          type: lockedType || modeLower,
          size: lockedSize || null,
          name: lockedName || null,
          number: lockedNumber || null,
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
          setMode(modeLabelFromDb(lockedType))
          setAccountSize(lockedSize)
          setFirm(lockedName)
          setAccountNumber(lockedNumber)
        }
      }
    }

    const skipAccountRegistry =
      modeLower === "backtest" || modeLower === "imported"

    const ensured = await ensureManualUserAccountRegistered(supabase, {
      userId: user.id,
      accountName: firmToSave ?? "",
      tradeAccountType: modeLower,
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
        notes: notes ?? "",
        public_description: publicDescription ?? "",
        image_url: imageUrlOut,
        account_name: finalAccount.name,
        account_type: finalAccount.type,
        mode: finalAccount.type,
        strategy:
          mode === "Backtest" && String(strategy).trim() !== ""
            ? String(strategy).trim()
            : null,
        account_size: finalAccount.size,
        account_id: finalAccount.number,
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
        market_condition: marketCondition || null,
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
            caption: notes ?? "",
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

    const parsedEntry = advanced ? parseFloat(entryPrice) || 0 : null
    const parsedExit = advanced ? parseFloat(exitPrice) || 0 : null

    const tradesToInsert = [
      {
        ticker,
        direction,
        pnl: parsedPnl,
        rr: parsedRR,
        points: parsedPoints,
        contracts: contractsNum,
        session: sessionToSave,
        notes,
        public_description: publicDescription,
        image_url: screenshotUrl,
        account_name: finalAccount.name,
        account_type: finalAccount.type,
        mode: finalAccount.type,
        strategy:
          mode === "Backtest" && String(strategy).trim() !== ""
            ? String(strategy).trim()
            : null,
        account_size: finalAccount.size,
        account_id: finalAccount.number,
        user_id: user.id,
        created_at: now.toISOString(),
        date: now.toISOString(),
        entry_price: parsedEntry,
        exit_price: parsedExit,
        entry_time: buildDateTime(tradeDate, entryTime),
        exit_time: buildDateTime(tradeDate, exitTime),
        psychology_notes: psychologyVal,
        trade_type: tradeTypeToSave,
        confidence: confidence ? Number(confidence) : null,
        emotion: emotion || null,
        followed_plan: followedPlan,
        mistake_type: mistakeType || null,
        market_condition: marketCondition || null,
        news_event: newsEvent,
        timeframe: timeframe || null,
        is_public: postToFeed,
      },
    ]

    const { data: newTradeData, error } = await supabase
      .from("trades")
      .insert(tradesToInsert)
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
          caption: notes,
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

  const formBody = (
    <>
      <div className="mb-4">
        <div className="flex flex-col gap-2 md:hidden">
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => void handleUploadCsvGuardClick()}
              disabled={!onUploadCsvClick || csvLoading}
              className="flex-1 px-3 py-2 text-sm rounded-lg bg-blue-500 disabled:opacity-60"
            >
              Upload CSV
            </button>
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

          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setAdvanced(!advanced)}
              className="flex-1 px-3 py-2 text-sm rounded-lg bg-[#1f2937]"
            >
              {advanced ? "Advanced Mode: ON" : "Advanced Mode: OFF"}
            </button>
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
            <button
              type="button"
              onClick={() => void handleUploadCsvGuardClick()}
              disabled={!onUploadCsvClick || csvLoading}
              className="px-4 py-2 text-sm rounded-lg bg-blue-500 disabled:opacity-60"
            >
              Upload CSV
            </button>

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

            <button
              type="button"
              onClick={() => setAdvanced(!advanced)}
              className="px-4 py-2 text-sm rounded-lg bg-[#1f2937]"
            >
              {advanced ? "Advanced Mode: ON" : "Advanced Mode: OFF"}
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

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-5 lg:gap-7 xl:gap-8">
        <div className="bg-white/5 p-4 lg:p-5 rounded-xl border border-white/10 space-y-3">
          <input
            ref={dateRef}
            type="date"
            value={tradeDate}
            onChange={(e) => setTradeDate(e.target.value)}
            className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10 text-white [color-scheme:dark]"
          />

          {accountControlsDisabled ? (
            <p className="text-xs text-amber-400/90">
              Free plan: account details are locked to your existing prop firm. Upgrade
              to Pro for unlimited accounts.
            </p>
          ) : null}

          <select
            value={displayedFirm}
            onChange={(e) => setFirm(e.target.value)}
            disabled={accountControlsDisabled}
            className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <option value="">Account Type</option>
            {firmOptions.map((f) => (
              <option key={f} value={f}>
                {f}
              </option>
            ))}
          </select>

          <select
            value={displayedAccountSize}
            onChange={(e) => setAccountSize(e.target.value)}
            disabled={accountControlsDisabled}
            className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <option value="">Account Size</option>
            {(accountSizes[displayedFirm] || []).map((size) => (
              <option key={size} value={size}>
                {size}
              </option>
            ))}
          </select>

          <input
            placeholder="Account Number"
            value={displayedAccountNumber}
            onChange={(e) => setAccountNumber(e.target.value)}
            disabled={accountControlsDisabled}
            className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          />
          {isLocked ? (
            <div className="text-sm text-white/70 mt-2">
              {planProfile?.locked_account_type} • {planProfile?.locked_account_name}{" "}
              {planProfile?.locked_account_size} #{planProfile?.locked_account_number}
            </div>
          ) : null}

          <input
            list="trade-symbol-options"
            placeholder="Symbol / ticker"
            value={ticker}
            onChange={(e) => setTicker(e.target.value)}
            className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
          />
          <datalist id="trade-symbol-options">
            {symbols.map((s) => (
              <option key={s} value={s} />
            ))}
          </datalist>
          <div className="w-full">
            <p className="text-sm text-gray-400 mt-0">
              Account Used
              {isLocked ? (
                <span className="text-xs text-yellow-400 ml-2">🔒 Locked (Free Plan)</span>
              ) : null}
            </p>

            <div className="grid grid-cols-2 sm:grid-cols-4 xl:grid-cols-1 gap-2 w-full mt-1">
              {["Eval", "Funded", "Live", "Backtest"].map((type) => (
                <button
                  key={type}
                  type="button"
                  disabled={isLocked}
                  onClick={() => setMode(type)}
                  className={
                    displayedMode === type
                      ? "w-full px-3 py-2 text-sm rounded bg-green-500 text-white"
                      : "w-full px-3 py-2 text-sm rounded bg-[#111827] hover:bg-[#1f2937] text-white"
                  }
                >
                  {type}
                </button>
              ))}
            </div>
          </div>

          {displayedMode === "Backtest" && (
            <div className="mt-3">
              <label className="text-sm text-gray-400">Strategy Name</label>
              <input
                type="text"
                value={strategy}
                onChange={(e) => setStrategy(e.target.value)}
                placeholder="e.g. NY Reversal, Liquidity Sweep"
                className="w-full mt-1 p-2 lg:p-2.5 rounded bg-black/30 text-white"
              />
            </div>
          )}

          <div
            onClick={handleClickUpload}
            onDrop={handleDrop}
            onDragOver={(e) => e.preventDefault()}
            className="border-2 border-dashed border-white/20 p-4 lg:p-5 rounded text-center cursor-pointer min-h-[96px] lg:min-h-[128px] flex items-center justify-center"
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

        <div className="bg-white/5 p-4 lg:p-5 rounded-xl border border-white/10 space-y-3 xl:space-y-3.5">
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

          <input
            placeholder="P&L"
            value={pnlFocused ? pnl : formatWithCommas(pnl)}
            onFocus={() => setPnlFocused(true)}
            onBlur={() => setPnlFocused(false)}
            onChange={(e) => {
              const raw = e.target.value.replace(/,/g, "")
              const val = handleNumberInput(raw)
              if (val !== null) setPnl(val)
            }}
            className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
          />

          {inputSettings.showRR && (
            <input
              placeholder="Risk Reward"
              value={rr}
              onChange={(e) => {
                const val = handleNumberInput(e.target.value)
                if (val !== null) setRR(val)
              }}
              className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          {inputSettings.showPoints && (
            <input
              placeholder="Points"
              value={points}
              onChange={(e) => {
                const val = handleNumberInput(e.target.value)
                if (val !== null) setPoints(val)
              }}
              className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          {inputSettings.showContracts && (
            <input
              placeholder="Contracts"
              value={contracts}
              onChange={(e) => setContracts(e.target.value)}
              className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          {inputSettings.showEntryExit && advanced && (
            <div className="grid grid-cols-1 gap-3">
              <input
                placeholder="Entry Price"
                value={entryPrice}
                onChange={(e) => {
                  const val = handleNumberInput(e.target.value)
                  if (val !== null) setEntryPrice(val)
                }}
                className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
              />
              <input
                placeholder="Exit Price"
                value={exitPrice}
                onChange={(e) => {
                  const val = handleNumberInput(e.target.value)
                  if (val !== null) setExitPrice(val)
                }}
                className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10"
              />
              <input
                type="time"
                value={entryTime}
                onChange={(e) => {
                  setEntryTimeTouched(true)
                  setEntryTime(e.target.value)
                }}
                className="w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10 [color-scheme:dark]"
              />
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

          <label className="text-gray-400 text-sm mb-1 block">
            Personal Notes
          </label>
          {inputSettings.showNotes && (
            <textarea
              placeholder="Notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full p-2 lg:p-2.5 h-24 lg:h-28 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          <div className="flex items-center justify-between mt-4 p-3 rounded-xl bg-white/5 border border-white/10">
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

          <div className="hidden lg:block">
            <button
              type="button"
              disabled={submitting}
              onClick={() => void handleSubmit()}
              className="w-full bg-blue-500 hover:bg-blue-600 p-2 rounded font-semibold disabled:opacity-60"
            >
              {submitting ? "Saving…" : isEditMode ? "Save changes" : "Add Trade"}
            </button>
          </div>
        </div>

        <div className="bg-white/5 p-4 lg:p-5 rounded-xl border border-white/10 flex flex-col gap-3 lg:gap-4 xl:gap-5">
          <p className="text-sm text-gray-400">Psychology</p>
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
          <select
            value={emotion}
            onChange={(e) => setEmotion(e.target.value)}
            className="w-full p-2 lg:p-2.5 bg-[#0f172a] border border-white/10 rounded"
          >
            <option value="">Emotion</option>
            <option>Calm</option>
            <option>FOMO</option>
            <option>Revenge</option>
          </select>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={followedPlan}
              onChange={(e) => setFollowedPlan(e.target.checked)}
            />
            Followed Plan?
          </label>
          <p className="text-sm text-gray-400 mt-0">Context</p>
          <select
            value={marketCondition}
            onChange={(e) => setMarketCondition(e.target.value)}
            className="w-full p-2 lg:p-2.5 bg-[#0f172a] border border-white/10 rounded"
          >
            <option value="">Market</option>
            <option>Trending</option>
            <option>Ranging</option>
          </select>
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
          <div className="mt-4 lg:hidden">
            <button
              type="button"
              disabled={submitting}
              onClick={() => void handleSubmit()}
              className="w-full py-3 rounded-lg bg-blue-500 hover:bg-blue-600 text-white font-semibold disabled:opacity-60"
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
      </>
    )
  }

  return (
    <>
      {formBody}
      {settingsModal}
      {popupModal}
    </>
  )
}
