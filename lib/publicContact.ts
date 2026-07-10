import type { AdminSubmissionType } from "@/lib/adminSubmissionTypes"

export type PublicContactCategory = "general" | "billing" | "partnership" | "business" | "faq"

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

/** FAQ page “Send a Question” — not listed on the public contact page cards. */
export const FAQ_CONTACT_CATEGORY: PublicContactCategoryConfig = {
  category: "faq",
  title: "FAQ Question",
  description: "Couldn't find what you need in the FAQ? Send us your question.",
  subject: "FAQ Question",
  cta: "Send a Question",
}

export const PUBLIC_CONTACT_CATEGORY_LABELS: Record<PublicContactCategory, string> = {
  general: "General Questions",
  billing: "Billing",
  partnership: "Partnerships",
  business: "Business Inquiries",
  faq: "FAQ Question",
}

export const PUBLIC_CONTACT_SUBJECTS: Record<PublicContactCategory, string> = {
  general: "[General] Question About TradeTraxs",
  billing: "[Billing] Subscription Question",
  partnership: "[Partnership] Partnership Inquiry",
  business: "[Business] Business Inquiry",
  faq: "FAQ Question",
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
