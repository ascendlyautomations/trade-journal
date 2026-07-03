import LegalDocumentLayout from "@/app/components/LegalDocumentLayout"
import { COOKIE_POLICY_SECTIONS } from "@/lib/legal/cookiePolicyContent"

export default function CookiePolicyPage() {
  return (
    <LegalDocumentLayout
      title="Cookie Policy"
      subtitle="How TradeTraxs uses cookies and similar technologies."
      sections={COOKIE_POLICY_SECTIONS}
      relatedHref={{ href: "/privacy", label: "Privacy Policy" }}
    />
  )
}
