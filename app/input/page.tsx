"use client"

import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { Button, Modal, cn } from "@/app/components/ui"
import CustomSelect from "@/app/components/CustomSelect"
import { SELECT_TRIGGER_CLASS } from "@/lib/accountDropdownStyles"
import { useUserProfile } from "@/lib/useUserProfile"

export default function InputPage() {
  const { user } = useUserProfile()
  const [ticker, setTicker] = useState("")
  const [pnl, setPnl] = useState("")
  const [direction, setDirection] = useState("Long")
  const [session, setSession] = useState("NY")
  const [notes, setNotes] = useState("")
  const [loading, setLoading] = useState(false)
  const [popupMessage, setPopupMessage] = useState("")
  const [popupType, setPopupType] = useState<"success" | "error">("success")
  const [showPopup, setShowPopup] = useState(false)

  useEffect(() => {
    if (showPopup) {
      const timer = setTimeout(() => setShowPopup(false), 2500)
      return () => clearTimeout(timer)
    }
  }, [showPopup])

  async function handleSubmit(e: any) {
    e.preventDefault()

    setLoading(true)

    const sessionToSave = (session && String(session).trim()) || "NY"

    console.log("🚨 INSERT FUNCTION HIT 🚨", "app/input/page.tsx handleSubmit")

    const tradesToInsert = [
      {
        user_id: user?.id,
        ticker,
        pnl: Number(pnl),
        direction,
        session: sessionToSave,
        notes,
        reviewed: false,
        created_at: new Date().toISOString(),
      },
    ]

    console.log("🚨 PARSED DATA:", JSON.stringify(tradesToInsert, null, 2))
    console.log(
      "🚨 INSERT PAYLOAD:",
      JSON.stringify(tradesToInsert, null, 2)
    )

    // TEMP DEBUG: block all trade inserts — restore block below when done
    console.log("🚫 INSERT BLOCKED HERE")
    setLoading(false)
    return
    /*
    const { error } = await supabase.from("trades").insert(tradesToInsert)

    if (error) {
      console.error(error)
      setPopupMessage("Failed to save trade")
      setPopupType("error")
      setShowPopup(true)
    } else {
      setPopupMessage("Trade saved successfully")
      setPopupType("success")
      setShowPopup(true)
      setTicker("")
      setPnl("")
      setSession("NY")
      setNotes("")
    }

    setLoading(false)
    */
  }

  return (
    <>

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white flex items-center justify-center">

        <form
          onSubmit={handleSubmit}
          className="bg-white/5 backdrop-blur-md border border-white/10 rounded-xl p-8 w-full max-w-md space-y-4"
        >
          <h1 className="text-2xl font-bold text-center text-blue-300">
            Add Trade
          </h1>

          <input
            placeholder="Ticker"
            value={ticker}
            onChange={(e) => setTicker(e.target.value)}
            className="w-full p-3 bg-[#0f172a] border border-white/10 rounded"
          />

          <CustomSelect
            value={direction}
            onChange={setDirection}
            triggerClassName={SELECT_TRIGGER_CLASS}
            options={[
              { label: "Long", value: "Long" },
              { label: "Short", value: "Short" },
            ]}
          />

          <CustomSelect
            value={session}
            onChange={setSession}
            triggerClassName={SELECT_TRIGGER_CLASS}
            options={[
              { label: "NY", value: "NY" },
              { label: "London", value: "London" },
              { label: "Asia", value: "Asia" },
            ]}
          />

          <input
            placeholder="P&L"
            value={pnl}
            onChange={(e) => setPnl(e.target.value)}
            className="w-full p-3 bg-[#0f172a] border border-white/10 rounded"
          />

          <textarea
            placeholder="Notes"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            className="w-full p-3 bg-[#0f172a] border border-white/10 rounded"
          />

          <Button type="submit" variant="accent" size="lg" fullWidth disabled={loading}>
            {loading ? "Saving..." : "Save Trade"}
          </Button>

        </form>

      </div>
      <Modal
        open={showPopup}
        onClose={() => setShowPopup(false)}
        size="sm"
        panelClassName={cn(
          "text-center",
          popupType === "success"
            ? "border-green-500 bg-green-900/20"
            : "border-red-500 bg-red-900/20"
        )}
        footer={
          <Button variant="ghost" size="sm" onClick={() => setShowPopup(false)}>
            Close
          </Button>
        }
      >
        <p
          className={cn(
            "text-sm font-medium",
            popupType === "success" ? "text-green-400" : "text-red-400"
          )}
        >
          {popupMessage}
        </p>
      </Modal>
    </>
  )
}