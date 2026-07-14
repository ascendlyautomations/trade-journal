"use client"

import { useState } from "react"
import { CompanySectionCard } from "@/app/components/marketing/CompanyPageShell"
import ContactFormModal from "@/app/components/marketing/ContactFormModal"
import { SUPPORT_EMAIL } from "@/lib/contactEmails"
import {
  PUBLIC_CONTACT_CATEGORIES,
  type PublicContactCategoryConfig,
} from "@/lib/publicContact"

const ACTION_BUTTON_CLASS =
  "mt-4 inline-flex w-full items-center justify-center gap-1 rounded-xl border border-white/15 bg-white/[0.08] px-4 py-2.5 text-sm font-semibold text-white transition hover:border-blue-400/30 hover:bg-white/[0.12]"

export default function ContactPageContent() {
  const [activeCategory, setActiveCategory] =
    useState<PublicContactCategoryConfig | null>(null)

  return (
    <>
      <div className="mb-5 rounded-xl border border-white/10 bg-white/[0.06] p-6 text-center shadow-lg shadow-black/20 md:mb-8">
        <p className="text-sm text-gray-400">Email us anytime</p>
        <p className="mt-2 text-xl font-semibold text-blue-300">{SUPPORT_EMAIL}</p>
      </div>

      <div className="grid gap-5 md:grid-cols-2">
        {PUBLIC_CONTACT_CATEGORIES.map((category) => (
          <CompanySectionCard key={category.category} title={category.title}>
            <p>{category.description}</p>
            <button
              type="button"
              onClick={() => setActiveCategory(category)}
              className={ACTION_BUTTON_CLASS}
            >
              {category.cta}
              <span aria-hidden>→</span>
            </button>
          </CompanySectionCard>
        ))}
      </div>

      <ContactFormModal
        open={activeCategory != null}
        category={activeCategory}
        onClose={() => setActiveCategory(null)}
      />
    </>
  )
}
