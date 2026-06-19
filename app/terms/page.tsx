import LegalDocumentLayout from "@/app/components/LegalDocumentLayout"
import { TERMS_OF_SERVICE_SECTIONS } from "@/lib/legal/termsOfServiceContent"

export default function TermsOfServicePage() {
  return (
    <LegalDocumentLayout
      title="Terms of Service"
      subtitle="Rules and conditions for using TradeTraxs."
      sections={TERMS_OF_SERVICE_SECTIONS}
      relatedHref={{ href: "/privacy", label: "Privacy Policy" }}
    />
  )
}
