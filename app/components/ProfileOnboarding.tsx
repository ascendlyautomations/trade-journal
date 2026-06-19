"use client"

import { useEffect, useRef, useState } from "react"
import { profileNeedsUsername } from "@/lib/profileOnboardingGate"
import { supabase } from "@/lib/supabaseClient"
import { uploadAvatarFile } from "@/lib/avatarUpload"
import {
  isProfilesUsernameConflict,
  normalizeProfileUsername,
  sanitizeUsernameInputForTyping,
  USERNAME_FORMAT_HINT,
  validateProfileUsernameNotEmpty,
} from "@/lib/profileUsername"
import { TRADER_TYPE_OPTIONS, normalizeTraderType } from "@/lib/traderType"
import CustomSelect from "@/app/components/CustomSelect"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { feedbackPresets } from "@/lib/feedbackPresets"
import {
  getLocalTodayDateInputValue,
  isStartedTradingDateInFuture,
} from "@/lib/tradeDateValidation"
import { mirrorAccountSettingsOnboardingCompleted } from "@/lib/profileSplitMirrorWrites"

export {
  profileNeedsOnboarding,
  profileNeedsUsername,
} from "@/lib/profileOnboardingGate"

export const ONBOARDING_FLAG = "tt_onboarding"

export function clearOnboardingFlag() {
  try {
    sessionStorage.removeItem(ONBOARDING_FLAG)
  } catch {
    /* ignore */
  }
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
  initialName?: string | null
  initialBio?: string | null
  initialTradingStyle?: string | null
  initialTraderType?: string | null
  initialPrimaryMarket?: string | null
  initialStartedTrading?: string | null
  initialAvatarUrl?: string | null
  onComplete: (patch: Record<string, unknown>) => void
}

