import type { HTMLAttributes, ReactNode } from "react"
import {
  UI_CARD_GLASS,
  UI_CARD_INTERACTIVE,
  UI_CARD_PANEL,
  UI_CARD_SOLID,
} from "@/lib/uiPrimitiveStyles"
import { cn } from "./cn"

export type CardVariant = "glass" | "solid" | "panel"

const variantClasses: Record<CardVariant, string> = {
  glass: `${UI_CARD_GLASS} ui-theme-backdrop`,
  solid: UI_CARD_SOLID,
  panel: `${UI_CARD_PANEL} ui-theme-backdrop`,
}

export type CardProps = HTMLAttributes<HTMLDivElement> & {
  variant?: CardVariant
  padding?: "none" | "sm" | "md" | "lg"
  interactive?: boolean
  children: ReactNode
}

const paddingClasses = {
  none: "",
  sm: "p-3",
  md: "p-4 md:p-5",
  lg: "p-6 md:p-8",
}

export default function Card({
  variant = "glass",
  padding = "md",
  interactive = false,
  className,
  children,
  ...props
}: CardProps) {
  return (
    <div
      className={cn(
        variantClasses[variant],
        paddingClasses[padding],
        interactive && UI_CARD_INTERACTIVE,
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
}
