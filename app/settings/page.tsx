"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"

export default function SettingsPage() {
  const [user, setUser] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [name, setName] = useState("")
  const [username, setUsername] = useState("")
  const [bio, setBio] = useState("")
  const [isPrivate, setIsPrivate] = useState(false)

  const [avatarFile, setAvatarFile] = useState<File | null>(null)
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null)

  const [tradingStyle, setTradingStyle] = useState("")
  const [experience, setExperience] = useState("")

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
      setName(data.name || "")
      setUsername(data.username || "")
      setBio(data.bio || "")
      setIsPrivate(data.is_private || false)
      setAvatarPreview(data.avatar_url || null)
      setTradingStyle(data.trading_style || "")
      setExperience(data.experience || "")
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
        experience
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

  if (loading) return <div className="text-white text-center mt-20">Loading...</div>

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">

        <div className="max-w-2xl mx-auto space-y-8">

          <h1 className="text-2xl font-semibold">Settings</h1>

          {/* PROFILE */}
          <div className="bg-white/5 p-6 rounded-xl space-y-4">

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
          <div className="bg-white/5 p-6 rounded-xl space-y-4">

            <h2 className="text-blue-400">Trading Profile</h2>

            <input
              value={tradingStyle}
              onChange={(e) => setTradingStyle(e.target.value)}
              placeholder="Trading Model"
              className="w-full p-3 bg-black border border-white/10 rounded"
            />

            <input
              value={experience}
              onChange={(e) => setExperience(e.target.value)}
              placeholder="Experience"
              className="w-full p-3 bg-black border border-white/10 rounded"
            />

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

          <button
            onClick={saveSettings}
            disabled={saving}
            className="w-full bg-gradient-to-r from-blue-500 to-emerald-500 p-3 rounded"
          >
            {saving ? "Saving..." : "Save Changes"}
          </button>
              
        </div>

      </div>
    </>
  )
}