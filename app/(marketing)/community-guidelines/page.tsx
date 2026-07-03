import CompanyPageShell, { CompanySectionCard } from "@/app/components/marketing/CompanyPageShell"

const SECTIONS = [
  {
    id: "mission",
    title: "Our Mission",
    body: (
      <>
        <p>
          TradeTraxs exists to help traders learn, improve, and grow together. Our community is
          built on accountability, education, and respect — whether you are sharing a trade,
          asking for feedback, or celebrating progress.
        </p>
        <p>
          These guidelines help keep TradeTraxs welcoming, constructive, and safe for every
          trader.
        </p>
      </>
    ),
  },
  {
    id: "respect",
    title: "Respect Other Traders",
    body: (
      <p>
        Treat fellow traders with courtesy. Disagree with ideas, not people. Personal attacks,
        bullying, and demeaning language are not welcome on TradeTraxs.
      </p>
    ),
  },
  {
    id: "feedback",
    title: "Constructive Feedback",
    body: (
      <p>
        Share feedback that helps others improve. Be specific, thoughtful, and professional —
        especially when commenting on trades, journals, or shared performance.
      </p>
    ),
  },
  {
    id: "harassment",
    title: "No Harassment",
    body: (
      <p>
        Harassment, threats, intimidation, and targeted abuse are prohibited. This includes
        repeated unwanted contact, doxxing, and coordinated pile-ons.
      </p>
    ),
  },
  {
    id: "spam",
    title: "No Spam",
    body: (
      <p>
        Do not post repetitive promotions, unsolicited links, referral spam, or low-quality content
        designed only to drive traffic elsewhere.
      </p>
    ),
  },
  {
    id: "fake-results",
    title: "No Fake Results",
    body: (
      <p>
        Do not misrepresent trades, performance, account status, or outcomes. Authenticity builds
        trust across the community.
      </p>
    ),
  },
  {
    id: "manipulation",
    title: "No Market Manipulation",
    body: (
      <p>
        Do not use TradeTraxs to coordinate pump-and-dump activity, spread false market
        information, or encourage harmful trading behavior.
      </p>
    ),
  },
  {
    id: "hate-speech",
    title: "No Hate Speech",
    body: (
      <p>
        Content that promotes hatred or violence against individuals or groups based on protected
        characteristics is not permitted.
      </p>
    ),
  },
  {
    id: "nsfw",
    title: "No NSFW Content",
    body: (
      <p>
        TradeTraxs is a professional trading platform. Sexually explicit, graphic, or otherwise
        not-safe-for-work content is not allowed.
      </p>
    ),
  },
  {
    id: "reporting",
    title: "Reporting Violations",
    body: (
      <p>
        If you see behavior that violates these guidelines, report it through support or contact
        our team at{" "}
        <a href="mailto:support@tradetraxs.com" className="text-blue-300 hover:text-blue-200">
          support@tradetraxs.com
        </a>
        . Include links, screenshots, and context when possible.
      </p>
    ),
  },
  {
    id: "consequences",
    title: "Consequences",
    body: (
      <p>
        Violations may result in content removal, feature restrictions, temporary suspension, or
        permanent account termination depending on severity and history. TradeTraxs may take
        action at its discretion to protect the community.
      </p>
    ),
  },
] as const

export default function CommunityGuidelinesPage() {
  return (
    <CompanyPageShell
      title="Community Guidelines"
      subtitle="Professional standards for traders connecting, sharing, and learning together on TradeTraxs."
    >
      <div className="space-y-5">
        {SECTIONS.map((section) => (
          <CompanySectionCard key={section.id} id={section.id} title={section.title}>
            {section.body}
          </CompanySectionCard>
        ))}
      </div>
    </CompanyPageShell>
  )
}
