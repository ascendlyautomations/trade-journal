"use client"

import CompanyPageShell, { CompanySectionCard } from "@/app/components/marketing/CompanyPageShell"
import AffiliateProgramCtaSection from "@/app/components/marketing/AffiliateProgramCtaSection"
import AffiliateProgramHeroApplyButton from "@/app/components/marketing/AffiliateProgramHeroApplyButton"
import { AffiliateProgramApplyProvider } from "@/app/components/marketing/AffiliateProgramApplyContext"
import { COMMISSION_RATE } from "@/lib/affiliateEarnings"

export default function AffiliateProgramPageClient() {
  return (
    <AffiliateProgramApplyProvider>
      <CompanyPageShell
        title="Affiliate Program"
        subtitle="The TradeTraxs Affiliate Program is live — partner with us and earn recurring commissions by referring traders to the platform."
        maxWidthClass="max-w-4xl"
        heroActions={<AffiliateProgramHeroApplyButton />}
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

          <AffiliateProgramCtaSection />

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
    </AffiliateProgramApplyProvider>
  )
}
