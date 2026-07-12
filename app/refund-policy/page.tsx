import LegalDocumentLayout from "@/app/components/LegalDocumentLayout"
import { REFUND_POLICY_SECTIONS } from "@/lib/legal/refundPolicyContent"

export default function RefundPolicyPage() {
  return (
    <LegalDocumentLayout
      title="Refund Policy"
      subtitle="How TradeTraxs handles subscription billing, cancellation, and refunds."
      sections={REFUND_POLICY_SECTIONS}
      relatedHref={{ href: "/terms", label: "Terms of Service" }}
    />
  )
}
