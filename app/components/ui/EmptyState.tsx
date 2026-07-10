import type { ReactNode } from "react"
import { cn } from "./cn"

export type EmptyStateProps = {
  title: string
  description?: string
  icon?: ReactNode
  action?: ReactNode
  className?: string
}

export default function EmptyState({
  title,
  description,
  icon,
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
      {icon ? (
        <div
          className="mb-3 flex h-10 w-10 items-center justify-center rounded-full border border-white/10 bg-white/[0.06] text-lg"
          aria-hidden
        >
          {icon}
        </div>
      ) : null}
      <h3 className="text-base font-semibold text-white">{title}</h3>
      {description ? (
        <p className="mt-2 max-w-sm text-sm text-gray-400">{description}</p>
      ) : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  )
}
