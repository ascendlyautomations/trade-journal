"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import { useEffect, useState } from "react"
import UserReviewModal from "@/app/components/beta/UserReviewModal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { BETA_ROOM_SLUG } from "@/lib/betaHub"
import { useUserProfile } from "@/lib/useUserProfile"

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
  const { user, profile, loading } = useUserProfile()
  const { feedbackModalProps } = useFeedbackPopup({ autoDismissMs: 3000 })
  const [checking, setChecking] = useState(true)
  const [userId, setUserId] = useState<string | null>(null)
  const [reviewModalOpen, setReviewModalOpen] = useState(false)

  useEffect(() => {
    if (loading) return

    if (!user) {
      router.replace("/")
      return
    }

    if (!profile?.is_beta_tester) {
      router.replace("/dashboard")
      return
    }

    setUserId(user.id)
    setChecking(false)
  }, [loading, user, profile?.is_beta_tester, router])

  function joinBetaDiscussion() {
    router.push(`/trade-rooms?room=${encodeURIComponent(BETA_ROOM_SLUG)}`)
  }

  if (checking) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Loading Beta Hub...
        </div>
      </>
    )
  }

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <UserReviewModal
        open={reviewModalOpen}
        userId={userId}
        onClose={() => setReviewModalOpen(false)}
      />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
        <div className="mx-auto max-w-3xl space-y-6">
          <div>
            <h1 className="text-2xl font-bold text-blue-300 md:text-3xl">
              TradeTraxs Beta Hub
            </h1>
            <p className="mt-2 text-sm text-gray-300">
              Help shape the product during beta. Share feedback, request features, and discuss with the team.
            </p>
          </div>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <h2 className="text-lg font-semibold text-white">Welcome, beta tester</h2>
            <ul className="mt-3 list-inside list-disc space-y-1 text-sm text-gray-300">
              <li>Your feedback directly influences what we build next.</li>
              <li>
                <strong className="text-gray-200">Share feedback</strong> or{" "}
                <Link href="/support" className="text-blue-300 underline hover:text-blue-200">
                  contact support
                </Link>{" "}
                for issues, with steps to reproduce and screenshots when possible.
              </li>
              <li>
                <strong className="text-gray-200">Request features</strong> on the{" "}
                <Link href="/feature-requests" className="text-blue-300 underline hover:text-blue-200">
                  Feature Requests
                </Link>{" "}
                page.
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

          <div className="grid gap-4 sm:grid-cols-2">
            <button
              type="button"
              onClick={() => setReviewModalOpen(true)}
              className={ACTION_CARD_CLASS}
            >
              <p className="font-semibold text-white">Leave a Review</p>
              <p className="mt-2 mb-5 flex-1 text-sm text-gray-400">
                Tell us what you honestly think about TradeTraxs. Your review may be featured on
                our homepage.
              </p>
              <span className={ACTION_CTA_CLASS}>Submit Review</span>
            </button>
            <Link href="/feedback" className={ACTION_CARD_CLASS}>
              <p className="font-semibold text-white">Submit Feedback</p>
              <p className="mt-2 mb-5 flex-1 text-sm text-gray-400">
                General product feedback via the dedicated feedback page.
              </p>
              <span className={ACTION_CTA_CLASS}>Leave Feedback</span>
            </Link>
            <Link href="/feature-requests" className={ACTION_CARD_CLASS}>
              <p className="font-semibold text-white">Feature Requests</p>
              <p className="mt-2 mb-5 flex-1 text-sm text-gray-400">
                Suggest new features and track your recent requests.
              </p>
              <span className={ACTION_CTA_CLASS}>Submit Feature Request</span>
            </Link>
          </div>
        </div>
      </div>
    </>
  )
}
