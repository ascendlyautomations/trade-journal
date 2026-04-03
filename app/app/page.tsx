"use client"

import Navbar from "../components/Navbar"
import { useState, useRef, useEffect } from "react"
import Papa from "papaparse"
import { supabase } from "../../lib/supabaseClient"

export default function Home() {
  const [loading, setLoading] = useState(false)
  const [pnlFocused, setPnlFocused] = useState(false)
  const [reviewCount, setReviewCount] = useState(0)
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
  useEffect(() => {
  fetchReviewCount()
}, [])
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
  
  // 🔥 INPUT VALIDATION FIX
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
  
  const [image, setImage] = useState<File | null>(null)

  const [firm, setFirm] = useState("")
  const [accountSize, setAccountSize] = useState("")
  const [accountNumber, setAccountNumber] = useState("")

  const firmOptions = [
    "Alpha Futures",
    "Apex",
    "Topstep",
    "Goat Funded Futures",
    "Live Account"
  ]

  const accountSizes: Record<string, string[]> = {
    "Alpha Futures": ["25K", "50K", "100K", "150K"],
    Apex: ["25K", "50K", "75K", "100K", "150K", "300K"],
    Topstep: ["50K", "100K", "150K"],
    "Goat Funded Futures": ["25K", "50K", "100K", "150K"],
    "Live Account": ["Custom"]
  }

  const [advanced, setAdvanced] = useState(false)

  const [entryPrice, setEntryPrice] = useState("")
  const [exitPrice, setExitPrice] = useState("")
  const [contracts, setContracts] = useState("")
  const [entryTime, setEntryTime] = useState("")
  const [exitTime, setExitTime] = useState("")
  const [screenshot, setScreenshot] = useState<File | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const csvInputRef = useRef<HTMLInputElement>(null)
  const dateRef = useRef<HTMLInputElement>(null)
  const entryTimeRef = useRef<HTMLInputElement>(null)
  const exitTimeRef = useRef<HTMLInputElement>(null)

  const symbols = ["MNQ", "MES", "MGC", "MCL", "MYM", "M2K"]

  async function handleSubmit() {
    if (loading) return
    setLoading(true)
    
    const {
      data: { user }
    } = await supabase.auth.getUser()

    let screenshotUrl = null

if (image) {
  const fileName = `${user.id}/${Date.now()}-${image.name}`

  const { error } = await supabase.storage
    .from("screenshots")
    .upload(fileName, image)

  if (error) {
    console.error("Upload error:", error)
  } else {
    screenshotUrl = fileName // ✅ THIS IS THE FIX
  }
}

    const parsedPnl = parseFloat(pnl) || 0
    const parsedRR = parseFloat(rr) || 0
    const parsedPoints = parseFloat(points) || 0
    const parsedEntry = advanced ? parseFloat(entryPrice) || 0 : null
    const parsedExit = advanced ? parseFloat(exitPrice) || 0 : null
    const parsedContracts = parseInt(contracts, 10) || 0

    const now = new Date()

    // Check if selected date is today
    const selectedDateObj = new Date(tradeDate + "T00:00:00")
    const isToday =
      selectedDateObj.toDateString() === now.toDateString()

    let finalDate: Date

    if (entryTime) {
      // Use selected date + entry time
      finalDate = new Date(`${tradeDate}T${entryTime}:00`)
    } else if (isToday) {
      // Use current time if today and no entry time
      finalDate = now
    } else {
      // Default fallback → 4:00 PM
      finalDate = new Date(`${tradeDate}T16:00:00`)
    }

    const sessionToSave = (session && String(session).trim()) || "NY"
    const tradeTypeToSave =
      tradeType != null && String(tradeType).trim() !== ""
        ? String(tradeType).trim()
        : null

    await supabase.from("trades").insert([
  {
    ticker,
    direction,
    pnl: parsedPnl,
    rr: parsedRR,
    points: parsedPoints,
    contracts: parsedContracts,
    session: sessionToSave,
    notes,
    image_url: screenshotUrl,
    account_type: firm,
    account_size: accountSize,
    account_id: accountNumber,
    user_id: user?.id,
    created_at: finalDate.toISOString(),
    entry_price: parsedEntry,
    exit_price: parsedExit,
    entry_time: entryTime,
    exit_time: exitTime,
    psychology_notes: psychologyNotes != null && String(psychologyNotes).trim() !== "" ? String(psychologyNotes).trim() : null,
    trade_type: tradeTypeToSave,

    confidence: confidence ? Number(confidence) : null,
    emotion: emotion || null,
    followed_plan: followedPlan,
    mistake_type: mistakeType || null,
    market_condition: marketCondition || null,
    news_event: newsEvent,
    timeframe: timeframe || null,

      }
    ])
    

    setTicker("")
    setDirection("Long")
    setPnl("")
    setRR("")
    setPoints("")
    setSession("NY")
    setNotes("")
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
    alert("Trade saved!")
    setLoading(false)
  }

  function handleDrop(e: React.DragEvent<HTMLDivElement>) {
    e.preventDefault()
    const file = e.dataTransfer.files[0]
    if (file) setImage(file)
  }

  function handleClickUpload() {
    fileInputRef.current?.click()
  }
  async function handleCSVUpload(e: any) {
  const file = e.target.files[0]
  if (!file) return

  setLoading(true)
  
  const {
    data: { user }
  } = await supabase.auth.getUser()

  Papa.parse(file, {
    header: true,
    skipEmptyLines: true,
    complete: async (results: any) => {
      try {
        const rows = results.data

        const formattedTrades = rows.map((row: any) => ({
          user_id: user?.id,
          ticker: row.Symbol || row.symbol || "",
          pnl: Number(row.PnL || row.pnl || 0),
          direction: row.Side || row.side || "Long",
          rr: Number(row.RR || row.rr || 0),
          points: Number(row.Points || row.points || 0),
          contracts: Number(row.Contracts || 0),
          session: row.Session || "NY",
          notes: "",
          image_url: null,
          account_type: "Imported",
          account_size: "",
          account_id: "",
          reviewed: false,
          created_at: row.Date
            ? new Date(row.Date).toISOString()
            : new Date().toISOString()
        }))

        const chunkSize = 100

        for (let i = 0; i < formattedTrades.length; i += chunkSize) {
          const chunk = formattedTrades.slice(i, i + chunkSize)

          const { error } = await supabase
            .from("trades")
            .insert(chunk)

          if (error) {
            console.error(error)
            alert("Error uploading trades")
            setLoading(false)
            return
          }
        }

        alert(`Uploaded ${formattedTrades.length} trades 🚀`)
        fetchReviewCount()
      } catch (err) {
        console.error(err)
        alert("CSV processing failed")
      }

      setLoading(false)
    },
  })
}

async function fetchReviewCount() {
  const {
    data: { user }
  } = await supabase.auth.getUser()

  const { count } = await supabase
    .from("trades")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user?.id)
    .eq("reviewed", false)

  setReviewCount(count || 0)
}
return (
  <>
    <Navbar />

    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
      <div className="p-10 max-w-7xl mx-auto">

        <h1 className="text-3xl font-semibold mb-6 text-center bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          Input Trade
        </h1>

        {/* Toggle */}
        <div className="flex items-center justify-between mb-6 flex-wrap gap-4">

  {/* LEFT SIDE */}
  <div className="w-full flex items-center mb-6">

  {/* LEFT GROUP */}
  <div className="flex gap-2">
    <button
      onClick={() => csvInputRef.current?.click()}
      className="bg-blue-500 px-4 py-2 rounded"
    >
      Upload CSV
    </button>

    <button
      onClick={() => window.location.href = "/review"}
      className="relative bg-emerald-500 px-4 py-2 rounded"
    >
      Review CSV Inputs
      {reviewCount > 0 && (
    <span className="absolute -top-2 -right-2 bg-red-500 text-white text-xs px-2 py-0.5 rounded-full">
      {reviewCount > 99 ? "99+" : reviewCount}
    </span>
  )}
    </button>

    <button
      onClick={() => setAdvanced(!advanced)}
      className="bg-emerald-500 px-4 py-2 rounded"
    >
      {advanced ? "Advanced Mode: ON" : "Advanced Mode: OFF"}
    </button>
  </div>

  {/* RIGHT BUTTON */}
  <button
    onClick={() => setShowSettings(true)}
    className="ml-auto bg-gray-700 hover:bg-gray-600 px-4 py-2 rounded"
  >
    ⚙️ Settings
  </button>


</div>

</div>

        <input
          ref={csvInputRef}
          type="file"
          accept=".csv"
          className="hidden"
          onChange={handleCSVUpload}
        />

        {/* GRID */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">

          {/* LEFT */}
          <div className="bg-white/5 p-4 rounded-xl border border-white/10 space-y-2">

            <input
              ref={dateRef}
              type="date"
              
              value={tradeDate}
          
              onChange={(e) => setTradeDate(e.target.value)}
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10 text-white [color-scheme:dark]"
            />

            <select value={firm} onChange={(e) => setFirm(e.target.value)} className="w-full p-2 rounded bg-[#0f172a] border border-white/10">
              <option value="">Account Type</option>
              {firmOptions.map(f => <option key={f}>{f}</option>)}
            </select>

            <select value={accountSize} onChange={(e) => setAccountSize(e.target.value)} className="w-full p-2 rounded bg-[#0f172a] border border-white/10">
              <option value="">Account Size</option>
              {(accountSizes[firm] || []).map(size => <option key={size}>{size}</option>)}
            </select>

            <input
              placeholder="Account Number"
              value={accountNumber}
              onChange={(e) => setAccountNumber(e.target.value)}
              className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
            />

            <select value={ticker} onChange={(e) => setTicker(e.target.value)} className="w-full p-2 rounded bg-[#0f172a] border border-white/10">
              <option value="">Select Symbol</option>
              {symbols.map(s => <option key={s}>{s}</option>)}
            </select>
            <p className="text-sm text-gray-400 mt-2">Account Traded</p>

<div className="flex gap-2">
  {["Eval", "Funded", "Live"].map((type) => (
    <button
      key={type}
      onClick={() => setTradeType(type)}
      className={`px-3 py-1 rounded text-sm font-medium border transition ${
        tradeType === type
          ? "bg-emerald-500 border-emerald-400 text-white"
          : "bg-[#0f172a] border-white/10 text-gray-300 hover:border-emerald-400"
      }`}
    >
      {type}
    </button>
  ))}
</div>

            <div
              onClick={handleClickUpload}
              onDrop={handleDrop}
              onDragOver={(e) => e.preventDefault()}
              className="border-2 border-dashed border-white/20 p-4 rounded text-center cursor-pointer"
            >
              {image ? <p>{image.name}</p> : <p>Upload Screenshot</p>}
              <input
  ref={fileInputRef}
  type="file"
  className="hidden"
  onChange={(e) => {
    const file = e.target.files?.[0]
    if (file) setImage(file)
  }}
/>
            </div>

          </div>

          {/* MIDDLE */}
          {/* MIDDLE */}
<div className="bg-white/5 p-4 rounded-xl border border-white/10 space-y-2">

  <select value={direction} onChange={(e) => setDirection(e.target.value)} className="w-full p-2 rounded bg-[#0f172a] border border-white/10">
    <option>Long</option>
    <option>Short</option>
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

  {/* ADVANCED */}
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

  {inputSettings.showNotes && (
    <textarea
      placeholder="Notes"
      value={notes}
      onChange={(e) => setNotes(e.target.value)}
      className="w-full p-2 h-20 rounded bg-[#0f172a] border border-white/10"
    />
  )}

  <button
    onClick={handleSubmit}
    className="w-full bg-blue-500 hover:bg-blue-600 p-2 rounded font-semibold"
  >
    Add Trade
  </button>

</div>

          {/* RIGHT */}
          <div className="bg-white/5 p-4 rounded-xl border border-white/10 space-y-3">

            <p className="text-sm text-gray-400">Psychology</p>

            <select value={confidence} onChange={(e) => setConfidence(e.target.value)} className="w-full p-2 bg-[#0f172a] border border-white/10 rounded">
              <option value="">Confidence (bad to great)</option>
              <option>1</option><option>2</option><option>3</option><option>4</option><option>5</option>
            </select>

            <select value={emotion} onChange={(e) => setEmotion(e.target.value)} className="w-full p-2 bg-[#0f172a] border border-white/10 rounded">
              <option value="">Emotion</option>
              <option>Calm</option>
              <option>FOMO</option>
              <option>Revenge</option>
            </select>

            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={followedPlan} onChange={(e) => setFollowedPlan(e.target.checked)} />
              Followed Plan?
            </label>

            <p className="text-sm text-gray-400 mt-4">Context</p>

            <select value={marketCondition} onChange={(e) => setMarketCondition(e.target.value)} className="w-full p-2 bg-[#0f172a] border border-white/10 rounded">
              <option value="">Market</option>
              <option>Trending</option>
              <option>Ranging</option>
            </select>

            <select value={timeframe} onChange={(e) => setTimeframe(e.target.value)} className="w-full p-2 bg-[#0f172a] border border-white/10 rounded">
              <option value="">Timeframe</option>
              <option>1m</option>
              <option>5m</option>
              <option>15m</option>
            </select>

            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={newsEvent} onChange={(e) => setNewsEvent(e.target.checked)} />
              News Event?
            </label>
            <p className="text-sm text-gray-400 mt-4">Psychology Notes</p>

<textarea
  placeholder="What were you thinking in the moment?"
  value={psychologyNotes}
  onChange={(e) => setPsychologyNotes(e.target.value)}
  className="w-full p-2 h-24 rounded bg-[#0f172a] border border-white/10 text-white"
/>

          </div>

        </div>

      </div>
    </div>
    {showSettings && (
  <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">

    <div className="bg-[#0f172a] border border-white/10 rounded-xl p-6 w-[400px] space-y-4">

      <h2 className="text-lg font-semibold text-white">Input Settings</h2>

      {Object.entries(inputSettings).map(([key, value]) => (
        <div key={key} className="flex items-center justify-between">

          <span className="text-sm text-gray-300 capitalize">
            {key.replace("show", "")}
          </span>

          <button
            onClick={() =>
              setInputSettings((prev) => ({
                ...prev,
                [key]: !prev[key],
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
        onClick={() => setShowSettings(false)}
        className="w-full bg-blue-500 hover:bg-blue-600 py-2 rounded font-semibold mt-4"
      >
        Done
      </button>

    </div>
  </div>
)}
  </>
)
}