"use client"

import { useEffect, useRef, useState, type ReactNode } from "react"
import { profileNeedsUsername } from "@/lib/profileOnboardingGate"
import { supabase } from "@/lib/supabaseClient"
import { uploadAvatarFile } from "@/lib/avatarUpload"
import ImageCropModal from "@/app/components/ImageCropModal"
import { useImageCropUpload } from "@/lib/useImageCropUpload"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import {
  isProfilesUsernameConflict,
  normalizeProfileUsername,
  sanitizeUsernameInputForTyping,
  USERNAME_FORMAT_HINT,
  validateProfileUsernameNotEmpty,
} from "@/lib/profileUsername"
import { TRADER_TYPE_OPTIONS, normalizeTraderType } from "@/lib/traderType"
import CustomSelect from "@/app/components/CustomSelect"
import { useAutoResizeTextarea } from "@/lib/useAutoResizeTextarea"
import { constrainProfileBio } from "@/lib/profileBio"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import { feedbackPresets } from "@/lib/feedbackPresets"
import {
  getLocalTodayDateInputValue,
  isStartedTradingDateInFuture,
} from "@/lib/tradeDateValidation"
import { mirrorAccountSettingsOnboardingCompleted } from "@/lib/profileSplitMirrorWrites"
import { notifyBetaSignupAfterOnboardingComplete } from "@/lib/betaSignupNotify"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { markContextualTourAwaitingInvite } from "@/lib/contextualTour/awaitingInvite"

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

const FIELD_LABEL = "mb-1.5 block text-xs font-medium text-gray-300"

const FIELD_HINT = "text-xs leading-snug text-gray-400"

/** Matches NativeDateInput grey field chrome. */
const CONTROL_BASE =
  "w-full min-w-0 rounded-lg border border-white/10 bg-black/30 text-sm text-white transition-colors placeholder:text-gray-400 focus:border-blue-400/45 focus:outline-none focus:ring-2 focus:ring-blue-500/25"

const CONTROL_HEIGHT = "h-10 px-3"

