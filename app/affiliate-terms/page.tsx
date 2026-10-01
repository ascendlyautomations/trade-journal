import LegalDocumentLayout from "@/app/components/LegalDocumentLayout"
import { AFFILIATE_TERMS_SECTIONS } from "@/lib/legal/affiliateTermsContent"

export default function AffiliateTermsPage() {
  return (
    <LegalDocumentLayout
      title="Affiliate Terms"
      subtitle="Rules for participating in the TradeTraxs Affiliate Program."
      sections={AFFILIATE_TERMS_SECTIONS}
      relatedHref={{ href: "/terms", label: "Terms of Service" }}
    />
  )
}
