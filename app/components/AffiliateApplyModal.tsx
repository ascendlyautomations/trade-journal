"use client"

import AffiliateApplyForm from "@/app/components/AffiliateApplyForm"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import type { AffiliateApplicationRow } from "@/lib/affiliateApplication"

type Props = {
  open: boolean
  onClose: () => void
  onSubmit: () => void | Promise<void>
  title?: string
  prefillFrom?: AffiliateApplicationRow | null
}

export default function AffiliateApplyModal({
  open,
  onClose,
  onSubmit,
  title = "Affiliate application",
  prefillFrom = null,
}: Props) {
  if (!open) return null

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
      <div
        className="relative max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-white/10 bg-[#152238] p-6 text-white shadow-2xl"
        role="dialog"
        aria-modal="true"
      >
        <ModalCloseButton
          onClick={onClose}
          className="absolute right-4 top-4 z-10"
        />
        <div className="pr-12">
          <AffiliateApplyForm
          active={open}
          prefillFrom={prefillFrom}
          title={title}
          onSubmit={onSubmit}
          onCancel={onClose}
          showCancel
        />
        </div>
      </div>
    </div>
  )
}
