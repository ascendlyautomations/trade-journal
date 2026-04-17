"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { submitAffiliateApplication } from "@/lib/affiliateApplication"

type Props = {
  open: boolean
  onClose: () => void
  onSubmit: () => void | Promise<void>
  defaultFullName?: string
  defaultEmail?: string | null
  title?: string
}

export default function AffiliateApplyModal({
  open,
  onClose,
  onSubmit,
  defaultFullName = "",
  defaultEmail,
  title = "Affiliate application",
}: Props) {
  const [fullName, setFullName] = useState(defaultFullName)
  const [email, setEmail] = useState(defaultEmail ?? "")
  const [platform, setPlatform] = useState("")
  const [audienceSize, setAudienceSize] = useState("")
  const [socialHandle, setSocialHandle] = useState("")
  const [whyJoin, setWhyJoin] = useState("")
  const [promoPlan, setPromoPlan] = useState("")
  const [requestedCode, setRequestedCode] = useState("")
  const [busy, setBusy] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)

  useEffect(() => {
    setFullName(defaultFullName)
  }, [defaultFullName, open])

  useEffect(() => {
    setEmail(defaultEmail ?? "")
  }, [defaultEmail, open])

  useEffect(() => {
    if (!open) {
      setPlatform("")
      setAudienceSize("")
      setSocialHandle("")
      setWhyJoin("")
      setPromoPlan("")
      setRequestedCode("")
      setFormError(null)
    }
  }, [open])

  if (!open) return null

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setFormError(null)
    if (!whyJoin.trim()) {
      setFormError("Please tell us why you’d like to join.")
      return
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
      email: user.email ?? (email.trim() || null),
      fullName: fullName.trim() || null,
      socialHandle: socialHandle.trim() || null,
      platform: platform.trim() || null,
      audienceSize: audienceSize.trim() || null,
      whyJoin: whyJoin.trim(),
      promoPlan: promoPlan.trim() || null,
      requestedCode: requestedCode.trim() || null,
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
          We review every application. You’ll see status here and in Settings → Affiliate.
        </p>

        <form onSubmit={(e) => void handleSubmit(e)} className="mt-4 space-y-3">
          <div>
            <label className="text-xs text-gray-400">Full name</label>
            <input
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-500"
              placeholder="Your name"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Email</label>
            <input
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              readOnly={Boolean(defaultEmail)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-500 read-only:opacity-80"
              placeholder="Email"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Primary platform</label>
            <input
              value={platform}
              onChange={(e) => setPlatform(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-500"
              placeholder="e.g. X, YouTube, TikTok, Discord"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Audience size (approx.)</label>
            <input
              value={audienceSize}
              onChange={(e) => setAudienceSize(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-500"
              placeholder="e.g. 5k followers, 12k subscribers"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Social handle / link</label>
            <input
              value={socialHandle}
              onChange={(e) => setSocialHandle(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-500"
              placeholder="@handle or profile URL"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Why do you want to join?</label>
            <textarea
              value={whyJoin}
              onChange={(e) => setWhyJoin(e.target.value)}
              rows={4}
              required
              className="mt-1 w-full resize-none rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-500"
              placeholder="Tell us how you’ll promote TradeTrax…"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Promotion plan (optional)</label>
            <textarea
              value={promoPlan}
              onChange={(e) => setPromoPlan(e.target.value)}
              rows={2}
              className="mt-1 w-full resize-none rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm text-white placeholder:text-gray-500"
              placeholder="Short plan, content types, timeline…"
            />
          </div>
          <div>
            <label className="text-xs text-gray-400">Requested code (optional)</label>
            <input
              value={requestedCode}
              onChange={(e) => setRequestedCode(e.target.value.toUpperCase())}
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 font-mono text-sm text-white placeholder:text-gray-500"
              placeholder="YOURCODE — subject to approval"
            />
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
              disabled={busy}
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
