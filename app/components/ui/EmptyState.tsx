import type { ReactNode } from "react"
import {
  UI_EMPTY_STATE_ICON,
  UI_EMPTY_STATE_SHELL,
} from "@/lib/uiPrimitiveStyles"
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
    <div className={cn(UI_EMPTY_STATE_SHELL, "ui-theme-backdrop", className)}>
      {icon ? (
        <div className={UI_EMPTY_STATE_ICON} aria-hidden>
          {icon}
        </div>
      ) : null}
      <h3 className="text-base font-semibold text-foreground">{title}</h3>
      {description ? (
        <p className="mt-2 max-w-sm text-sm text-muted-foreground">
          {description}
        </p>
      ) : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  )
}
