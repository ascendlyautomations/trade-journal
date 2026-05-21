import type { ReactNode } from "react"
import { cn } from "./cn"

export type EmptyStateProps = {
  title: string
  description?: string
  action?: ReactNode
  className?: string
}

export default function EmptyState({
  title,
  description,
  action,
  className,
}: EmptyStateProps) {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center rounded-xl border border-white/10 bg-white/5 px-6 py-10 text-center",
        className
      )}
    >
      <h3 className="text-base font-semibold text-white">{title}</h3>
      {description ? (
        <p className="mt-2 max-w-sm text-sm text-gray-400">{description}</p>
      ) : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  )
}
