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

    let imagePath = null

    if (image) {
      const fileName = `${Date.now()}-${image.name}`
      const { error } = await supabase.storage
        .from("screenshots")
        .upload(fileName, image)

      if (!error) imagePath = fileName
    }

    const parsedPnl = parseFloat(pnl) || 0
    const parsedRR = parseFloat(rr) || 0
    const parsedPoints = parseFloat(points) || 0
    const parsedEntry = advanced ? parseFloat(entryPrice) || 0 : null
    const parsedExit = advanced ? parseFloat(exitPrice) || 0 : null
    const parsedContracts = parseInt(contracts, 10) || 0

    await supabase.from("trades").insert([
  {
    ticker,
    direction,
    pnl: parsedPnl,
    rr: parsedRR,
    points: parsedPoints,
    contracts: parsedContracts,
    session,
    notes,
    image_url: imagePath,
    account_type: firm,
    account_size: accountSize,
    account_id: accountNumber,
    user_id: user?.id,
    created_at: new Date(tradeDate + "T12:00:00"),
    entry_price: parsedEntry,
    exit_price: parsedExit,
    entry_time: entryTime,
    exit_time: exitTime,

    // 🔥 ADD THIS BLOCK
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
        <div className="p-12 max-w-7xl mx-auto">

          <h1 className="text-3xl font-semibold mb-6 text-center bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Input Trade
            
          </h1>
          <div className="flex justify-center mb-6 gap-4">

  
  


</div>
          <div className="flex justify-center mb-6">
            <button
              onClick={() => setAdvanced(!advanced)}
              className="bg-emerald-500 hover:bg-emerald-600 px-4 py-2 rounded font-semibold"
            >
              {advanced ? "Advanced Mode: ON" : "Advanced Mode: OFF"}
            </button>
          </div>

          <div className="flex gap-2 mb-4">

  {/* Upload CSV */}
  <button
    onClick={() => csvInputRef.current?.click()}
    className="bg-blue-500 hover:bg-blue-600 px-4 py-2 rounded font-semibold"
  >
    Upload CSV
  </button>

  {/* Review CSV Inputs */}
  <button
  onClick={() => window.location.href = "/review"}
  className="relative bg-emerald-500 hover:bg-emerald-600 px-4 py-2 rounded font-semibold"
>
  Review CSV Inputs

  {reviewCount > 0 && (
    <span className="absolute -top-2 -right-2 bg-red-500 text-white text-xs font-bold px-2 py-0.5 rounded-full">
      {reviewCount > 99 ? "99+" : reviewCount}
    </span>
  )}
</button>

</div>

  <input
    ref={csvInputRef}
    type="file"
    accept=".csv"
    className="hidden"
    onChange={handleCSVUpload}
  />
          

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">

            {/* LEFT */}
            <div className="bg-white/5 p-4 rounded-xl border border-white/10 space-y-4">

              <div onClick={() => dateRef.current?.showPicker()}>
                <input
                  ref={dateRef}
                  type="date"
                  value={tradeDate}
                  onChange={(e) => setTradeDate(e.target.value)}
                  className="w-full p-2 rounded bg-[#0f172a] border border-white/10 text-white cursor-pointer [color-scheme:dark]"
                />
              </div>

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

              {advanced && (
                <>
                  <div className="relative">
  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
    $
  </span>
  <input
    type="text"
    placeholder="Entry Price"
    value={formatWithCommas(entryPrice)}
    onChange={(e) => {
      const raw = e.target.value.replace(/,/g, "")
      const val = handleNumberInput(raw)
      if (val !== null) setEntryPrice(val)
    }}
    className="w-full p-2 pl-8 rounded bg-[#0f172a] border border-white/10"
  />
</div>

                  <div className="relative">
  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
    $
  </span>
  <input
    type="text"
    placeholder="Exit Price"
    value={formatWithCommas(exitPrice)}
    onChange={(e) => {
      const raw = e.target.value.replace(/,/g, "")
      const val = handleNumberInput(raw)
      if (val !== null) setExitPrice(val)
    }}
    className="w-full p-2 pl-8 rounded bg-[#0f172a] border border-white/10"
  />
</div>

                  <div onClick={() => entryTimeRef.current?.showPicker()}>
                    <p className="text-sm text-gray-400">Entry Time</p>
                    <input
                      ref={entryTimeRef}
                      type="time"
                      value={entryTime}
                      onChange={(e) => setEntryTime(e.target.value)}
                      className="w-full p-2 rounded bg-[#0f172a] border border-white/10 cursor-pointer [color-scheme:dark]"
                    />
                  </div>

                  <div onClick={() => exitTimeRef.current?.showPicker()}>
                    <p className="text-sm text-gray-400">Exit Time</p>
                    <input
                      ref={exitTimeRef}
                      type="time"
                      value={exitTime}
                      onChange={(e) => setExitTime(e.target.value)}
                      className="w-full p-2 rounded bg-[#0f172a] border border-white/10 cursor-pointer [color-scheme:dark]"
                    />
                  </div>
                </>
              )}

              <div
                onClick={handleClickUpload}
                onDrop={handleDrop}
                onDragOver={(e) => e.preventDefault()}
                className="border-2 border-dashed border-white/20 p-4 rounded text-center cursor-pointer hover:border-blue-400"
              >
                {image ? <p>{image.name}</p> : <p>Upload Screenshot</p>}
                <input ref={fileInputRef} type="file" className="hidden" onChange={(e) => setImage(e.target.files?.[0] || null)} />
              </div>
              
            </div>
              
            {/* RIGHT */}
            <div className="bg-white/5 p-4 rounded-xl border border-white/10 space-y-4">

              <select value={direction} onChange={(e) => setDirection(e.target.value)} className="w-full p-2 rounded bg-[#0f172a] border border-white/10">
                <option>Long</option>
                <option>Short</option>
              </select>

              <div className="relative">
  {pnl.startsWith("-") && (
    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
      -
    </span>
  )}

  <span className="absolute left-6 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
    $
  </span>

  <input
    type="text"
    placeholder="P&L"
    value={
      pnlFocused
        ? pnl.startsWith("-") ? pnl.slice(1) : pnl
        : formatWithCommas(
            pnl.startsWith("-") ? pnl.slice(1) : pnl
          )
    }
    onFocus={() => setPnlFocused(true)}
    onBlur={() => setPnlFocused(false)}
    onChange={(e) => {
      let raw = e.target.value.replace(/,/g, "")

      if (pnl.startsWith("-")) raw = "-" + raw

      const cleaned = handleNumberInput(raw)
      if (cleaned !== null) setPnl(cleaned)
    }}
    className="w-full p-2 pl-10 rounded bg-[#0f172a] border border-white/10"
  />
</div>

              <input
                type="text"
                placeholder="Risk Reward"
                value={rr}
                onChange={(e) => {
                  const val = handleNumberInput(e.target.value)
                  if (val !== null) setRR(val)
                }}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
              />

              <input
                type="text"
                placeholder="Points"
                value={points}
                onChange={(e) => {
                  const val = handleNumberInput(e.target.value)
                  if (val !== null) setPoints(val)
                }}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
              />

              <input
                type="text"
                placeholder="Contracts"
                value={contracts}
                onChange={(e) => {
                  const cleaned = e.target.value.replace(/[^0-9]/g, "")
                  setContracts(cleaned)
                }}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
              />

              <select value={session} onChange={(e) => setSession(e.target.value)} className="w-full p-2 rounded bg-[#0f172a] border border-white/10">
                <option>NY</option>
                <option>London</option>
                <option>Asia</option>
              </select>

              <textarea placeholder="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} className="w-full p-2 h-24 rounded bg-[#0f172a] border border-white/10" />
              <div className="space-y-3">

  <p className="text-sm text-gray-400">Psychology</p>

  <select
    value={confidence}
    onChange={(e) => setConfidence(e.target.value)}
    className="w-full p-2 bg-[#0f172a] border border-white/10 rounded"
  >
    <option value="">Confidence (1-5)</option>
    <option value="1">1 - Very Low</option>
    <option value="2">2</option>
    <option value="3">3</option>
    <option value="4">4</option>
    <option value="5">5 - Very High</option>
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
    <option>Fear</option>
    <option>Confident</option>
  </select>

  <select
    value={mistakeType}
    onChange={(e) => setMistakeType(e.target.value)}
    className="w-full p-2 bg-[#0f172a] border border-white/10 rounded"
  >
    <option value="">Mistake Type</option>
    <option>None</option>
    <option>Overtrading</option>
    <option>Early Entry</option>
    <option>Late Exit</option>
    <option>No Stop Loss</option>
  </select>

  <label className="flex items-center gap-2 text-sm">
    <input
      type="checkbox"
      checked={followedPlan}
      onChange={(e) => setFollowedPlan(e.target.checked)}
    />
    Followed Rules?
  </label>

</div>
<div className="space-y-3 mt-4">

  <p className="text-sm text-gray-400">Context</p>

  <select
    value={marketCondition}
    onChange={(e) => setMarketCondition(e.target.value)}
    className="w-full p-2 bg-[#0f172a] border border-white/10 rounded"
  >
    <option value="">Market Condition</option>
    <option>Trending</option>
    <option>Ranging</option>
    <option>Choppy</option>
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
    <option>1h</option>
  </select>

  <label className="flex items-center gap-2 text-sm">
    <input
      type="checkbox"
      checked={newsEvent}
      onChange={(e) => setNewsEvent(e.target.checked)}
    />
    News Event?
  </label>

</div>
              <button onClick={handleSubmit} disabled={loading} className="w-full mt-4 bg-blue-500 hover:bg-blue-600 p-2 rounded font-semibold">
                {loading ? "Saving..." : "Add Trade"}
              </button>

            </div>

          </div>

        </div>
      </div>
    </>
  )
}