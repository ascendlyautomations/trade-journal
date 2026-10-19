"use client"

import Link from "next/link"

type PsychologyCoachEntryLinkProps = {
  href?: string
  className?: string
}

/** Primary coach entry — always shown on analytics detail (iOS coach route). */
export default function PsychologyCoachEntryLink({
  href = "/psychology/coach",
  className,
}: PsychologyCoachEntryLinkProps) {
  return (
    <Link
      href={href}
      className={
        className ??
        "flex w-full items-center justify-center rounded-lg bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-600"
      }
      data-testid="psychologyCoach.open"
    >
      Open Psychology Coach
    </Link>
  )
}
