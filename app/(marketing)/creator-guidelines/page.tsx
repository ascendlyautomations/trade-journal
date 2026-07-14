import CompanyPageShell, { CompanySectionCard } from "@/app/components/marketing/CompanyPageShell"

const SECTIONS = [
  {
    id: "overview",
    title: "Share With Purpose",
    body: (
      <>
        <p>
          TradeTraxs creators share trades, posts, and clips to educate, document progress, and
          build authentic trading journeys. Your content helps others learn, and reflects on the
          community as a whole.
        </p>
        <p>
          These guidelines apply to all public content you publish on TradeTraxs.
        </p>
      </>
    ),
  },
  {
    id: "educational",
    title: "Share Educational Content",
    body: (
      <p>
        Focus on process, context, and lessons learned. Explain your setup, risk management, and
        reasoning when sharing trades or breakdowns so others can learn responsibly.
      </p>
    ),
  },
  {
    id: "transparent",
    title: "Be Transparent",
    body: (
      <p>
        Present your results honestly. Disclose simulated, replay, or partial data when relevant.
        Do not imply guaranteed outcomes or hide material context behind selective screenshots.
      </p>
    ),
  },
  {
    id: "claims",
    title: "Avoid Misleading Performance Claims",
    body: (
      <p>
        Do not cherry-pick wins, exaggerate returns, or present unverified performance as typical.
        Past results are not guarantees of future performance.
      </p>
    ),
  },
  {
    id: "copyright",
    title: "Respect Copyright",
    body: (
      <p>
        Only upload content you have the right to share. Do not repost charts, videos, or media
        from other creators or platforms without permission. To report infringement, see our{" "}
        <a href="/copyright" className="text-blue-300 hover:text-blue-200">
          Copyright &amp; DMCA Policy
        </a>
        .
      </p>
    ),
  },
  {
    id: "professional",
    title: "Keep Content Professional",
    body: (
      <p>
        Maintain a tone appropriate for a trading community. Avoid sensationalism, clickbait, and
        content that could mislead newer traders.
      </p>
    ),
  },
  {
    id: "scams",
    title: "No Scams",
    body: (
      <p>
        Do not promote fraudulent services, signal-selling schemes, guaranteed-profit programs, or
        any activity designed to deceive other users.
      </p>
    ),
  },
  {
    id: "impersonation",
    title: "No Impersonation",
    body: (
      <p>
        Do not impersonate other traders, brands, educators, or TradeTraxs staff. Use your real
        identity and represent your own work accurately.
      </p>
    ),
  },
  {
    id: "authentic",
    title: "Encourage Authentic Journeys",
    body: (
      <p>
        The best creator content documents real growth. Wins, losses, and the work in between.
        TradeTraxs is built for traders who value honesty over hype.
      </p>
    ),
  },
] as const

export default function CreatorGuidelinesPage() {
  return (
    <CompanyPageShell
      title="Creator Guidelines"
      subtitle="Best practices for sharing trades, posts, and clips on TradeTraxs with integrity."
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
