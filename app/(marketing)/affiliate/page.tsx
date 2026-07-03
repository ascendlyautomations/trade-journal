import Link from "next/link"
import CompanyPageShell, { CompanySectionCard } from "@/app/components/marketing/CompanyPageShell"
import { COMMISSION_RATE } from "@/lib/affiliateEarnings"
import { AFFILIATE_PRIMARY_BUTTON_CLASS } from "@/lib/affiliateUi"

const AFFILIATE_APPLY_HREF = "/affiliate/dashboard?apply=true"

export default function AffiliateProgramPage() {
  return (
    <CompanyPageShell
      title="Affiliate Program"
      subtitle="The TradeTraxs Affiliate Program is live — partner with us and earn recurring commissions by referring traders to the platform."
      maxWidthClass="max-w-4xl"
    >
      <div className="space-y-5">
        <CompanySectionCard title="Become a TradeTraxs Affiliate">
          <p>
            The TradeTraxs Affiliate Program is designed for creators, educators, and community
            leaders who want to introduce traders to a modern journaling and social trading
            platform.
          </p>
        </CompanySectionCard>

        <CompanySectionCard title="How It Works">
          <ul className="list-disc space-y-2 pl-5">
            <li>Share your unique referral link with your audience.</li>
            <li>Traders sign up and start their TradeTraxs journey.</li>
            <li>Earn commissions when referred users subscribe to TradeTraxs Pro.</li>
          </ul>
        </CompanySectionCard>

        <CompanySectionCard title="Commission Structure">
          <p>
            Affiliates earn a recurring {Math.round(COMMISSION_RATE * 100)}% commission on
            qualifying Pro subscriptions. Payout details and performance tracking are available
            in your affiliate dashboard after approval.
          </p>
        </CompanySectionCard>

        <CompanySectionCard title="Who It's For">
          <p>
            Trading educators, content creators, community leaders, newsletter writers, and anyone
            with an audience of active or aspiring traders who would benefit from TradeTraxs.
          </p>
        </CompanySectionCard>

        <CompanySectionCard title="Marketing Resources">
          <p>
            Approved affiliates receive brand assets, messaging guidance, and promotional
            resources to help you share TradeTraxs professionally.
          </p>
        </CompanySectionCard>

        <CompanySectionCard title="Requirements">
          <ul className="list-disc space-y-2 pl-5">
            <li>Promote TradeTraxs honestly and professionally.</li>
            <li>Do not make misleading income or performance claims.</li>
            <li>Follow TradeTraxs community and creator guidelines.</li>
            <li>Comply with applicable advertising disclosure requirements.</li>
          </ul>
        </CompanySectionCard>

        <section className="rounded-2xl border border-emerald-400/35 bg-gradient-to-br from-emerald-500/10 via-white/[0.04] to-blue-950/20 p-8 text-center shadow-lg shadow-black/20">
          <h2 className="text-2xl font-semibold text-white md:text-3xl">Sign Up Today!</h2>
          <p className="mx-auto mt-4 max-w-2xl text-sm leading-relaxed text-gray-300 md:text-base">
            Join the TradeTraxs Affiliate Program and start earning commissions by sharing
            TradeTraxs with your audience. Whether you&apos;re a trader, educator, content creator,
            or community leader, it&apos;s easy to get started.
          </p>
          <div className="mt-6 flex flex-col items-center justify-center">
            <Link
              href={AFFILIATE_APPLY_HREF}
              className={`${AFFILIATE_PRIMARY_BUTTON_CLASS} inline-flex min-w-[220px] items-center justify-center px-8 py-3.5 text-base`}
            >
              Become an Affiliate
            </Link>
          </div>
          <p className="mt-4 text-xs text-gray-500">
            Already an approved affiliate?{" "}
            <Link href="/affiliate/dashboard" className="text-blue-300 hover:text-blue-200">
              Open your dashboard
            </Link>
          </p>
        </section>

        <CompanySectionCard title="Why Join?">
          <ul className="list-disc space-y-2 pl-5">
            <li>Earn recurring commissions</li>
            <li>Access your own affiliate dashboard</li>
            <li>Share your unique referral link</li>
            <li>Help traders discover a better way to journal and improve</li>
          </ul>
        </CompanySectionCard>
      </div>
    </CompanyPageShell>
  )
}
