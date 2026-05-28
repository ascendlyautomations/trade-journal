"use client"

import { useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabaseClient"
import { uploadAvatarFile } from "@/lib/avatarUpload"

export const ONBOARDING_FLAG = "tt_onboarding"

export function clearOnboardingFlag() {
  try {
    sessionStorage.removeItem(ONBOARDING_FLAG)
  } catch {
    /* ignore */
  }
}

export function profileNeedsUsername(
  username: string | null | undefined
): boolean {
  return username == null || String(username).trim() === ""
}

/** Normalize DB / ISO dates to `YYYY-MM-DD` for `<input type="date">`. */
function sliceDateInput(raw: unknown): string {
  if (raw == null || raw === "") return ""
  const s = String(raw)
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10)
  const d = new Date(s)
  if (Number.isNaN(d.getTime())) return ""
  return d.toISOString().slice(0, 10)
}

type ProfileOnboardingProps = {
  userId: string
  initialUsername?: string | null
  initialBio?: string | null
  initialTradingStyle?: string | null
  initialPrimaryMarket?: string | null
  initialStartedTrading?: string | null
  initialAvatarUrl?: string | null
  onComplete: (patch: Record<string, unknown>) => void
  /**
   * When true, do not redirect to profile after save (parent handles next step, e.g. CSV modal).
   */
  suppressPostSaveRedirect?: boolean
}