export default function ProfileOnboarding({
  userId,
  initialUsername = "",
  initialName = "",
  initialBio = "",
  initialTradingStyle = "",
  initialTraderType = "",
  initialPrimaryMarket = "",
  initialStartedTrading = null,
  initialAvatarUrl = null,
  onComplete,
}: ProfileOnboardingProps) {
  const { showPopup, ...feedbackModalProps } = useFeedbackPopup()
  const [username, setUsername] = useState(() =>
    sanitizeUsernameInputForTyping(
      initialUsername ? String(initialUsername) : ""
    )
  )
  const [name, setName] = useState(initialName ? String(initialName) : "")
  const [bio, setBio] = useState(initialBio ? String(initialBio) : "")
  const [tradingStyle, setTradingStyle] = useState(
    initialTradingStyle ? String(initialTradingStyle) : ""
  )
  const [traderType, setTraderType] = useState(() =>
    normalizeTraderType(initialTraderType)
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
  const savingRef = useRef(false)
  const [error, setError] = useState<string | null>(null)
  const startedTradingInputRef = useRef<HTMLInputElement>(null)
  const formShellRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (initialName != null && String(initialName).trim() !== "") return
    let cancelled = false
    void (async () => {
      const { data } = await supabase
        .from("profiles")
        .select("name")
        .eq("id", userId)
        .maybeSingle()
      if (!cancelled && data?.name != null) {
        setName(String(data.name).trim())
      }
    })()
    return () => {
      cancelled = true
    }
  }, [userId, initialName])

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

  function handleStartedTradingChange(next: string) {
    if (isStartedTradingDateInFuture(next)) {
      showPopup(feedbackPresets.invalidStartedTradingDate())
    }
    setStartedTrading(next)
  }

  const invalidStartedTradingDate = isStartedTradingDateInFuture(startedTrading)
  const localTodayDate = getLocalTodayDateInputValue()

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (savingRef.current || saving) return
    setError(null)

    const u = normalizeProfileUsername(username)
    const usernameErr = validateProfileUsernameNotEmpty(username)
    if (usernameErr) {
      setError(usernameErr)
      return
    }

    if (!tradingStyle.trim()) {
      setError("Trading style is required")
      return
    }

    if (!traderType.trim()) {
      setError("Trader type is required")
      return
    }

    if (!startedTrading.trim()) {
      setError("Started trading date is required")
      return
    }

    if (invalidStartedTradingDate) {
      showPopup(feedbackPresets.invalidStartedTradingDate())
      return
    }

    savingRef.current = true
    setSaving(true)

    try {
      let avatarUrl: string | null = avatarPreview
      if (avatarFile) {
        const uploaded = await uploadAvatarFile(userId, avatarFile)
        if (uploaded) avatarUrl = uploaded
      }

      const patch = {
        username: u,
        name: name.trim() || null,
        bio: bio.trim() || null,
        trading_style: tradingStyle.trim(),
        trader_type: traderType.trim(),
        primary_market: primaryMarket.trim() || null,
        started_trading: startedTrading.trim(),
        avatar_url: avatarUrl,
        onboarding_completed: true,
      }

      const { error: upErr } = await supabase
        .from("profiles")
        .update(patch)
        .eq("id", userId)

      if (upErr) {
        if (isProfilesUsernameConflict(upErr)) {
          setError("Username already in use")
        } else {
          setError(upErr.message)
        }
        return
      }

      const { error: mirrorErr } = await mirrorAccountSettingsOnboardingCompleted(
        supabase,
        userId,
        true
      )
      if (mirrorErr) {
        console.error("mirror account_settings.onboarding_completed:", mirrorErr)
      }

      clearOnboardingFlag()
      onComplete(patch)
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  const onboardingFieldClass =
    "w-full min-w-0 rounded-xl border border-white/10 bg-white/10 text-white focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400"

  const inputClass = `${onboardingFieldClass} px-4 py-3`

  const selectTriggerClass = `${onboardingFieldClass} flex cursor-pointer items-center justify-between px-4 py-3 text-sm`

  const selectMenuClass =
    "fixed z-50 overflow-hidden rounded-xl border border-white/10 bg-[#3d4451] shadow-xl"

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <div
        ref={formShellRef}
        className="flex min-h-screen items-start justify-center overflow-x-hidden px-4 py-8 md:items-center"
      >
        <form
          onSubmit={handleSubmit}
          className="flex max-h-[min(90vh,720px)] w-full min-w-0 max-w-xl flex-col overflow-hidden rounded-2xl border border-white/10 bg-white/10 p-6 shadow-2xl backdrop-blur-xl sm:p-8"
        >
          <div className="min-h-0 flex-1 overflow-x-hidden overflow-y-auto overscroll-contain">
            <h2
              id="onboarding-title"
              className="mb-2 text-center text-2xl font-semibold text-white"
            >
              Let&apos;s get your account ready
            </h2>
            <p className="mb-6 text-center text-sm text-gray-300">
              {profileNeedsUsername(initialUsername)
                ? "Choose a username and a few trading details to unlock TradeTraxs."
                : "Add the remaining details below to finish setting up your account."}
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
                Upload photo (optional)
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
              placeholder="username (lowercase only)"
              className={`${inputClass} mb-1`}
              value={username}
              onChange={(e) =>
                setUsername(sanitizeUsernameInputForTyping(e.target.value))
              }
            />
            <p className="mb-4 text-xs text-gray-500">{USERNAME_FORMAT_HINT}</p>

            <label className="mb-1 block text-xs font-medium text-gray-300">
              Trading style <span className="text-red-400">*</span>
            </label>
            <input
              type="text"
              required
              placeholder="e.g. Scalping, swing, futures"
              className={`${inputClass} mb-4`}
              value={tradingStyle}
              onChange={(e) => setTradingStyle(e.target.value)}
            />

            <label className="mb-1 block text-xs font-medium text-gray-300">
              Trader type <span className="text-red-400">*</span>
            </label>
            <div className="mb-4">
              <CustomSelect
                value={traderType}
                onChange={(value) => setTraderType(normalizeTraderType(value))}
                placeholder="Select trader type"
                triggerClassName={selectTriggerClass}
                menuClassName={selectMenuClass}
                portalContainerRef={formShellRef}
                options={TRADER_TYPE_OPTIONS.map((option) => ({
                  label: option,
                  value: option,
                }))}
              />
            </div>

            <label className="mb-1 block text-xs font-medium text-gray-300">
              Started trading <span className="text-red-400">*</span>
            </label>
            <p className="mb-2 text-xs text-gray-500">
              Select the date you began trading
            </p>
            <div className="mb-4 w-full min-w-0">
              <input
                ref={startedTradingInputRef}
                type="date"
                required
                max={localTodayDate}
                value={startedTrading}
                onChange={(e) => handleStartedTradingChange(e.target.value)}
                onFocus={openStartedTradingPicker}
                className={`${inputClass} tt-timeframe-date cursor-pointer text-sm [color-scheme:dark]`}
              />
            </div>

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
          </div>

          <div className="shrink-0 pt-1">
            {error ? (
              <p className="mb-4 text-center text-sm text-red-400">{error}</p>
            ) : null}

            <button
              type="submit"
              disabled={saving || invalidStartedTradingDate}
              className="w-full rounded-xl bg-gradient-to-r from-blue-500 to-teal-400 py-3 font-semibold text-white transition hover:scale-[1.02] disabled:opacity-60 disabled:hover:scale-100"
            >
              {saving ? "Saving…" : "Finish setup"}
            </button>
          </div>
        </form>
      </div>
    </>
  )
}
