import CompanyPageShell, { CompanyDocumentCard } from "@/app/components/marketing/CompanyPageShell"

const LEGAL_DOCUMENTS = [
  {
    title: "Privacy Policy",
    description:
      "How TradeTraxs collects, uses, stores, and protects your account, trading, and community data.",
    href: "/privacy",
  },
  {
    title: "Terms of Service",
    description:
      "The rules governing your TradeTraxs account, subscriptions, user content, and use of the platform.",
    href: "/terms",
  },
  {
    title: "Cookie Policy",
    description:
      "How TradeTraxs uses cookies and similar technologies to operate and improve the service.",
    href: "/cookie-policy",
  },
  {
    title: "Acceptable Use Policy",
    description:
      "Standards for acceptable behavior, content, and platform use across TradeTraxs products.",
    href: "/acceptable-use",
  },
] as const

export default function LegalHubPage() {
  return (
    <CompanyPageShell
      title="Legal"
      subtitle="Find TradeTraxs legal documents, policies, and platform terms in one place."
      maxWidthClass="max-w-4xl"
    >
      <div className="grid gap-4 sm:grid-cols-2">
        {LEGAL_DOCUMENTS.map((doc) => (
          <CompanyDocumentCard
            key={doc.title}
            title={doc.title}
            description={doc.description}
            href={"href" in doc ? doc.href : undefined}
            comingSoon={"comingSoon" in doc ? doc.comingSoon : false}
          />
        ))}
      </div>
    </CompanyPageShell>
  )
}
