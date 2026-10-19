"use client"

import Link from "next/link"
import { useMemo } from "react"
import { buildTradeRoomsEntryHref } from "@/lib/tradeRoomsEntry"
import { useUserProfile } from "@/lib/UserProfileProvider"

const TRADE_ROOMS_ICON = (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.75"
    strokeLinecap="round"
    strokeLinejoin="round"
    className="h-4 w-4 shrink-0"
    aria-hidden
  >
    <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
    <circle cx="9" cy="7" r="4" />
    <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
    <path d="M16 3.13a4 4 0 0 1 0 7.75" />
  </svg>
)

type MessagesTradeRoomsLinkProps = {
  className?: string
}

export default function MessagesTradeRoomsLink({
  className = "",
}: MessagesTradeRoomsLinkProps) {
  const { user } = useUserProfile()
  const href = useMemo(() => buildTradeRoomsEntryHref(user?.id), [user?.id])

  return (
    <Link
      href={href}
      prefetch={false}
      className={
        className ||
        "inline-flex min-h-10 items-center gap-1.5 rounded-lg border border-blue-400/30 bg-blue-500/15 px-3 py-1.5 text-sm font-medium text-blue-200 transition hover:border-blue-400/45 hover:bg-blue-500/25 hover:text-blue-100 md:min-h-9"
      }
    >
      {TRADE_ROOMS_ICON}
      Trade Rooms
    </Link>
  )
}
