"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import { useEffect, useRef, useState } from "react"
import Navbar from "@/app/components/Navbar"
import BugReportModal from "@/app/components/BugReportModal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { BETA_ROOM_SLUG } from "@/lib/betaHub"
import { submitFeatureRequest } from "@/lib/featureRequests"
import { supabase } from "@/lib/supabaseClient"

const ACTION_CARD_CLASS =
  "group flex h-full cursor-pointer flex-col rounded-xl border border-white/15 bg-white/[0.06] p-5 text-left shadow-md transition-all duration-200 hover:scale-[1.02] hover:border-white/25 hover:bg-white/[0.12] hover:shadow-lg motion-reduce:hover:scale-100"

const ACTION_CTA_CLASS =
  "mt-auto inline-flex w-full items-center justify-center rounded-lg border border-white/20 bg-white/10 px-4 py-2.5 text-sm font-semibold text-white transition group-hover:border-white/30 group-hover:bg-white/15"

const PRIMARY_CTA_CLASS =
  "w-full rounded-lg bg-gradient-to-r from-amber-500 to-amber-600 px-4 py-2.5 text-sm font-semibold text-white shadow-md shadow-amber-900/30 transition hover:scale-[1.02] hover:from-amber-400 hover:to-amber-500 hover:shadow-lg hover:shadow-amber-900/40 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:scale-100 motion-reduce:hover:scale-100 sm:w-auto"

function DiscussionIcon({ className }: { className?: string }) {
  return (
    <svg className={className} width="24" height="24" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M21 15a4 4 0 0 1-4 4H8l-5 3v-7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4zM17 3H7a4 4 0 0 0-4 4v10"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export default function BetaHubPage() {
  const router = useRouter()
  const { showPopup, feedbackModalProps } = useFeedbackPopup({ autoDismissMs: 3000 })
  const [checking, setChecking] = useState(true)
  const [userId, setUserId] = useState<string | null>(null)
  const [bugReportOpen, setBugReportOpen] = useState(false)
  const [featureTitle, setFeatureTitle] = useState("")
  const [featureDescription, setFeatureDescription] = useState("")
  const [featureBusy, setFeatureBusy] = useState(false)
  const featureSubmittingRef = useRef(false)

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
    if (!userId || featureSubmittingRef.current || featureBusy) return

    featureSubmittingRef.current = true
    setFeatureBusy(true)

    try {
    const result = await submitFeatureRequest(userId, {
      title: featureTitle,
      description: featureDescription,
    })

    if (!result.ok) {
      showPopup({ type: "error", message: result.message })
      return
    }

    setFeatureTitle("")
    setFeatureDescription("")
    showPopup({ type: "success", message: "Feature request submitted. Thank you!" })
    } finally {
      featureSubmittingRef.current = false
      setFeatureBusy(false)
    }
  }

  function joinBetaDiscussion() {
    router.push(`/trade-rooms?room=${encodeURIComponent(BETA_ROOM_SLUG)}`)
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

          <section className="w-full rounded-xl border border-amber-400/45 bg-gradient-to-br from-amber-500/15 via-amber-900/10 to-emerald-950/20 p-6 shadow-[0_8px_32px_rgba(0,0,0,0.25),0_0_40px_rgba(245,158,11,0.14)]">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-start">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl border border-amber-400/40 bg-amber-500/20 text-amber-200">
                <DiscussionIcon className="h-6 w-6" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-lg font-semibold text-amber-50">Beta Discussion</h2>
                  <span className="rounded border border-amber-400/30 bg-amber-500/20 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-200">
                    Primary
                  </span>
                </div>
                <p className="mt-2 text-sm leading-relaxed text-amber-100/80">
                  Join the TradeTraxs Beta room to discuss bugs, feature ideas, and platform improvements with other
                  beta testers.
                </p>
                <button
                  type="button"
                  onClick={joinBetaDiscussion}
                  className={`mt-4 ${PRIMARY_CTA_CLASS}`}
                >
                  Join Beta Discussion
                </button>
              </div>
            </div>
          </section>

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
                className={PRIMARY_CTA_CLASS}
              >
                {featureBusy ? "Submitting..." : "Submit Feature Request"}
              </button>
            </form>
          </section>

          <div className="grid gap-4 sm:grid-cols-2">
            <button
              type="button"
              onClick={() => setBugReportOpen(true)}
              className={ACTION_CARD_CLASS}
            >
              <p className="font-semibold text-white">Report Bug</p>
              <p className="mt-2 mb-5 flex-1 text-sm text-gray-400">
                Opens the existing bug report form with screenshot support.
              </p>
              <span className={ACTION_CTA_CLASS}>Open Bug Report</span>
            </button>
            <Link href="/feedback" className={ACTION_CARD_CLASS}>
              <p className="font-semibold text-white">Submit Feedback</p>
              <p className="mt-2 mb-5 flex-1 text-sm text-gray-400">
                General product feedback via the existing feedback page.
              </p>
              <span className={ACTION_CTA_CLASS}>Leave Feedback</span>
            </Link>
          </div>
        </div>
      </div>
    </>
  )
}
