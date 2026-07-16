import type { HTMLAttributes, ReactNode } from "react"
import { READABLE_CARD_TEXT_CLASS } from "@/lib/readableTextStyles"
import { cn } from "./cn"

export type CardVariant = "glass" | "solid" | "panel"

const variantClasses: Record<CardVariant, string> = {
  glass: `rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 ${READABLE_CARD_TEXT_CLASS}`,
  solid: `rounded-xl border border-white/10 bg-[#0f172a] ${READABLE_CARD_TEXT_CLASS}`,
  panel: `rounded-2xl border border-white/10 bg-white/10 shadow-2xl backdrop-blur-xl ${READABLE_CARD_TEXT_CLASS}`,
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
        interactive &&
          "cursor-pointer transition hover:bg-white/10 hover:border-white/15",
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
}