function OnboardingField({
  label,
  required,
  hint,
  children,
  className = "",
  htmlFor,
}: {
  label: string
  required?: boolean
  hint?: string
  children: ReactNode
  className?: string
  htmlFor?: string
}) {
  return (
    <div className={className}>
      <label className={FIELD_LABEL} htmlFor={htmlFor}>
        {label}
        {required ? <span className="normal-case text-red-400/90"> *</span> : null}
      </label>
      {hint ? <p className={`-mt-1 mb-1.5 ${FIELD_HINT}`}>{hint}</p> : null}
      {children}
    </div>
  )
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
  onComplete: (patch: Record<string, unknown>) => void | Promise<void>
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
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { runUpload } = useUploadProgress()
  const [username, setUsername] = useState(() =>
    sanitizeUsernameInputForTyping(
      initialUsername ? String(initialUsername) : ""
    )
  )
  const [name, setName] = useState(initialName ? String(initialName) : "")
  const [bio, setBio] = useState(
    initialBio ? constrainProfileBio(String(initialBio)) : ""
  )
  const bioTextareaRef = useAutoResizeTextarea(bio, { minLines: 2, maxLines: 4 })
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
  const avatarCrop = useImageCropUpload({
    preset: "avatar",
    onCropped: (cropped) => {
      setAvatarFile(cropped)
      setAvatarPreview(URL.createObjectURL(cropped))
    },
    onValidationError: setError,
  })

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

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    avatarCrop.handleFileSelected(e.target.files?.[0])
  }

  function handleStartedTradingChange(next: string) {
    if (isStartedTradingDateInFuture(next)) {
      showPopup(feedbackPresets.invalidStartedTradingDate())
    }
    setStartedTrading(next)
  }

  const invalidStartedTradingDate = isStartedTradingDateInFuture(startedTrading)
  const localTodayDate = getLocalTodayDateInputValue()

  const subtitle = profileNeedsUsername(initialUsername)
    ? "Pick a username and tell us how you trade — it only takes a minute."
    : "Fill in the last few details to unlock your dashboard."

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
        try {
          await runUpload({
            title: "Uploading Profile Picture",
            execute: async (report) => {
              const uploaded = await uploadAvatarFile(userId, avatarFile, {
                onProgress: report,
              })
              if (!uploaded) {
                throw new Error("Could not upload profile picture.")
              }
              avatarUrl = uploaded
            },
          })
        } catch {
          return
        }
      }

      const patch = {
        username: u,
        name: name.trim() || null,
        bio: constrainProfileBio(bio).trim() || null,
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
          console.error("[ProfileOnboarding] profile update failed", upErr)
          setError(handleSupabaseError(upErr))
        }
        return
      }

      const { confirmProfileOnboardingPersisted } = await import(
        "@/lib/confirmProfileOnboardingPersisted"
      )
      const confirmed = await confirmProfileOnboardingPersisted(
        supabase,
        userId,
        u
      )
      if (!confirmed.ok) {
        setError(confirmed.message)
        return
      }

      markContextualTourAwaitingInvite(userId)
      clearOnboardingFlag()
      notifyBetaSignupAfterOnboardingComplete("onboarding")
      void mirrorAccountSettingsOnboardingCompleted(supabase, userId, true).then(
        ({ error: mirrorErr }) => {
          if (mirrorErr) {
            console.error(
              "mirror account_settings.onboarding_completed:",
              mirrorErr
            )
          }
        }
      )
      await onComplete(patch)
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  const inputClass = `${CONTROL_BASE} ${CONTROL_HEIGHT}`
  const selectTriggerClass = `${CONTROL_BASE} ${CONTROL_HEIGHT} flex cursor-pointer items-center justify-between`
  const selectMenuClass =
    "fixed z-[200] max-h-60 overflow-y-auto rounded-lg border border-white/10 bg-[#0f172a] shadow-lg"

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <div className="flex w-full justify-center px-4 py-5 sm:px-5 md:min-h-dvh md:items-center md:py-6">
        <form
          onSubmit={handleSubmit}
          aria-labelledby="onboarding-title"
          className="w-full max-w-[700px] shrink-0 rounded-xl border border-white/10 bg-white/10 p-5 shadow-[0_24px_80px_-12px_rgba(0,0,0,0.65)] ring-1 ring-white/[0.06] backdrop-blur-md sm:p-6"
        >
          <header className="mb-5">
            <div className="mb-3 flex items-center gap-2.5">
              <span
                className="h-9 w-1 shrink-0 rounded-full bg-gradient-to-b from-blue-400 to-blue-600"
                aria-hidden
              />
              <div>
                <p className="text-xs font-bold uppercase tracking-[0.22em] text-blue-300">
                  TradeTraxs
                </p>
                <p className="text-[11px] text-gray-500">Profile setup</p>
              </div>
            </div>
            <h1
              id="onboarding-title"
              className="text-[1.35rem] font-semibold leading-tight tracking-tight text-white sm:text-2xl"
            >
              Set up your trader profile
            </h1>
            <p className="mt-1.5 max-w-[34rem] text-sm leading-snug text-gray-400">
              {subtitle}
            </p>
          </header>

          <div className="mb-4 flex items-start gap-3 sm:gap-4">
            <div className="flex shrink-0 flex-col items-center gap-1">
              <ProfileAvatarImg
                src={avatarPreview}
                className="h-14 w-14 border border-white/15"
              />
              <label className="cursor-pointer text-center text-[11px] font-medium leading-tight text-blue-300 transition hover:text-blue-200">
                Upload
                <input
                  type="file"
                  accept="image/*"
                  className="sr-only"
                  onChange={onFileChange}
                />
              </label>
              <span className={`text-[10px] ${FIELD_HINT}`}>Optional</span>
            </div>

            <div className="min-w-0 flex-1 pt-0.5">
              <label className={FIELD_LABEL} htmlFor="onboarding-username">
                Username
                <span className="text-red-400/90"> *</span>
              </label>
              <input
                id="onboarding-username"
                type="text"
                required
                autoComplete="username"
                placeholder="yourname"
                className={inputClass}
                value={username}
                onChange={(e) =>
                  setUsername(sanitizeUsernameInputForTyping(e.target.value))
                }
              />
              <p className={`mt-1.5 ${FIELD_HINT}`}>{USERNAME_FORMAT_HINT}</p>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-3.5 sm:grid-cols-2 sm:gap-4">
            <OnboardingField label="Trading style" required htmlFor="onboarding-trading-style">
              <input
                id="onboarding-trading-style"
                type="text"
                required
                placeholder="Scalping, swing, investor…"
                className={inputClass}
                value={tradingStyle}
                onChange={(e) => setTradingStyle(e.target.value)}
              />
            </OnboardingField>

            <OnboardingField label="Trader type" required>
              <CustomSelect
                value={traderType}
                onChange={(value) => setTraderType(normalizeTraderType(value))}
                placeholder="Select type"
                triggerClassName={selectTriggerClass}
                triggerLabelClassName="min-w-0 flex-1 truncate text-left text-white"
                menuClassName={selectMenuClass}
                options={TRADER_TYPE_OPTIONS.map((option) => ({
                  label: option,
                  value: option,
                }))}
              />
            </OnboardingField>
          </div>

          <div className="mt-3.5 space-y-3.5 sm:mt-4">
            <OnboardingField
              label="Started trading"
              required
              hint="Must be today or earlier"
              className="max-w-sm"
            >
              <NativeDateInput
                required
                max={localTodayDate}
                value={startedTrading}
                onChange={(e) => handleStartedTradingChange(e.target.value)}
                className="tt-date-field--compact h-10 rounded-lg"
                aria-label="Started trading date"
              />
            </OnboardingField>

            <OnboardingField label="Bio" htmlFor="onboarding-bio">
              <textarea
                id="onboarding-bio"
                ref={bioTextareaRef}
                placeholder="Short bio (optional)"
                rows={2}
                className={`${CONTROL_BASE} min-h-[4.5rem] resize-none overflow-hidden px-3 py-2.5 leading-normal`}
                value={bio}
                onChange={(e) => setBio(constrainProfileBio(e.target.value))}
              />
            </OnboardingField>
          </div>

          {error ? (
            <p
              className="mt-4 rounded-lg border border-red-500/25 bg-red-950/50 px-3 py-2 text-sm text-red-200"
              role="alert"
            >
              {error}
            </p>
          ) : null}

          <button
            type="submit"
            disabled={saving || invalidStartedTradingDate}
            className="mt-4 h-10 w-full rounded-lg bg-blue-500 text-sm font-semibold text-white shadow-md shadow-blue-950/30 transition hover:bg-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-400/45 disabled:cursor-not-allowed disabled:opacity-55"
          >
            {saving ? "Saving…" : "Finish setup"}
          </button>
        </form>
      </div>
      <ImageCropModal
        open={avatarCrop.cropSourceFile != null}
        file={avatarCrop.cropSourceFile}
        preset="avatar"
        onCancel={avatarCrop.handleCropCancel}
        onSave={avatarCrop.handleCropSave}
      />
    </>
  )
}
