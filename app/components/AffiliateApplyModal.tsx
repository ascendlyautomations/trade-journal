"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { submitAffiliateApplication } from "@/lib/affiliateApplication"

type Props = {
  open: boolean
  onClose: () => void
  onSubmit: () => void | Promise<void>
  title?: string
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

export default function AffiliateApplyModal({
  open,
  onClose,
  onSubmit,
  title = "Affiliate application",
}: Props) {
  const [socialHandle, setSocialHandle] = useState("")
  const [followers, setFollowers] = useState("")
  const [requestedCode, setRequestedCode] = useState("")
  const [busy, setBusy] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)
  const [codeAvailability, setCodeAvailability] = useState<CodeAvailability>("idle")

  useEffect(() => {
    if (!open) {
      setSocialHandle("")
      setFollowers("")
      setRequestedCode("")
      setFormError(null)
      setCodeAvailability("idle")
    }
  }, [open])

  /* Debounced live check while typing */
  useEffect(() => {
    if (!open) return

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
  }, [requestedCode, open])

  if (!open) return null

  const normalizedRequestedCode = normalizeAffiliateRequestedCode(requestedCode)
  const submitDisabled = busy || codeAvailability === "taken"

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setFormError(null)

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
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user?.id) {
      setFormError("Not signed in.")
      setBusy(false)
      return
    }

    const { ok, error } = await submitAffiliateApplication(supabase, user.id, {
      socialHandle: handle,
      followers: n,
      requestedCode: codeForSubmit,
    })

    setBusy(false)
    if (!ok || error) {
      setFormError(error || "Could not submit application.")
      return
    }

    await onSubmit()
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
      <div
        className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-white/10 bg-[#152238] p-6 text-white shadow-2xl"
        role="dialog"
        aria-modal="true"
      >
        <h2 className="text-lg font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          {title}
        </h2>
        <p className="mt-1 text-xs text-gray-400">
          Status updates appear on this page and in Settings → Affiliate.
        </p>

        <form onSubmit={(e) => void handleSubmit(e)} className="mt-4 space-y-3">
          <div>
            <label className="text-xs text-gray-400">Social handle</label>
            <input
              value={socialHandle}
              onChange={(e) => setSocialHandle(e.target.value)}
              required
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-500"
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
              required
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-500"
              placeholder="Approximate follower count"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Requested code (optional)</label>
            <input
              value={requestedCode}
              onChange={(e) => setRequestedCode(e.target.value.toUpperCase())}
              aria-invalid={codeAvailability === "taken"}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 font-mono text-sm text-white placeholder:text-gray-500"
              placeholder="YOURCODE"
            />
            {normalizedRequestedCode ? (
              <div className="mt-1.5 min-h-[1.25rem] text-xs">
                {codeAvailability === "checking" ? (
                  <span className="text-gray-500">Checking availability…</span>
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

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg bg-white/10 px-4 py-2 text-sm hover:bg-white/20"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitDisabled}
              className="rounded-lg bg-gradient-to-r from-blue-500 to-emerald-500 px-5 py-2 text-sm font-semibold disabled:opacity-50"
            >
              {busy ? "Submitting…" : "Submit application"}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