export default function ProfileOnboarding({
  userId,
  initialUsername = "",
  initialBio = "",
  initialTradingStyle = "",
  initialPrimaryMarket = "",
  initialStartedTrading = null,
  initialAvatarUrl = null,
  onComplete,
  suppressPostSaveRedirect = false,
}: ProfileOnboardingProps) {
  const router = useRouter()
  const [username, setUsername] = useState(
    initialUsername ? String(initialUsername) : ""
  )
  const [bio, setBio] = useState(initialBio ? String(initialBio) : "")
  const [tradingStyle, setTradingStyle] = useState(
    initialTradingStyle ? String(initialTradingStyle) : ""
  )
  const [primaryMarket, setPrimaryMarket] = useState(
    initialPrimaryMarket ? String(initialPrimaryMarket) : ""
  )
  const [startedTrading, setStartedTrading] = useState(
    sliceDateInput(initialStartedTrading)
  )
  const [avatarFile, setAvatarFile] = useState<File | null>(null)
  const [avatarPreview, setAvatarPreview] = useState<string | null>(
    initialAvatarUrl
  )
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const startedTradingInputRef = useRef<HTMLInputElement>(null)

  function openStartedTradingPicker() {
    const el = startedTradingInputRef.current
    if (!el) return
    try {
      el.showPicker()
    } catch {
      el.focus()
    }
  }

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0]
    if (!f) return
    setAvatarFile(f)
    setAvatarPreview(URL.createObjectURL(f))
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)

    const u = username.trim()
    if (!u) {
      setError("Please choose a username.")
      return
    }

    setSaving(true)

    let avatarUrl: string | null = avatarPreview
    if (avatarFile) {
      const uploaded = await uploadAvatarFile(userId, avatarFile)
      if (uploaded) avatarUrl = uploaded
    }

    const { error: upErr } = await supabase
      .from("profiles")
      .update({
        username: u,
        bio: bio.trim() || null,
        trading_style: tradingStyle.trim() || null,
        primary_market: primaryMarket.trim() || null,
        started_trading: startedTrading.trim() || null,
        avatar_url: avatarUrl,
      })
      .eq("id", userId)

    if (upErr) {
      setSaving(false)
      setError(upErr.message)
      return
    }

    clearOnboardingFlag()
    onComplete({
      username: u,
      bio: bio.trim() || null,
      trading_style: tradingStyle.trim() || null,
      primary_market: primaryMarket.trim() || null,
      started_trading: startedTrading.trim() || null,
      avatar_url: avatarUrl,
    })

    setTimeout(() => {
      setSaving(false)
      if (!suppressPostSaveRedirect) {
        router.push(`/profile/${userId}`)
        router.refresh()
      }
    }, 300)
  }

  const inputClass =
    "w-full px-4 py-3 rounded-xl bg-white/10 border border-white/10 focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400 text-white"

  return (
    <div
      className="fixed inset-0 z-[1000] flex items-center justify-center bg-black/80 backdrop-blur-lg px-4 py-8"
      role="dialog"
      aria-modal="true"
      aria-labelledby="onboarding-title"
    >
      <form
        onSubmit={handleSubmit}
        className="flex max-h-[min(90vh,720px)] w-full max-w-md flex-col overflow-hidden rounded-2xl border border-white/10 bg-white/10 p-8 shadow-2xl backdrop-blur-xl"
      >
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain pr-1">
        <h2
          id="onboarding-title"
          className="mb-2 text-center text-xl font-semibold text-white"
        >
          Complete your profile
        </h2>
        <p className="mb-6 text-center text-sm text-gray-300">
          Add a few details so your journal and social profile look great.
        </p>

        <div className="mb-6 flex flex-col items-center gap-3">
          <div className="relative h-24 w-24 overflow-hidden rounded-full border-2 border-white/20 bg-white/5">
            {avatarPreview ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={avatarPreview}
                alt=""
                className="h-full w-full object-cover"
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-3xl text-gray-500">
                ?
              </div>
            )}
          </div>
          <label className="cursor-pointer rounded-xl bg-white/10 px-4 py-2 text-sm text-white transition hover:bg-white/20">
            Upload photo
            <input
              type="file"
              accept="image/*"
              className="sr-only"
              onChange={onFileChange}
            />
          </label>
        </div>

        <label className="mb-1 block text-xs font-medium text-gray-300">
          Username <span className="text-red-400">*</span>
        </label>
        <input
          type="text"
          required
          autoComplete="username"
          placeholder="Username"
          className={`${inputClass} mb-4`}
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />

        <label className="mb-1 block text-xs font-medium text-gray-300">
          Bio
        </label>
        <textarea
          placeholder="Short bio (optional)"
          rows={3}
          className={`${inputClass} mb-4 resize-none`}
          value={bio}
          onChange={(e) => setBio(e.target.value)}
        />

        <label className="mb-1 block text-xs font-medium text-gray-300">
          Trading style
        </label>
        <input
          type="text"
          placeholder="e.g. Scalping, swing, futures"
          className={`${inputClass} mb-4`}
          value={tradingStyle}
          onChange={(e) => setTradingStyle(e.target.value)}
        />

        <label className="mb-1 block text-xs font-medium text-gray-300">
          Primary Market
        </label>
        <input
          type="text"
          placeholder="e.g. NQ, ES, Gold, BTC, EUR/USD"
          className={`${inputClass} mb-4`}
          value={primaryMarket}
          onChange={(e) => setPrimaryMarket(e.target.value)}
        />
        </div>

        <div className="shrink-0 pt-1">
        <label className="mb-1 block text-xs font-medium text-gray-300">
          Started Trading
        </label>
        <p className="mb-2 text-xs text-gray-500">
          Select date you began trading
        </p>
        <div className="mb-6 w-full">
          <input
            ref={startedTradingInputRef}
            type="date"
            value={startedTrading}
            onChange={(e) => setStartedTrading(e.target.value)}
            onClick={(e) => {
              e.preventDefault()
              openStartedTradingPicker()
            }}
            className="w-full cursor-pointer rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-white focus:outline-none focus:ring-2 focus:ring-blue-400 [color-scheme:dark]"
            style={{ colorScheme: "dark" }}
          />
        </div>

        {error ? (
          <p className="mb-4 text-center text-sm text-red-400">{error}</p>
        ) : null}

        <button
          type="submit"
          disabled={saving}
          className="w-full rounded-xl bg-gradient-to-r from-blue-500 to-teal-400 py-3 font-semibold text-white transition hover:scale-[1.02] disabled:opacity-60 disabled:hover:scale-100"
        >
          {saving ? "Saving…" : "Save & continue"}
        </button>
        </div>
      </form>
    </div>
  )
}
