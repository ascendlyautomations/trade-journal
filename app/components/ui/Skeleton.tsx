import type { HTMLAttributes } from "react"
import { cn } from "./cn"

export type SkeletonProps = HTMLAttributes<HTMLDivElement>

export default function Skeleton({ className, ...props }: SkeletonProps) {
  return (
    <div
      aria-hidden="true"
      className={cn("animate-pulse rounded-md bg-white/10", className)}
      {...props}
    />
  )
}
