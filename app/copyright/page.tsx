import LegalDocumentLayout from "@/app/components/LegalDocumentLayout"
import { COPYRIGHT_DMCA_SECTIONS } from "@/lib/legal/copyrightDmcaContent"

export default function CopyrightPolicyPage() {
  return (
    <LegalDocumentLayout
      title="Copyright & DMCA Policy"
      subtitle="How to report copyright infringement and submit counter-notifications on TradeTraxs."
      sections={COPYRIGHT_DMCA_SECTIONS}
      relatedHref={{ href: "/terms", label: "Terms of Service" }}
    />
  )
}
