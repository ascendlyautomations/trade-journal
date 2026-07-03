"use client"

import Link from "next/link"
import { useEffect, useRef, useState } from "react"
import AffiliateApplyForm, {
  type AffiliateApplyFormHandle,
} from "@/app/components/AffiliateApplyForm"
import { useAffiliateProgramApply } from "@/app/components/marketing/AffiliateProgramApplyContext"
import { AFFILIATE_PRIMARY_BUTTON_CLASS } from "@/lib/affiliateUi"
import {
  fetchLatestAffiliateApplication,
  type AffiliateApplicationRow,
} from "@/lib/affiliateApplication"
import { supabase } from "@/lib/supabaseClient"
import { useUserProfile } from "@/lib/useUserProfile"

const LOGGED_OUT_SIGNUP_HREF =
  "/login?tab=signup&next=%2Faffiliate%2Fdashboard%3Fapply%3Dtrue"

function pendingViewOnly(app: AffiliateApplicationRow | null): boolean {
  return Boolean(app?.status === "pending" && !app.has_edited)
}

export default function AffiliateProgramCtaSection() {
  const { user, loading: authLoading } = useUserProfile()
  const { expanded, setExpanded, scrollToApplication, registerFocusFirstField } =
    useAffiliateProgramApply()
  const formRef = useRef<AffiliateApplyFormHandle>(null)
  const [latestApp, setLatestApp] = useState<AffiliateApplicationRow | null>(null)

  const isLoggedIn = Boolean(user?.id)
  const isPending = latestApp?.status === "pending"
  const applicationLocked = Boolean(isPending && latestApp?.has_edited)

  useEffect(() => {
    if (!user?.id) {
      setLatestApp(null)
      return
    }

    let cancelled = false
    void fetchLatestAffiliateApplication(supabase, user.id).then((app) => {
      if (!cancelled) {
        setLatestApp(app)
        setExpanded(!pendingViewOnly(app))
      }
    })

    return () => {
      cancelled = true
    }
  }, [user?.id, setExpanded])

  useEffect(() => {
    registerFocusFirstField(() => {
      formRef.current?.focusFirstField()
    })
    return () => registerFocusFirstField(null)
  }, [registerFocusFirstField, expanded])

  async function afterSubmit() {
    if (!user?.id) return
    const app = await fetchLatestAffiliateApplication(supabase, user.id)
    setLatestApp(app)
    setExpanded(!pendingViewOnly(app))
  }

  return (
    <>
      <section className="rounded-2xl border border-emerald-400/35 bg-gradient-to-br from-emerald-500/10 via-white/[0.04] to-blue-950/20 p-8 text-center shadow-lg shadow-black/20">
        <h2 className="text-2xl font-semibold text-white md:text-3xl">
          {isLoggedIn ? "Ready to Apply?" : "Sign Up Today!"}
        </h2>
        <p className="mx-auto mt-4 max-w-2xl text-sm leading-relaxed text-gray-300 md:text-base">
          Join the TradeTraxs Affiliate Program and start earning commissions by sharing
          TradeTraxs with your audience. Whether you&apos;re a trader, educator, content creator,
          or community leader, it&apos;s easy to get started.
        </p>
        <div className="mt-6 flex flex-col items-center justify-center">
          {isLoggedIn ? (
            <button
              type="button"
              onClick={scrollToApplication}
              disabled={authLoading}
              className={`${AFFILIATE_PRIMARY_BUTTON_CLASS} inline-flex min-w-[220px] items-center justify-center px-8 py-3.5 text-base disabled:cursor-not-allowed disabled:opacity-60`}
            >
              Apply to Become an Affiliate
            </button>
          ) : (
            <Link
              href={LOGGED_OUT_SIGNUP_HREF}
              className={`${AFFILIATE_PRIMARY_BUTTON_CLASS} inline-flex min-w-[220px] items-center justify-center px-8 py-3.5 text-base`}
            >
              Sign Up Today
            </Link>
          )}
        </div>
        <p className="mt-4 text-xs text-gray-500">
          Already an approved affiliate?{" "}
          <Link href="/affiliate/dashboard" className="text-blue-300 hover:text-blue-200">
            Open your dashboard
          </Link>
        </p>
      </section>

      {isLoggedIn ? (
        <section
          id="affiliate-application"
          className="scroll-mt-28 rounded-xl border border-white/10 bg-[#1e293b]/60 p-6 shadow-lg shadow-black/10 md:p-8"
        >
          {!expanded ? (
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div className="text-left">
                <h2 className="text-xl font-semibold text-white">Affiliate Application</h2>
                <p className="mt-2 text-sm text-gray-400">
                  {latestApp?.status === "pending"
                    ? "Your application has been submitted and is under review."
                    : "Complete your affiliate application below."}
                </p>
              </div>
              <button
                type="button"
                onClick={() => {
                  setExpanded(true)
                  window.requestAnimationFrame(() => {
                    formRef.current?.focusFirstField()
                  })
                }}
                className={`${AFFILIATE_PRIMARY_BUTTON_CLASS} shrink-0 px-5 py-2.5`}
              >
                View Application
              </button>
            </div>
          ) : (
            <AffiliateApplyForm
              ref={formRef}
              active
              prefillFrom={latestApp}
              title={applicationLocked ? "View application" : "Affiliate application"}
              onSubmit={() => void afterSubmit()}
              showCancel={false}
            />
          )}
        </section>
      ) : null}
    </>
  )
}
