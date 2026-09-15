"use client"

import type { ReactNode } from "react"
import ScrollableModalShell, {
  type ScrollableModalShellProps,
} from "@/app/components/ui/ScrollableModalShell"
import InlineMicroSpinner from "@/app/components/ui/InlineMicroSpinner"
import { cn } from "@/app/components/ui/cn"

const OVERLAY = "z-[105] bg-black/60 backdrop-blur-sm"
const ENRICHMENT_OVERLAY = "z-[110] bg-black/60 backdrop-blur-sm"

const PANEL_BASE =
  "w-full min-w-[min(100%,18rem)] rounded-2xl border border-white/10 bg-[#152238] shadow-xl"

const HEADER_CLASS = "shrink-0 border-b-0 px-5 pb-0 pt-5 pr-12"
const BODY_CLASS =
  "min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-5 pt-4 min-h-[4.5rem]"
const FOOTER_CLASS = "shrink-0 border-t border-white/10 px-5 py-4"

export const brokerImportTitleClass = {
  default: "text-lg font-semibold leading-snug text-white",
  success: "text-lg font-semibold leading-snug text-emerald-300",
  error: "text-lg font-semibold leading-snug text-red-300",
} as const

export const brokerImportDescriptionClass = "text-sm leading-relaxed text-gray-300"

export const brokerImportFooterActionsClass =
  "flex flex-col-reverse gap-2 sm:flex-row sm:items-center sm:justify-end sm:gap-3"

export const brokerImportPrimaryButtonClass =
  "min-h-[2.5rem] rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-50"

export const brokerImportSecondaryButtonClass =
  "min-h-[2.5rem] rounded-xl border border-white/15 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/5 disabled:cursor-not-allowed disabled:opacity-50"

export const brokerImportGhostButtonClass =
  "min-h-[2.5rem] rounded-xl px-3 py-2 text-sm font-medium text-gray-300 transition hover:text-white disabled:opacity-50"

type BrokerImportModalShellProps = {
  open: boolean
  onClose: ScrollableModalShellProps["onClose"]
  ariaLabel: string
  title: ReactNode
  titleTone?: keyof typeof brokerImportTitleClass
  /** Rendered at top of body with spacing below the header. */
  description?: ReactNode
  footer?: ReactNode
  children?: ReactNode
  showCloseButton?: boolean
  closeDisabled?: boolean
  /** Import gate vs post-import enrichment stacking. */
  variant?: "import" | "enrichment"
  size?: "md" | "lg"
  bodyClassName?: string
  onOverlayClick?: ScrollableModalShellProps["onOverlayClick"]
}

export default function BrokerImportModalShell({
  open,
  onClose,
  ariaLabel,
  title,
  titleTone = "default",
  description,
  footer,
  children,
  showCloseButton = true,
  closeDisabled = false,
  variant = "import",
  size = "md",
  bodyClassName,
  onOverlayClick,
}: BrokerImportModalShellProps) {
  const panelClassName = cn(
    PANEL_BASE,
    size === "lg" ? "max-w-lg" : "max-w-md"
  )

  return (
    <ScrollableModalShell
      open={open}
      onClose={onClose}
      ariaLabel={ariaLabel}
      showCloseButton={showCloseButton}
      closeDisabled={closeDisabled}
      closeButtonClassName="absolute right-3 top-3 z-10 sm:right-4 sm:top-4"
      overlayClassName={variant === "enrichment" ? ENRICHMENT_OVERLAY : OVERLAY}
      panelClassName={panelClassName}
      headerClassName={HEADER_CLASS}
      bodyClassName={cn(BODY_CLASS, bodyClassName)}
      footerClassName={footer ? FOOTER_CLASS : undefined}
      onOverlayClick={onOverlayClick}
      header={
        <h2 className={cn(brokerImportTitleClass[titleTone], "pr-1")}>{title}</h2>
      }
      footer={footer}
    >
      {description ? (
        <div className={cn(brokerImportDescriptionClass, children ? "mb-4" : "")}>
          {description}
        </div>
      ) : null}
      {children}
    </ScrollableModalShell>
  )
}

export function BrokerImportLoadingBody({
  message = "Looking for new trades.",
}: {
  message?: string
}) {
  return (
    <div className="flex items-start gap-3 pt-1">
      <InlineMicroSpinner className="mt-0.5 h-4 w-4 text-blue-400" label="Loading" />
      <p className={brokerImportDescriptionClass}>{message}</p>
    </div>
  )
}
