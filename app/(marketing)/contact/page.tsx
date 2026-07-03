import CompanyPageShell from "@/app/components/marketing/CompanyPageShell"
import ContactPageContent from "./ContactPageContent"

export default function ContactPage() {
  return (
    <CompanyPageShell
      title="Contact"
      subtitle="Reach the TradeTraxs team for billing, partnerships, business inquiries, and general questions."
      maxWidthClass="max-w-4xl"
    >
      <ContactPageContent />
    </CompanyPageShell>
  )
}
