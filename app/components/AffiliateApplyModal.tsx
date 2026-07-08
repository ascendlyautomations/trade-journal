"use client"

import AffiliateApplyForm from "@/app/components/AffiliateApplyForm"
import ScrollableModalShell from "@/app/components/ui/ScrollableModalShell"
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
  return (
    <ScrollableModalShell
      open={open}
      onClose={onClose}
      ariaLabel={title}
      overlayClassName="z-[100] bg-black/60 backdrop-blur-sm"
      backdropClassName="bg-transparent"
      panelClassName="max-w-lg rounded-2xl border-white/10 bg-[#152238]"
      headerClassName="border-white/10 px-6 py-4"
      bodyClassName="px-6 pb-6"
      header={<span className="sr-only">{title}</span>}
    >
      <AffiliateApplyForm
        active={open}
        prefillFrom={prefillFrom}
        title={title}
        onSubmit={onSubmit}
        onCancel={onClose}
        showCancel
      />
    </ScrollableModalShell>
  )
}
