"use client"

import Modal from "@/app/components/ui/Modal"
import LockedFeature from "./LockedFeature"
import { TRADETRAXS_PRO_PLAN } from "@/lib/tradeTraxsPlans"

export const PRO_EXPORT_UPGRADE_DESCRIPTION = `Branded export cards are included with ${TRADETRAXS_PRO_PLAN.name}.`

export type ProUpgradeModalProps = {
  open: boolean
  onClose: () => void
  title?: string
  description?: string
}

export default function ProUpgradeModal({
  open,
  onClose,
  title = "Export Images",
  description = PRO_EXPORT_UPGRADE_DESCRIPTION,
}: ProUpgradeModalProps) {
  return (
    <Modal open={open} onClose={onClose} size="sm" panelClassName="p-0">
      <LockedFeature
        title={title}
        description={description}
        showBackLink={false}
        className="min-h-0 border-0 bg-transparent"
      />
    </Modal>
  )
}
