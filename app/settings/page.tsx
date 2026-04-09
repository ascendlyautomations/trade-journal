"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"

export default function SettingsPage() {
  const [user, setUser] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [profile, setProfile] = useState<any>(null)
  const [managingSub, setManagingSub] = useState(false)
  const [affiliateData, setAffiliateData] = useState<any>(null)

  const [name, setName] = useState("")
  const [username, setUsername] = useState("")
  const [bio, setBio] = useState("")
  const [isPrivate, setIsPrivate] = useState(false)

  const [avatarFile, setAvatarFile] = useState<File | null>(null)
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null)

  const [tradingStyle, setTradingStyle] = useState("")
  const [experience, setExperience] = useState("")
  const [startedTrading, setStartedTrading] = useState<string>("")
  const [tradingModel, setTradingModel] = useState<string>("")
  const [maxDrawdown, setMaxDrawdown] = useState("")
  const [savingDrawdown, setSavingDrawdown] = useState(false)

  useEffect(() => {
    init()
  }, [])

  async function init() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    if (!user) return

    setUser(user)

    const { data } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", user.id)
      .single()

    if (data) {
      setProfile(data)
      setName(data.name || "")
      setUsername(data.username || "")
      setBio(data.bio || "")
      setIsPrivate(data.is_private || false)
      setAvatarPreview(data.avatar_url || null)
      setTradingStyle(data.trading_style || data.trading_model || "")
      setExperience(data.experience || "")
      setStartedTrading(data.startedTrading || "")
      setTradingModel(data.trading_model || "")
      setMaxDrawdown(
        data.max_drawdown_limit != null && data.max_drawdown_limit !== ""
          ? String(data.max_drawdown_limit)
          : ""
      )

      try {
        const { data: affiliate } = await supabase
          .from("affiliates")
          .select("*")
          .eq("user_id", data.id)
          .single()

        if (affiliate) {
          setAffiliateData(affiliate)
        }
      } catch (e) {
        console.error("Affiliate stats fetch failed:", e)
      }
    }

    setLoading(false)
  }

  // ✅ FIXED UPLOAD FUNCTION
  async function uploadAvatar() {
    if (!avatarFile || !user) return null

    const fileExt = avatarFile.name.split(".").pop()
    const fileName = `${user.id}/${Date.now()}.${fileExt}`

    const { data: uploadData, error: uploadError } = await supabase.storage
      .from("avatars")
      .upload(fileName, avatarFile, {
        upsert: true
      })

    console.log("UPLOAD RESULT:", { uploadData, uploadError })

    if (uploadError) {
      console.error("REAL UPLOAD ERROR:", uploadError.message)
      return null
    }

    const publicUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${fileName}`

    return publicUrl
  }

  async function saveSettings() {
    if (!user) return

    setSaving(true)

    let avatarUrl = avatarPreview

    if (avatarFile) {
      const uploaded = await uploadAvatar()

      if (uploaded) {
        avatarUrl = uploaded
      }
    }

    const { error } = await supabase
      .from("profiles")
      .update({
        name,
        username,
        bio,
        is_private: isPrivate,
        avatar_url: avatarUrl,
        trading_style: tradingStyle,
        experience,
        started_trading: startedTrading,
        trading_model: tradingModel || tradingStyle || null,
        max_drawdown_limit: (() => {
          const t = maxDrawdown.trim()
          if (t === "") return null
          const n = Number(t)
          return Number.isFinite(n) && n >= 0 ? n : profile?.max_drawdown_limit ?? null
        })(),
      })
      .eq("id", user.id)

    // ✅ FIXED ERROR HANDLING
    if (error) {
      alert(error.message)
    } else {
      alert("Settings saved 🔥")
    }

    setSaving(false)
  }

  async function saveDrawdownLimit() {
    if (!user) return

    const t = maxDrawdown.trim()
    const n = t === "" ? null : Number(t)
    if (t !== "" && (!Number.isFinite(n) || n === null || n < 0)) {
      alert("Enter a valid non-negative dollar amount, or leave blank to clear your limit.")
      return
    }

    setSavingDrawdown(true)
    const { error } = await supabase
      .from("profiles")
      .update({
        max_drawdown_limit: n,
      })
      .eq("id", user.id)
    setSavingDrawdown(false)

    if (error) {
      alert(error.message)
      return
    }

    setProfile((p: any) => (p ? { ...p, max_drawdown_limit: n } : p))
    alert("Drawdown limit saved")
  }

  async function handleManageSubscription() {
    if (!user) return

    setManagingSub(true)
    try {
      if (!profile?.stripe_customer_id) {
        alert("No active subscription found")
        return
      }

      const res = await fetch("/api/create-portal-session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ userId: user.id })
      })

      const data = await res.json()

      if (data.url) {
        window.location.href = data.url
      } else {
        alert("Unable to open billing portal")
      }
    } catch (err) {
      console.error("Manage subscription error:", err)
      alert("Something went wrong")
    } finally {
      setManagingSub(false)
    }
  }

  if (loading) return <div className="text-white text-center mt-20">Loading...</div>

  const referralLink =
    affiliateData && typeof window !== "undefined"
      ? `${window.location.origin}?ref=${affiliateData.code}`
      : ""

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">

        <div className="max-w-6xl mx-auto space-y-8">

          <h1 className="text-2xl font-semibold">Settings</h1>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-10 items-start">

            <div className="space-y-8">
              {/* PROFILE */}
              <div className="bg-white/5 p-8 rounded-xl space-y-5 min-h-[300px]">

                <h2 className="text-emerald-400">Profile</h2>

                {/* AVATAR */}
                <div className="flex items-center gap-4">

                  <div className="w-16 h-16 rounded-full bg-gray-700 overflow-hidden">
                    {avatarPreview && (
                      <img
                        src={avatarPreview}
                        className="w-full h-full object-cover"
                        onError={(e) => {
                          e.currentTarget.src = "/default-avatar.png"
                        }}
                      />
                    )}
                  </div>

                  <input
                    type="file"
                    onChange={(e) => {
                      const file = e.target.files?.[0]
                      if (!file) return
                      setAvatarFile(file)
                      setAvatarPreview(URL.createObjectURL(file))
                    }}
                  />

                </div>

                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Display Name"
                  className="w-full p-3 bg-black border border-white/10 rounded"
                />

                <input
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="Username"
                  className="w-full p-3 bg-black border border-white/10 rounded"
                />

                <textarea
                  value={bio}
                  onChange={(e) => setBio(e.target.value)}
                  placeholder="Bio"
                  className="w-full p-3 bg-black border border-white/10 rounded"
                />

              </div>

              {/* TRADING */}
              <div className="bg-white/5 p-8 rounded-xl space-y-5 min-h-[300px]">

                <h2 className="text-blue-400">Trading Profile</h2>

                <input
                  value={tradingModel}
                  onChange={(e) => {
                    setTradingModel(e.target.value)
                    setTradingStyle(e.target.value)
                  }}
                  placeholder="Trading Model"
                  className="w-full p-3 bg-black border border-white/10 rounded"
                />

                <div>
                  <label className="text-sm text-gray-400">Started Trading</label>
                  <input
                    type="date"
                    value={startedTrading || ""}
                    onChange={(e) => setStartedTrading(e.target.value)}
                    className="w-full p-3 rounded bg-[#0f172a] border border-white/10"
                  />
                </div>

                <div className="rounded-lg border border-white/10 bg-black/20 p-4 space-y-3">
                  <p className="text-sm text-gray-400">Drawdown limit</p>
                  <p className="text-xs text-gray-500">
                    Optional cap on drawdown from your equity peak (filtered trades on the
                    dashboard). Leave blank to clear.
                  </p>
                  <div className="flex flex-wrap items-center gap-2">
                    <input
                      type="number"
                      min={0}
                      step="0.01"
                      placeholder="Max Drawdown ($)"
                      value={maxDrawdown}
                      onChange={(e) => setMaxDrawdown(e.target.value)}
                      className="bg-[#0f172a] text-white border border-white/10 rounded px-3 py-2 min-w-[12rem] flex-1"
                    />
                    <button
                      type="button"
                      onClick={saveDrawdownLimit}
                      disabled={savingDrawdown}
                      className="bg-slate-600 hover:bg-slate-500 px-4 py-2 rounded text-sm font-medium disabled:opacity-50"
                    >
                      {savingDrawdown ? "Saving…" : "Save limit"}
                    </button>
                  </div>
                </div>

                {profile?.is_pro && (
                  <button
                    onClick={handleManageSubscription}
                    disabled={managingSub}
                    className="w-full bg-emerald-500 hover:bg-emerald-600 px-4 py-2 rounded font-semibold mt-2 disabled:opacity-50"
                  >
                    {managingSub ? "Opening Billing Portal..." : "Manage Subscription"}
                  </button>
                )}

              </div>
            </div>

            <div className="space-y-6">
              {affiliateData && (
                <div className="p-8 rounded-xl bg-white/5 border border-white/10 space-y-4 min-h-[300px]">

                  <h2 className="text-xl font-semibold mb-4">
                    Affiliate Dashboard
                  </h2>

                  <p className="text-sm text-gray-400 mb-2">
                    Your Code:
                    <span className="text-white ml-2">
                      {affiliateData.code}
                    </span>
                  </p>

                  <p className="text-sm text-gray-400 mb-4">
                    Total Referrals:
                    <span className="text-white ml-2">
                      {Number(profile?.referral_count || 0)}
                    </span>
                  </p>

                  <p className="text-sm text-gray-400 mb-2">
                    Your referral link:
                  </p>

                  <div className="flex gap-2">
                    <input
                      value={referralLink}
                      readOnly
                      className="flex-1 p-3 rounded bg-black border border-white/10 text-sm"
                    />

                    <button
                      onClick={async () => {
                        if (!referralLink) return
                        try {
                          await navigator.clipboard.writeText(referralLink)
                          alert("Copied!")
                        } catch (err) {
                          console.error("Copy failed", err)
                          alert("Failed to copy")
                        }
                      }}
                      className="bg-emerald-500 px-5 py-2 rounded text-white text-sm hover:bg-emerald-600"
                    >
                      Copy
                    </button>
                  </div>

                </div>
              )}

              <button
                onClick={saveSettings}
                disabled={saving}
                className="w-full bg-gradient-to-r from-blue-500 to-emerald-500 p-3 rounded-lg mt-6"
              >
                {saving ? "Saving..." : "Save Changes"}
              </button>
            </div>

          </div>

          {/* PRIVACY */}
          <div className="bg-white/5 p-6 rounded-xl flex justify-between items-center">

            <div>
              <p>Private Profile</p>
              <p className="text-xs text-gray-400">
                Only followers can view your profile
              </p>
            </div>

            <button
              onClick={() => setIsPrivate(!isPrivate)}
              className={`px-4 py-2 rounded ${
                isPrivate ? "bg-emerald-500" : "bg-white/10"
              }`}
            >
              {isPrivate ? "ON" : "OFF"}
            </button>

          </div>

        </div>

      </div>
    </>
  )
}