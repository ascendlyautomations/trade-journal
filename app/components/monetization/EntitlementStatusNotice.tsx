"use client"

import { buttonVariants, cn } from "@/app/components/ui"

type Props = {
  status: "idle" | "loading" | "ready" | "error"
  onRetry?: () => void
  className?: string
}

export default function EntitlementStatusNotice({
  status,
  onRetry,
  className,
}: Props) {
  const failed = status === "error"
  return (
    <div
      className={cn(
        "rounded-xl border border-white/10 bg-white/5 px-4 py-4 text-sm text-gray-200",
        className
      )}
      role={failed ? "alert" : "status"}
    >
      <p className="font-medium text-white">
        {failed ? "Could not verify your plan" : "Checking your plan"}
      </p>
      <p className="mt-1 text-gray-300">
        {failed
          ? "TradeTraxs could not confirm Pro access. Nothing was charged. Try again."
          : "Confirming your subscription before showing plan options."}
      </p>
      {failed && onRetry ? (
        <button
          type="button"
          className={cn(buttonVariants({ variant: "secondary", size: "sm" }), "mt-3")}
          onClick={onRetry}
        >
          Try again
        </button>
      ) : null}
    </div>
  )
}
