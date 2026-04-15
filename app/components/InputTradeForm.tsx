"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { supabase } from "@/lib/supabaseClient"
import { isProActive } from "@/lib/subscription"

function tradeAccountKey(
  accountType: string | null | undefined,
  accountSize: string | null | undefined,
  accountId: string | null | undefined
): string {
  return `${String(accountType ?? "")
    .toLowerCase()
    .trim()}-${String(accountSize ?? "").trim()}-${String(accountId ?? "").trim()}`
}

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

function tradeDateFromRow(t: any): string {
  if (t?.created_at) return String(t.created_at).split("T")[0]
  if (t?.date) return String(t.date).split("T")[0]
  return getESTDate()
}

export default function InputTradeForm({
  existingTrade,
  onSave,
  onClose,
}: InputTradeFormProps) {
  const isEditMode = Boolean(existingTrade?.id)
  const showAsModal = isEditMode && Boolean(onClose)

  const [submitting, setSubmitting] = useState(false)
  const [pnlFocused, setPnlFocused] = useState(false)
  const [confidence, setConfidence] = useState("")
  const [psychologyNotes, setPsychologyNotes] = useState("")
  const [tradeType, setTradeType] = useState("")
  const [showSettings, setShowSettings] = useState(false)

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

  const fileInputRef = useRef<HTMLInputElement>(null)
  const dateRef = useRef<HTMLInputElement>(null)

  const symbols = ["MNQ", "MES", "MGC", "MCL", "MYM", "M2K"]

  const [planProfile, setPlanProfile] = useState<{
    is_pro?: boolean | null
    subscription_status?: string | null
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
      .select("is_pro, subscription_status")
      .eq("id", user.id)
      .maybeSingle()
    setPlanProfile(prof ?? null)
    if (isProActive(prof)) {
      setAccountFieldsLocked(false)
      return
    }
    const { data: rows } = await supabase
      .from("trades")
      .select("account_type, account_size, account_id")
      .eq("user_id", user.id)
      .neq("mode", "backtest")
    const keys = new Set(
      (rows ?? []).map((t) =>
        tradeAccountKey(t.account_type, t.account_size, t.account_id)
      )
    )
    setAccountFieldsLocked(keys.size >= 1)
  }, [])

  useEffect(() => {
    void refreshPlanAndAccountLock()
  }, [refreshPlanAndAccountLock, existingTrade?.id])

  useEffect(() => {
    if (isEditMode || mode === "Backtest" || !accountFieldsLocked) return
    let cancelled = false
    void (async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user?.id || cancelled) return
      const { data: rows } = await supabase
        .from("trades")
        .select("account_type, account_size, account_id, account_name")
        .eq("user_id", user.id)
        .neq("mode", "backtest")
        .order("created_at", { ascending: false })
        .limit(1)
      const first = rows?.[0]
      if (!first || cancelled) return
      setMode(modeLabelFromDb(first.account_type))
      setAccountSize(first.account_size != null ? String(first.account_size) : "")
      setAccountNumber(first.account_id != null ? String(first.account_id) : "")
      setFirm(first.account_name != null ? String(first.account_name) : "")
    })()
    return () => {
      cancelled = true
    }
  }, [isEditMode, mode, accountFieldsLocked, existingTrade?.id])

  const accountInputsDisabled =
    accountFieldsLocked && mode !== "Backtest" && !isProActive(planProfile)

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
    setFirm(firmFromLegacy)
    setAccountSize(t.account_size ?? "")
    setAccountNumber(t.account_id ?? "")
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
    setAdvanced(
      Boolean(
        (t.entry_price != null && t.entry_price !== "") ||
          (t.exit_price != null && t.exit_price !== "") ||
          t.entry_time ||
          t.exit_time
      )
    )
  }, [existingTrade?.id])

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
      alert("Please log in first")
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

    const now = new Date()
    const selectedDateObj = new Date(tradeDate + "T00:00:00")
    const isToday = selectedDateObj.toDateString() === now.toDateString()

    let finalDate: Date
    if (entryTime) {
      finalDate = new Date(`${tradeDate}T${entryTime}:00`)
    } else if (isToday) {
      finalDate = now
    } else {
      finalDate = new Date(`${tradeDate}T16:00:00`)
    }

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
      .select("is_pro, subscription_status")
      .eq("id", user.id)
      .maybeSingle()
    const userIsPro = isProActive(profileRow)

    const modeLowerForLimit = mode.toLowerCase()
    if (modeLowerForLimit !== "backtest") {
      const newKey = tradeAccountKey(
        modeLowerForLimit,
        accountSize || "",
        accountNumber || ""
      )
      let accQuery = supabase
        .from("trades")
        .select("id, account_type, account_size, account_id")
        .eq("user_id", user.id)
        .neq("mode", "backtest")
      if (isEditMode && existingTrade?.id) {
        accQuery = accQuery.neq("id", existingTrade.id)
      }
      const { data: existingTrades } = await accQuery
      const uniqueAccounts = new Set(
        (existingTrades ?? []).map((t) =>
          tradeAccountKey(t.account_type, t.account_size, t.account_id)
        )
      )
      if (!userIsPro && !uniqueAccounts.has(newKey) && uniqueAccounts.size >= 1) {
        alert(
          "Free plan allows only 1 account. Upgrade to Pro for unlimited accounts."
        )
        setSubmitting(false)
        return
      }
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
        account_name: firmToSave,
        account_type: mode.toLowerCase(),
        mode: mode.toLowerCase(),
        strategy:
          mode === "Backtest" && String(strategy).trim() !== ""
            ? String(strategy).trim()
            : null,
        account_size: accountSize || null,
        account_id: accountNumber || null,
        created_at: finalDate.toISOString(),
        entry_price:
          entryVal !== null && Number.isFinite(entryVal) ? entryVal : null,
        exit_price:
          exitVal !== null && Number.isFinite(exitVal) ? exitVal : null,
        entry_time: entryTime || null,
        exit_time: exitTime || null,
        psychology_notes: psychologyVal,
        trade_type: tradeTypeToSave,
        confidence: confidence ? Number(confidence) : null,
        emotion: emotion || null,
        followed_plan: followedPlan,
        mistake_type: mistakeType || null,
        market_condition: marketCondition || null,
        news_event: newsEvent,
        timeframe: timeframe || null,
      }

      const { error } = await supabase
        .from("trades")
        .update(updateRow)
        .eq("id", existingTrade.id)

      if (error) {
        console.error("UPDATE ERROR:", error)
        const msg = String(error.message || "")
        if (msg.includes("FREE_PLAN_ACCOUNT_LIMIT")) {
          alert(
            "Free plan allows only 1 account. Upgrade to Pro for unlimited accounts."
          )
        } else {
          alert("Failed to update trade.")
        }
      } else {
        void refreshPlanAndAccountLock()
        onSave?.()
        onClose?.()
        alert("Trade updated!")
      }
      setSubmitting(false)
      return
    }

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
        account_name: firmToSave,
        account_type: mode.toLowerCase(),
        mode: mode.toLowerCase(),
        strategy:
          mode === "Backtest" && String(strategy).trim() !== ""
            ? String(strategy).trim()
            : null,
        account_size: accountSize,
        account_id: accountNumber,
        user_id: user.id,
        created_at: finalDate.toISOString(),
        entry_price: parsedEntry,
        exit_price: parsedExit,
        entry_time: entryTime,
        exit_time: exitTime,
        psychology_notes: psychologyVal,
        trade_type: tradeTypeToSave,
        confidence: confidence ? Number(confidence) : null,
        emotion: emotion || null,
        followed_plan: followedPlan,
        mistake_type: mistakeType || null,
        market_condition: marketCondition || null,
        news_event: newsEvent,
        timeframe: timeframe || null,
      },
    ]

    const { data: newTradeData, error } = await supabase
      .from("trades")
      .insert(tradesToInsert)
      .select()
      .single()

    if (error) {
      console.error("Trade insert error:", error)
      const msg = String(error.message || "")
      if (msg.includes("FREE_PLAN_ACCOUNT_LIMIT")) {
        alert(
          "Free plan allows only 1 account. Upgrade to Pro for unlimited accounts."
        )
      } else {
        alert("Failed to save trade. Please try again.")
      }
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
    alert("Trade saved!")
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

  const formBody = (
    <>
      <div className="flex items-center justify-between mb- flex-wrap gap-4">
        <div className="w-full flex items-center mb-6 flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setAdvanced(!advanced)}
            className="bg-emerald-500 px-4 py-2 rounded"
          >
            {advanced ? "Advanced Mode: ON" : "Advanced Mode: OFF"}
          </button>
          <button
            type="button"
            onClick={() => setShowSettings(true)}
            className="ml-auto bg-gray-700 hover:bg-gray-600 px-4 py-2 rounded"
          >
            ⚙️ Settings
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="bg-white/5 p-4 rounded-xl border border-white/10 space-y-2">
          <input
            ref={dateRef}
            type="date"
            value={tradeDate}
            onChange={(e) => setTradeDate(e.target.value)}
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10 text-white [color-scheme:dark]"
          />

          {accountInputsDisabled ? (
            <p className="text-xs text-amber-400/90">
              Free plan: account details are locked to your existing prop firm. Upgrade
              to Pro for unlimited accounts.
            </p>
          ) : null}

          <select
            value={firm}
            onChange={(e) => setFirm(e.target.value)}
            disabled={accountInputsDisabled}
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <option value="">Account Type</option>
            {firmOptions.map((f) => (
              <option key={f}>{f}</option>
            ))}
          </select>

          <select
            value={accountSize}
            onChange={(e) => setAccountSize(e.target.value)}
            disabled={accountInputsDisabled}
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <option value="">Account Size</option>
            {(accountSizes[firm] || []).map((size) => (
              <option key={size}>{size}</option>
            ))}
          </select>

          <input
            placeholder="Account Number"
            value={accountNumber}
            onChange={(e) => setAccountNumber(e.target.value)}
            disabled={accountInputsDisabled}
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          />

          <input
            list="trade-symbol-options"
            placeholder="Symbol / ticker"
            value={ticker}
            onChange={(e) => setTicker(e.target.value)}
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
          />
          <datalist id="trade-symbol-options">
            {symbols.map((s) => (
              <option key={s} value={s} />
            ))}
          </datalist>
          <p className="text-sm text-gray-400 mt-2">Mode</p>

          <div className="flex gap-2">
            {["Eval", "Funded", "Live", "Backtest"].map((type) => (
              <button
                key={type}
                type="button"
                onClick={() => setMode(type)}
                className={`px-3 py-1 rounded text-sm font-medium border transition ${
                  mode === type
                    ? "bg-emerald-500 border-emerald-400 text-white"
                    : "bg-[#0f172a] border-white/10 text-gray-300 hover:border-emerald-400"
                }`}
              >
                {type}
              </button>
            ))}
          </div>

          {mode === "Backtest" && (
            <div className="mt-2">
              <label className="text-sm text-gray-400">Strategy Name</label>
              <input
                type="text"
                value={strategy}
                onChange={(e) => setStrategy(e.target.value)}
                placeholder="e.g. NY Reversal, Liquidity Sweep"
                className="w-full mt-1 p-2 rounded bg-black/30 text-white"
              />
            </div>
          )}

          <div
            onClick={handleClickUpload}
            onDrop={handleDrop}
            onDragOver={(e) => e.preventDefault()}
            className="border-2 border-dashed border-white/20 p-4 rounded text-center cursor-pointer"
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

        <div className="bg-white/5 p-4 rounded-xl border border-white/10 space-y-2">
          <select
            value={direction}
            onChange={(e) => setDirection(e.target.value)}
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
          >
            <option>Long</option>
            <option>Short</option>
          </select>

          <select
            value={session}
            onChange={(e) => setSession(e.target.value)}
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
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
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
          />

          {inputSettings.showRR && (
            <input
              placeholder="Risk Reward"
              value={rr}
              onChange={(e) => {
                const val = handleNumberInput(e.target.value)
                if (val !== null) setRR(val)
              }}
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
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
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          {inputSettings.showContracts && (
            <input
              placeholder="Contracts"
              value={contracts}
              onChange={(e) => setContracts(e.target.value)}
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          {inputSettings.showEntryExit && advanced && (
            <>
              <input
                placeholder="Entry Price"
                value={entryPrice}
                onChange={(e) => {
                  const val = handleNumberInput(e.target.value)
                  if (val !== null) setEntryPrice(val)
                }}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
              />
              <input
                placeholder="Exit Price"
                value={exitPrice}
                onChange={(e) => {
                  const val = handleNumberInput(e.target.value)
                  if (val !== null) setExitPrice(val)
                }}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
              />
              <input
                type="time"
                value={entryTime}
                onChange={(e) => setEntryTime(e.target.value)}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10 [color-scheme:dark]"
              />
              <input
                type="time"
                value={exitTime}
                onChange={(e) => setExitTime(e.target.value)}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10 [color-scheme:dark]"
              />
            </>
          )}

          <div className="mt-1">
            <label className="text-gray-400 text-sm mb-1 block">
              Public Description
            </label>
            <textarea
              value={publicDescription}
              onChange={(e) => setPublicDescription(e.target.value)}
              placeholder="Insert public thoughts..."
              className="w-full p-2 rounded-lg bg-[#0f172a] text-white border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[80px]"
            />
          </div>

          <label className="text-gray-400 text-sm mb-1 block">
            Personal Thoughts
          </label>
          {inputSettings.showNotes && (
            <textarea
              placeholder="Notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full p-2 h-20 rounded bg-[#0f172a] border border-white/10"
            />
          )}

          {!isEditMode && (
            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={postToFeed}
                onChange={(e) => setPostToFeed(e.target.checked)}
              />
              Share to Feed
            </label>
          )}

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

        <div className="bg-white/5 p-4 rounded-xl border border-white/10 flex flex-col gap-3 md:gap-4">
          <p className="text-sm text-gray-400">Psychology</p>
          <select
            value={confidence}
            onChange={(e) => setConfidence(e.target.value)}
            className="w-full p-2 bg-[#0f172a] border border-white/10 rounded"
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
            className="w-full p-2 bg-[#0f172a] border border-white/10 rounded"
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
          <p className="text-sm text-gray-400 mt-4">Context</p>
          <select
            value={marketCondition}
            onChange={(e) => setMarketCondition(e.target.value)}
            className="w-full p-2 bg-[#0f172a] border border-white/10 rounded"
          >
            <option value="">Market</option>
            <option>Trending</option>
            <option>Ranging</option>
          </select>
          <select
            value={timeframe}
            onChange={(e) => setTimeframe(e.target.value)}
            className="w-full p-2 bg-[#0f172a] border border-white/10 rounded"
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
          <p className="text-sm text-gray-400 mt-4">Psychology Notes</p>
          <textarea
            placeholder="What were you thinking in the moment?"
            value={psychologyNotes}
            onChange={(e) => setPsychologyNotes(e.target.value)}
            className="w-full p-2 h-24 rounded bg-[#0f172a] border border-white/10 text-white"
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

  if (showAsModal) {
    return (
      <>
        <div
          className="fixed inset-0 bg-black/90 z-[100] flex items-start justify-center overflow-y-auto py-8 px-4"
          onClick={() => onClose?.()}
          role="presentation"
        >
          <div
            className="bg-gradient-to-br from-[#0f172a] via-[#1e3a8a]/80 to-[#065f46]/30 text-gray-100 rounded-xl border border-white/10 p-9 w-full max-w-7xl shadow-xl my-auto"
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-modal="true"
            aria-labelledby="input-trade-modal-title"
          >
            <div className="flex justify-between items-center gap-4 mb-4">
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
      </>
    )
  }

  return (
    <>
      {formBody}
      {settingsModal}
    </>
  )
}
