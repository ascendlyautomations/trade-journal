import type { HTMLAttributes } from "react"
import { UI_SKELETON_PULSE } from "@/lib/uiPrimitiveStyles"
import { cn } from "./cn"

export type SkeletonProps = HTMLAttributes<HTMLDivElement>

export default function Skeleton({ className, ...props }: SkeletonProps) {
  return (
    <div
      aria-hidden="true"
      className={cn(UI_SKELETON_PULSE, className)}
      {...props}
    />
  )
}
