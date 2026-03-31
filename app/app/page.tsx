"use client"

import Navbar from "../components/Navbar"
import { useState, useRef } from "react"
import { supabase } from "../../lib/supabaseClient"

export default function Home() {
  const [loading, setLoading] = useState(false)
  const [pnlFocused, setPnlFocused] = useState(false)
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
        exit_time: exitTime
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

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="p-12 max-w-7xl mx-auto">

          <h1 className="text-3xl font-semibold mb-6 text-center bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Input Trade
          </h1>

          <div className="flex justify-center mb-6">
            <button
              onClick={() => setAdvanced(!advanced)}
              className="bg-emerald-500 hover:bg-emerald-600 px-4 py-2 rounded font-semibold"
            >
              {advanced ? "Advanced Mode: ON" : "Advanced Mode: OFF"}
            </button>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-10">

            {/* LEFT */}
            <div className="bg-white/5 p-6 rounded-xl border border-white/10 space-y-4">

              <div onClick={() => dateRef.current?.showPicker()}>
                <input
                  ref={dateRef}
                  type="date"
                  value={tradeDate}
                  onChange={(e) => setTradeDate(e.target.value)}
                  className="w-full p-3 rounded bg-[#0f172a] border border-white/10 text-white cursor-pointer [color-scheme:dark]"
                />
              </div>

              <select value={firm} onChange={(e) => setFirm(e.target.value)} className="w-full p-3 rounded bg-[#0f172a] border border-white/10">
                <option value="">Account Type</option>
                {firmOptions.map(f => <option key={f}>{f}</option>)}
              </select>

              <select value={accountSize} onChange={(e) => setAccountSize(e.target.value)} className="w-full p-3 rounded bg-[#0f172a] border border-white/10">
                <option value="">Account Size</option>
                {(accountSizes[firm] || []).map(size => <option key={size}>{size}</option>)}
              </select>

              <input
                placeholder="Account Number"
                value={accountNumber}
                onChange={(e) => setAccountNumber(e.target.value)}
                className="w-full p-3 rounded bg-[#0f172a] border border-white/10"
              />

              <select value={ticker} onChange={(e) => setTicker(e.target.value)} className="w-full p-3 rounded bg-[#0f172a] border border-white/10">
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
    className="w-full p-3 pl-8 rounded bg-[#0f172a] border border-white/10"
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
    className="w-full p-3 pl-8 rounded bg-[#0f172a] border border-white/10"
  />
</div>

                  <div onClick={() => entryTimeRef.current?.showPicker()}>
                    <p className="text-sm text-gray-400">Entry Time</p>
                    <input
                      ref={entryTimeRef}
                      type="time"
                      value={entryTime}
                      onChange={(e) => setEntryTime(e.target.value)}
                      className="w-full p-3 rounded bg-[#0f172a] border border-white/10 cursor-pointer [color-scheme:dark]"
                    />
                  </div>

                  <div onClick={() => exitTimeRef.current?.showPicker()}>
                    <p className="text-sm text-gray-400">Exit Time</p>
                    <input
                      ref={exitTimeRef}
                      type="time"
                      value={exitTime}
                      onChange={(e) => setExitTime(e.target.value)}
                      className="w-full p-3 rounded bg-[#0f172a] border border-white/10 cursor-pointer [color-scheme:dark]"
                    />
                  </div>
                </>
              )}

              <div
                onClick={handleClickUpload}
                onDrop={handleDrop}
                onDragOver={(e) => e.preventDefault()}
                className="border-2 border-dashed border-white/20 p-6 rounded text-center cursor-pointer hover:border-blue-400"
              >
                {image ? <p>{image.name}</p> : <p>Upload Screenshot</p>}
                <input ref={fileInputRef} type="file" className="hidden" onChange={(e) => setImage(e.target.files?.[0] || null)} />
              </div>

            </div>

            {/* RIGHT */}
            <div className="bg-white/5 p-6 rounded-xl border border-white/10 space-y-4">

              <select value={direction} onChange={(e) => setDirection(e.target.value)} className="w-full p-3 rounded bg-[#0f172a] border border-white/10">
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
    className="w-full p-3 pl-10 rounded bg-[#0f172a] border border-white/10"
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
                className="w-full p-3 rounded bg-[#0f172a] border border-white/10"
              />

              <input
                type="text"
                placeholder="Points"
                value={points}
                onChange={(e) => {
                  const val = handleNumberInput(e.target.value)
                  if (val !== null) setPoints(val)
                }}
                className="w-full p-3 rounded bg-[#0f172a] border border-white/10"
              />

              <input
                type="text"
                placeholder="Contracts"
                value={contracts}
                onChange={(e) => {
                  const cleaned = e.target.value.replace(/[^0-9]/g, "")
                  setContracts(cleaned)
                }}
                className="w-full p-3 rounded bg-[#0f172a] border border-white/10"
              />

              <select value={session} onChange={(e) => setSession(e.target.value)} className="w-full p-3 rounded bg-[#0f172a] border border-white/10">
                <option>NY</option>
                <option>London</option>
                <option>Asia</option>
              </select>

              <textarea placeholder="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} className="w-full p-3 h-24 rounded bg-[#0f172a] border border-white/10" />

              <button onClick={handleSubmit} disabled={loading} className="w-full mt-4 bg-blue-500 hover:bg-blue-600 p-3 rounded font-semibold">
                {loading ? "Saving..." : "Add Trade"}
              </button>

            </div>

          </div>

        </div>
      </div>
    </>
  )
}