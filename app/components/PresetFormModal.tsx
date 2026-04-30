"use client"

import { useState } from "react"
import { supabase } from "@/lib/supabaseClient"

type TradePreset = {
  id: string
  name: string
  values: Record<string, any>
}

type Props = {
  open: boolean
  onClose: () => void
  onSaved: (preset: TradePreset) => void
}

export default function PresetFormModal({ open, onClose, onSaved }: Props) {
  const [presetName, setPresetName] = useState("")
  const [ticker, setTicker] = useState("")
  const [direction, setDirection] = useState("Long")
  const [rr, setRR] = useState("")
  const [points, setPoints] = useState("")
  const [session, setSession] = useState("NY")
  const [confluences, setConfluences] = useState("")
  const [confidence, setConfidence] = useState("")
  const [emotion, setEmotion] = useState("")
  const [followedPlan, setFollowedPlan] = useState(false)
  const [marketCondition, setMarketCondition] = useState("")
  const [timeframe, setTimeframe] = useState("")
  const [saving, setSaving] = useState(false)

  if (!open) return null

  async function handleSavePreset() {
    const name = presetName.trim()
    if (!name) {
      alert("Please enter a preset name")
      return
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user?.id) {
      alert("Please log in first")
      return
    }

    const values = {
      ticker,
      direction,
      rr,
      points,
      session,
      confluences,
      confidence,
      emotion,
      followed_plan: followedPlan,
      market_condition: marketCondition,
      timeframe,
    }

    setSaving(true)
    const { data, error } = await supabase
      .from("presets")
      .insert({
        user_id: user.id,
        name,
        values,
      })
      .select("id, name, values")
      .single()
    setSaving(false)

    if (error) {
      console.error("preset save:", error)
      alert("Failed to save preset")
      return
    }

    if (data) onSaved(data as TradePreset)
    onClose()
  }

  return (
    <div className="fixed inset-0 z-[130] flex items-center justify-center bg-black/70 backdrop-blur-sm px-3 sm:px-4 lg:px-6">
      <div className="w-full max-w-md md:max-w-4xl xl:max-w-6xl max-h-[92vh] overflow-y-auto rounded-xl p-4 md:p-6 lg:p-7 bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 shadow-xl">
        <div className="flex items-center justify-between gap-4 mb-3">
          <h2 className="text-xl font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            New Preset
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="px-3 py-1 rounded bg-white/10 hover:bg-white/20 text-sm"
          >
            Close
          </button>
        </div>

        <div className="mb-4">
          <label className="text-sm text-gray-300 mb-1 block">Preset Name</label>
          <input
            type="text"
            value={presetName}
            onChange={(e) => setPresetName(e.target.value)}
            placeholder="e.g. NY Open Momentum"
            className="w-full p-2 rounded bg-[#0f172a] border border-white/10 text-white"
          />
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div className="p-4 rounded-xl bg-[#0b1220]/60 border border-white/5">
            <h3 className="text-sm text-gray-400 mb-2">Trade Structure</h3>
            <div className="space-y-3">
              <input
                type="text"
                placeholder="Symbol / Ticker (e.g. MNQ, ES, AAPL)"
                value={ticker}
                onChange={(e) => setTicker(e.target.value.toUpperCase())}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
              />
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
                <option value="After">After</option>
              </select>
              <input
                placeholder="Risk Reward"
                type="text"
                value={rr}
                onChange={(e) => setRR(e.target.value)}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
              />
              <input
                placeholder="Points"
                type="text"
                value={points}
                onChange={(e) => setPoints(e.target.value)}
                className="w-full p-2 rounded bg-[#0f172a] border border-white/10"
              />
              <label className="text-gray-400 text-sm mb-1 block">Top Confluences</label>
              <textarea
                placeholder="What confirmations led to this trade?"
                value={confluences}
                onChange={(e) => setConfluences(e.target.value)}
                className="w-full p-2 h-24 rounded bg-[#0f172a] border border-white/10"
              />
            </div>
          </div>

          <div className="p-4 rounded-xl bg-[#0b1220]/60 border border-white/5">
            <h3 className="text-sm text-gray-400 mb-2">Psychology</h3>
            <div className="space-y-3">
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
                <option value="Confident">Confident</option>
                <option value="Calm">Calm</option>
                <option value="Focused">Focused</option>
                <option value="Fearful">Fearful</option>
                <option value="FOMO">FOMO</option>
                <option value="Overconfident">Overconfident</option>
                <option value="Hesitant">Hesitant</option>
                <option value="Frustrated">Frustrated</option>
              </select>
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={followedPlan}
                  onChange={(e) => setFollowedPlan(e.target.checked)}
                />
                Followed Plan?
              </label>
              <select
                value={marketCondition}
                onChange={(e) => setMarketCondition(e.target.value)}
                className="w-full p-2 bg-[#0f172a] border border-white/10 rounded"
              >
                <option value="">Market</option>
                <option value="Trending">Trending</option>
                <option value="Strong Trend">Strong Trend</option>
                <option value="Ranging">Ranging</option>
                <option value="Choppy">Choppy</option>
                <option value="Low Volume">Low Volume</option>
                <option value="High Volume">High Volume</option>
                <option value="News Driven">News Driven</option>
                <option value="Volatile">Volatile</option>
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
            </div>
          </div>
        </div>

        <button
          type="button"
          disabled={saving}
          onClick={() => void handleSavePreset()}
          className="mt-5 w-full py-3 text-lg font-semibold rounded bg-green-500 hover:bg-green-600 text-white disabled:opacity-60"
        >
          {saving ? "Saving..." : "Save Preset"}
        </button>
      </div>
    </div>
  )
}
