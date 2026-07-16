"use client"

import {
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
  forwardRef,
  type Ref,
} from "react"
import { AFFILIATE_PRIMARY_BUTTON_CLASS } from "@/lib/affiliateUi"
import { supabase } from "@/lib/supabaseClient"
import {
  submitAffiliateApplication,
  type AffiliateApplicationRow,
} from "@/lib/affiliateApplication"
import { useUserProfile } from "@/lib/useUserProfile"

export type AffiliateApplyFormHandle = {
  focusFirstField: () => void
}

type AffiliateApplyFormProps = {
  prefillFrom?: AffiliateApplicationRow | null
  title?: string
  onSubmit: () => void | Promise<void>
  onCancel?: () => void
  showCancel?: boolean
  /** When false, form state resets only on mount (inline page section). */
  active?: boolean
}

function normalizeAffiliateRequestedCode(raw: string): string {
  return raw.trim().toUpperCase()
}

type CodeAvailability = "idle" | "empty" | "checking" | "taken" | "available" | "check_error"

async function affiliateCodeIsTaken(normalized: string): Promise<boolean | null> {
  if (!normalized) return false
  const { data, error } = await supabase
    .from("affiliates")
    .select("code")
    .eq("code", normalized)
    .maybeSingle()

  if (error) return null
  return data != null
}

