import LegalDocumentLayout from "@/app/components/LegalDocumentLayout"
import { ACCEPTABLE_USE_POLICY_SECTIONS } from "@/lib/legal/acceptableUsePolicyContent"

export default function AcceptableUsePolicyPage() {
  return (
    <LegalDocumentLayout
      title="Acceptable Use Policy"
      subtitle="Standards for acceptable behavior and platform use on TradeTraxs."
      sections={ACCEPTABLE_USE_POLICY_SECTIONS}
      relatedHref={{ href: "/terms", label: "Terms of Service" }}
    />
  )
}
