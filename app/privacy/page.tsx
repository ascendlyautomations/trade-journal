import LegalDocumentLayout from "@/app/components/LegalDocumentLayout"
import { PRIVACY_POLICY_SECTIONS } from "@/lib/legal/privacyPolicyContent"

export default function PrivacyPolicyPage() {
  return (
    <LegalDocumentLayout
      title="Privacy Policy"
      subtitle="How TradeTraxs collects, uses, and protects your information."
      sections={PRIVACY_POLICY_SECTIONS}
      relatedHref={{ href: "/terms", label: "Terms of Service" }}
    />
  )
}
