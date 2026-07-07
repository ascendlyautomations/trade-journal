import Link from "next/link"
import { buttonVariants, Card, cn } from "@/app/components/ui"
import { TRADETRAXS_PRO_PLAN } from "@/lib/tradeTraxsPlans"

type LockedFeatureProps = {
  title?: string
  description?: string
  /** When false, hides the secondary “Back to Dashboard” link (e.g. inside a modal). */
  showBackLink?: boolean
  className?: string
  /** Compact teaser — opens parent upgrade modal instead of inline upgrade UI. */
  onUpgradeClick?: () => void
}

export default function LockedFeature({
  title,
  description,
  showBackLink = true,
  className = "",
  onUpgradeClick,
}: LockedFeatureProps) {
  if (onUpgradeClick) {
    return (
      <button
        type="button"
        onClick={onUpgradeClick}
        className={cn(
          "flex h-full w-full min-h-[120px] flex-col items-center justify-center rounded-xl border border-white/10 bg-[#0b1f3a]/80 p-4 text-center transition hover:border-emerald-500/30 hover:bg-[#0b1f3a]",
          className
        )}
      >
        {title ? (
          <p className="mb-1 text-xs font-medium uppercase tracking-wide text-gray-500">
            {title}
          </p>
        ) : null}
        <p className="text-sm font-medium text-white/90">🔒 Pro feature</p>
        <p className="mt-1 text-xs text-emerald-300/90">Tap to unlock</p>
      </button>
    )
  }

  return (
    <Card
      variant="solid"
      padding="lg"
      className={cn(
        "flex min-h-[220px] h-full w-full flex-col items-center justify-center bg-[#0b1f3a] text-center",
        className
      )}
    >
      {title ? (
        <p className="mb-1 text-xs font-medium uppercase tracking-wide text-gray-500">
          {title}
        </p>
      ) : null}
      <h3 className="mb-2 text-lg font-semibold text-white">
        Upgrade to {TRADETRAXS_PRO_PLAN.name}
      </h3>
      <p className="mb-4 max-w-sm text-sm text-gray-400">
        {description ??
          `This feature is available with ${TRADETRAXS_PRO_PLAN.name}.`}
      </p>
      <div className="flex flex-col items-center gap-2 sm:flex-row sm:justify-center">
        <Link
          href="/pricing"
          className={buttonVariants({ variant: "primary", size: "md" })}
        >
          Upgrade to {TRADETRAXS_PRO_PLAN.name}
        </Link>
        {showBackLink ? (
          <Link
            href="/dashboard"
            className={buttonVariants({ variant: "secondary", size: "md" })}
          >
            Back to Dashboard
          </Link>
        ) : null}
      </div>
    </Card>
  )
}
