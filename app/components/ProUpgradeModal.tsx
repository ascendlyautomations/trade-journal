"use client"

import Link from "next/link"
import Modal from "@/app/components/ui/Modal"
import { buttonVariants, cn } from "@/app/components/ui"
import { TRADETRAXS_PRO_PLAN } from "@/lib/tradeTraxsPlans"
import {
  PRO_EXPORT_UPGRADE_TITLE,
  PRO_UPGRADE_ANALYTICS_FEATURES,
  PRO_UPGRADE_ANALYTICS_HEADLINE,
  PRO_UPGRADE_ANALYTICS_SECTION_LABEL,
  PRO_UPGRADE_ANALYTICS_SUBHEADLINE,
  proExportUpgradeDescription,
} from "@/lib/proUpgradeContent"

export const PRO_EXPORT_UPGRADE_DESCRIPTION = proExportUpgradeDescription(
  TRADETRAXS_PRO_PLAN.name
)

export type ProUpgradeModalProps = {
  open: boolean
  onClose: () => void
  /** Full analytics feature list (default) or a single-purpose export prompt. */
  variant?: "analytics" | "custom"
  title?: string
  description?: string
}

export default function ProUpgradeModal({
  open,
  onClose,
  variant = "analytics",
  title = PRO_EXPORT_UPGRADE_TITLE,
  description = PRO_EXPORT_UPGRADE_DESCRIPTION,
}: ProUpgradeModalProps) {
  return (
    <Modal
      open={open}
      onClose={onClose}
      size={variant === "analytics" ? "md" : "sm"}
      panelClassName="border border-white/10 bg-[#0b1f3a] p-6 text-center text-gray-100"
    >
      {variant === "analytics" ? (
        <>
          <h2 className="text-xl font-semibold text-white">
            {PRO_UPGRADE_ANALYTICS_HEADLINE}
          </h2>
          <p className="mt-2 text-sm text-gray-400">
            {PRO_UPGRADE_ANALYTICS_SUBHEADLINE}
          </p>
          <p className="mt-5 text-xs font-medium uppercase tracking-wide text-gray-400">
            {PRO_UPGRADE_ANALYTICS_SECTION_LABEL}
          </p>
          <ul className="mx-auto mt-3 max-w-sm space-y-2 text-left text-sm text-gray-200">
            {PRO_UPGRADE_ANALYTICS_FEATURES.map((feature) => (
              <li key={feature} className="flex items-start gap-2">
                <span className="shrink-0 text-emerald-400" aria-hidden>
                  ✓
                </span>
                <span>{feature}</span>
              </li>
            ))}
          </ul>
          <Link
            href="/pricing"
            onClick={onClose}
            className={cn(
              buttonVariants({ variant: "primary", size: "md" }),
              "mt-6 inline-flex w-full justify-center sm:w-auto"
            )}
          >
            Upgrade to Pro
          </Link>
        </>
      ) : (
        <>
          {title ? (
            <p className="mb-1 text-xs font-medium uppercase tracking-wide text-gray-400">
              {title}
            </p>
          ) : null}
          <h3 className="mb-2 text-lg font-semibold text-white">
            Upgrade to {TRADETRAXS_PRO_PLAN.name}
          </h3>
          <p className="mb-4 max-w-sm text-sm text-gray-400">{description}</p>
          <Link
            href="/pricing"
            onClick={onClose}
            className={buttonVariants({ variant: "primary", size: "md" })}
          >
            Upgrade to {TRADETRAXS_PRO_PLAN.name}
          </Link>
        </>
      )}
    </Modal>
  )
}
