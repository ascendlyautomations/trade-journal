import type { AdminSubmissionType } from "@/lib/adminSubmissionTypes"

export type PublicContactCategory = "general" | "billing" | "partnership" | "business"

export type PublicContactCategoryConfig = {
  category: PublicContactCategory
  title: string
  description: string
  subject: string
  cta: string
}

export const PUBLIC_CONTACT_CATEGORIES: PublicContactCategoryConfig[] = [
  {
    category: "general",
    title: "General Questions",
    description: "Questions about TradeTraxs before getting started.",
    subject: "[General] Question About TradeTraxs",
    cta: "Ask a Question",
  },
  {
    category: "billing",
    title: "Billing",
    description:
      "Questions about subscriptions, invoices, payments, or billing.",
    subject: "[Billing] Subscription Question",
    cta: "Email Support",
  },
  {
    category: "partnership",
    title: "Partnerships",
    description: "Interested in partnering with TradeTraxs?",
    subject: "[Partnership] Partnership Inquiry",
    cta: "Contact Us",
  },
  {
    category: "business",
    title: "Business Inquiries",
    description: "Business opportunities, media, or general inquiries.",
    subject: "[Business] Business Inquiry",
    cta: "Email Us",
  },
]

export const PUBLIC_CONTACT_CATEGORY_LABELS: Record<PublicContactCategory, string> = {
  general: "General Questions",
  billing: "Billing",
  partnership: "Partnerships",
  business: "Business Inquiries",
}

export const PUBLIC_CONTACT_SUBJECTS: Record<PublicContactCategory, string> = {
  general: "[General] Question About TradeTraxs",
  billing: "[Billing] Subscription Question",
  partnership: "[Partnership] Partnership Inquiry",
  business: "[Business] Business Inquiry",
}

export function publicContactAdminType(
  category: PublicContactCategory
): AdminSubmissionType {
  return `contact_${category}` as AdminSubmissionType
}

export type SubmitPublicContactInput = {
  category: PublicContactCategory
  name: string
  email: string
  subject: string
  message: string
}

export async function submitPublicContact(
  input: SubmitPublicContactInput
): Promise<{ ok: true } | { ok: false; message: string }> {
  const res = await fetch("/api/contact", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  })

  let data: { error?: string } = {}
  try {
    data = (await res.json()) as { error?: string }
  } catch {
    // ignore parse errors
  }

  if (!res.ok) {
    return { ok: false, message: data.error || "Failed to send message. Please try again." }
  }

  return { ok: true }
}