function AffiliateApplyFormInner(
  {
    prefillFrom = null,
    title = "Affiliate application",
    onSubmit,
    onCancel,
    showCancel = true,
    active = true,
  }: AffiliateApplyFormProps,
  ref: Ref<AffiliateApplyFormHandle>
) {
  const { user } = useUserProfile()
  const socialHandleRef = useRef<HTMLInputElement>(null)
  const [socialHandle, setSocialHandle] = useState("")
  const [followers, setFollowers] = useState("")
  const [requestedCode, setRequestedCode] = useState("")
  const [isEditing, setIsEditing] = useState(false)
  const [showEditConfirm, setShowEditConfirm] = useState(false)
  const [busy, setBusy] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)
  const [codeAvailability, setCodeAvailability] = useState<CodeAvailability>("idle")

  useImperativeHandle(ref, () => ({
    focusFirstField: () => {
      const input = socialHandleRef.current
      if (input && !input.disabled) {
        input.focus({ preventScroll: true })
        return
      }
      const editButton = document.getElementById("affiliate-apply-edit-button")
      editButton?.focus({ preventScroll: true })
    },
  }))

  useEffect(() => {
    if (!active) return

    const row = prefillFrom
    const canPrefill = row && row.status !== "approved"

    let socialHandleValue = ""
    let followersValue = ""
    let requestedCodeValue = ""

    if (canPrefill) {
      socialHandleValue = row.social_handle ?? ""
      followersValue = row.followers != null ? String(row.followers) : ""
      requestedCodeValue = row.requested_code
        ? row.requested_code.trim().toUpperCase()
        : ""
    }

    setSocialHandle(socialHandleValue)
    setFollowers(followersValue)
    setRequestedCode(requestedCodeValue)

    if (!row || row.status === "rejected") {
      setIsEditing(true)
    } else {
      setIsEditing(false)
    }

    setFormError(null)
    setCodeAvailability("idle")
    setShowEditConfirm(false)
  }, [active, prefillFrom])

  useEffect(() => {
    if (!active) return

    const normalized = normalizeAffiliateRequestedCode(requestedCode)
    if (!normalized) {
      setCodeAvailability("empty")
      return
    }

    let cancelled = false
    setCodeAvailability("checking")

    const timer = window.setTimeout(() => {
      void (async () => {
        const taken = await affiliateCodeIsTaken(normalized)
        if (cancelled) return
        if (taken === null) {
          setCodeAvailability("check_error")
          return
        }
        setCodeAvailability(taken ? "taken" : "available")
      })()
    }, 400)

    return () => {
      cancelled = true
      window.clearTimeout(timer)
    }
  }, [requestedCode, active])

  const normalizedRequestedCode = normalizeAffiliateRequestedCode(requestedCode)

  const canEditFields = Boolean(
    !prefillFrom ||
      prefillFrom.status === "rejected" ||
      (prefillFrom.status === "pending" && !prefillFrom.has_edited && isEditing)
  )

  const showInnerEdit = Boolean(
    prefillFrom?.status === "pending" && !prefillFrom.has_edited && !isEditing
  )

  const submitDisabled = busy || codeAvailability === "taken" || !canEditFields

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setFormError(null)

    if (!canEditFields) return

    const handle = socialHandle.trim()
    if (!handle) {
      setFormError("Enter your social handle or profile link.")
      return
    }

    const n = parseInt(followers.trim(), 10)
    if (!Number.isFinite(n) || n < 0) {
      setFormError("Enter a valid follower count (0 or more).")
      return
    }

    const codeForSubmit = normalizedRequestedCode || null
    if (codeForSubmit) {
      const taken = await affiliateCodeIsTaken(codeForSubmit)
      if (taken === null) {
        setFormError("Could not verify code availability. Try again.")
        return
      }
      if (taken) {
        setFormError("This code is already taken")
        setCodeAvailability("taken")
        return
      }
    }

    setBusy(true)
    if (!user?.id) {
      setFormError("Not signed in.")
      setBusy(false)
      return
    }

    const formPayload = {
      socialHandle: handle,
      followers: n,
      requestedCode: codeForSubmit,
    }

    const saveAndLock =
      prefillFrom?.status === "pending" && isEditing && !prefillFrom.has_edited

    const { ok, error } = await submitAffiliateApplication(
      supabase,
      user.id,
      formPayload
    )

    setBusy(false)
    if (!ok || error) {
      setFormError(error || "Could not submit application.")
      return
    }

    if (saveAndLock) {
      alert("Application saved and locked.")
    }

    await onSubmit()
  }

  return (
    <>
      <div>
        <h2 className="text-lg font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          {title}
        </h2>
        <p className="mt-1 text-xs text-gray-400">
          Status updates appear on this page and in Settings → Affiliate.
        </p>

        {prefillFrom?.status === "pending" && prefillFrom.has_edited ? (
          <p className="mt-3 rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-xs text-gray-400">
            You have already used your one edit.
          </p>
        ) : null}

        <form onSubmit={(e) => void handleSubmit(e)} className="mt-4 space-y-3">
          <div>
            <label className="text-xs text-gray-400">Social handle</label>
            <input
              ref={socialHandleRef}
              value={socialHandle}
              onChange={(e) => setSocialHandle(e.target.value)}
              required={canEditFields}
              disabled={!canEditFields}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-400 disabled:cursor-not-allowed disabled:opacity-60"
              placeholder="@you or profile URL"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Followers</label>
            <input
              type="number"
              min={0}
              step={1}
              value={followers}
              onChange={(e) => setFollowers(e.target.value)}
              required={canEditFields}
              disabled={!canEditFields}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-400 disabled:cursor-not-allowed disabled:opacity-60"
              placeholder="Approximate follower count"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Requested code (optional)</label>
            <input
              value={requestedCode}
              onChange={(e) => setRequestedCode(e.target.value.toUpperCase())}
              aria-invalid={codeAvailability === "taken"}
              disabled={!canEditFields}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 font-mono text-sm text-white placeholder:text-gray-400 disabled:cursor-not-allowed disabled:opacity-60"
              placeholder="YOURCODE"
            />
            {normalizedRequestedCode ? (
              <div className="mt-1.5 min-h-[1.25rem] text-xs">
                {codeAvailability === "checking" ? (
                  <span className="text-gray-400">Checking availability…</span>
                ) : codeAvailability === "taken" ? (
                  <span className="text-red-300">This code is already taken</span>
                ) : codeAvailability === "available" ? (
                  <span className="text-emerald-400/90">Code available</span>
                ) : codeAvailability === "check_error" ? (
                  <span className="text-amber-200/90">Could not verify code (try again)</span>
                ) : null}
              </div>
            ) : null}
          </div>

          {formError ? <p className="text-sm text-red-300">{formError}</p> : null}

          <div className="flex flex-wrap justify-end gap-2 pt-2">
            {showCancel && onCancel ? (
              <button
                type="button"
                onClick={onCancel}
                className="rounded-lg bg-white/10 px-4 py-2 text-sm hover:bg-white/20"
              >
                {prefillFrom?.status === "pending" && prefillFrom.has_edited
                  ? "Close"
                  : "Cancel"}
              </button>
            ) : null}
            {showInnerEdit ? (
              <button
                id="affiliate-apply-edit-button"
                type="button"
                onClick={() => setShowEditConfirm(true)}
                className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600"
              >
                Edit Application
              </button>
            ) : null}
            {canEditFields ? (
              <button
                type="submit"
                disabled={submitDisabled}
                className={`${AFFILIATE_PRIMARY_BUTTON_CLASS} px-5`}
              >
                {busy
                  ? "Submitting…"
                  : prefillFrom?.status === "pending" &&
                      isEditing &&
                      !prefillFrom.has_edited
                    ? "Save & lock"
                    : "Submit application"}
              </button>
            ) : null}
          </div>
        </form>
      </div>

      {showEditConfirm ? (
        <div
          className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/60 p-4"
          role="presentation"
          onClick={() => setShowEditConfirm(false)}
        >
          <div
            className="w-[90%] max-w-md rounded-2xl border border-white/10 bg-[#0b1f3a] p-6"
            role="dialog"
            aria-modal="true"
            aria-labelledby="affiliate-edit-confirm-title"
            onClick={(e) => e.stopPropagation()}
          >
            <h2
              id="affiliate-edit-confirm-title"
              className="mb-2 text-lg font-semibold text-white"
            >
              Edit Application
            </h2>

            <p className="mb-6 text-sm text-white/70">
              You can only edit your affiliate application{" "}
              <span className="font-semibold text-red-400">once</span>. After saving, it will be
              permanently locked.
            </p>

            <div className="flex justify-end gap-3">
              <button
                type="button"
                onClick={() => setShowEditConfirm(false)}
                className="rounded-lg bg-white/10 px-4 py-2 text-white"
              >
                Cancel
              </button>

              <button
                type="button"
                onClick={() => {
                  setIsEditing(true)
                  setShowEditConfirm(false)
                }}
                className="rounded-lg bg-blue-500 px-4 py-2 text-white"
              >
                Continue
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}

const AffiliateApplyForm = forwardRef(AffiliateApplyFormInner)
AffiliateApplyForm.displayName = "AffiliateApplyForm"

export default AffiliateApplyForm
