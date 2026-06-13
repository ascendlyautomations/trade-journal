"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import { useEffect, useState } from "react"
import Navbar from "@/app/components/Navbar"
import BugReportModal from "@/app/components/BugReportModal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { BETA_ROOM_SLUG } from "@/lib/betaHub"
import { submitFeatureRequest } from "@/lib/featureRequests"
import { supabase } from "@/lib/supabaseClient"

export default function BetaHubPage() {
  const router = useRouter()
  const { showPopup, feedbackModalProps } = useFeedbackPopup({ autoDismissMs: 3000 })
  const [checking, setChecking] = useState(true)
  const [userId, setUserId] = useState<string | null>(null)
  const [bugReportOpen, setBugReportOpen] = useState(false)
  const [featureTitle, setFeatureTitle] = useState("")
  const [featureDescription, setFeatureDescription] = useState("")
  const [featureBusy, setFeatureBusy] = useState(false)

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) {
        router.replace("/login")
        return
      }

      const { data: profile, error } = await supabase
        .from("profiles")
        .select("is_beta_tester")
        .eq("id", user.id)
        .maybeSingle()

      if (cancelled) return

      if (error || !profile?.is_beta_tester) {
        router.replace("/dashboard")
        return
      }

      setUserId(user.id)
      setChecking(false)
    })()

    return () => {
      cancelled = true
    }
  }, [router])

  async function handleFeatureSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!userId || featureBusy) return

    setFeatureBusy(true)
    const result = await submitFeatureRequest(userId, {
      title: featureTitle,
      description: featureDescription,
    })
    setFeatureBusy(false)

    if (!result.ok) {
      showPopup({ type: "error", message: result.message })
      return
    }

    setFeatureTitle("")
    setFeatureDescription("")
    showPopup({ type: "success", message: "Feature request submitted. Thank you!" })
  }

  if (checking) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Loading Beta Hub...
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />
      <FeedbackModal {...feedbackModalProps} />
      <BugReportModal open={bugReportOpen} onClose={() => setBugReportOpen(false)} />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
        <div className="mx-auto max-w-3xl space-y-6">
          <div>
            <h1 className="bg-gradient-to-r from-amber-300 to-emerald-400 bg-clip-text text-2xl font-bold text-transparent md:text-3xl">
              TradeTraxs Beta Hub
            </h1>
            <p className="mt-2 text-sm text-gray-300">
              Help shape the product during beta. Report issues, request features, and discuss with the team.
            </p>
          </div>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <h2 className="text-lg font-semibold text-white">Welcome, beta tester</h2>
            <ul className="mt-3 list-inside list-disc space-y-1 text-sm text-gray-300">
              <li>Your feedback directly influences what we build next.</li>
              <li>
                <strong className="text-gray-200">Report bugs</strong> with steps to reproduce and screenshots when
                possible.
              </li>
              <li>
                <strong className="text-gray-200">Request features</strong> using the form below.
              </li>
              <li>
                <strong className="text-gray-200">Join the beta discussion room</strong> for ideas and product chat.
              </li>
            </ul>
          </section>

          <div className="grid gap-4 sm:grid-cols-2">
            <button
              type="button"
              onClick={() => setBugReportOpen(true)}
              className="rounded-xl border border-white/10 bg-white/5 p-4 text-left transition hover:bg-white/10"
            >
              <p className="font-semibold text-white">Report a bug</p>
              <p className="mt-1 text-sm text-gray-400">Opens the existing bug report form with screenshot support.</p>
            </button>
            <Link
              href="/feedback"
              className="rounded-xl border border-white/10 bg-white/5 p-4 transition hover:bg-white/10"
            >
              <p className="font-semibold text-white">Submit feedback</p>
              <p className="mt-1 text-sm text-gray-400">General product feedback via the existing feedback page.</p>
            </Link>
          </div>

          <section className="rounded-xl border border-amber-500/20 bg-amber-500/5 p-5">
            <h2 className="text-lg font-semibold text-amber-100">Feature request</h2>
            <p className="mt-1 text-sm text-gray-400">
              Describe a feature you&apos;d like to see in TradeTraxs.
            </p>
            <form onSubmit={(e) => void handleFeatureSubmit(e)} className="mt-4 space-y-3">
              <input
                type="text"
                placeholder="Title"
                value={featureTitle}
                onChange={(e) => setFeatureTitle(e.target.value)}
                className="w-full rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-amber-400/50"
                maxLength={200}
              />
              <textarea
                placeholder="Description — what problem does this solve? How would it work?"
                value={featureDescription}
                onChange={(e) => setFeatureDescription(e.target.value)}
                rows={5}
                className="w-full resize-y rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-amber-400/50"
              />
              <button
                type="submit"
                disabled={featureBusy}
                className="rounded-lg bg-gradient-to-r from-amber-500 to-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:opacity-90 disabled:opacity-60"
              >
                {featureBusy ? "Submitting..." : "Submit feature request"}
              </button>
            </form>
          </section>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <h2 className="text-lg font-semibold text-white">Beta discussion</h2>
            <p className="mt-1 text-sm text-gray-400">
              Chat with other beta testers about bugs, ideas, and product direction.
            </p>
            <Link
              href={`/trade-rooms?room=${encodeURIComponent(BETA_ROOM_SLUG)}`}
              className="mt-4 inline-block rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
            >
              Join Beta Discussion
            </Link>
          </section>
        </div>
      </div>
    </>
  )
}
