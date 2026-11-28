"use client"

import dynamic from "next/dynamic"

const ProfileInsightsPageClient = dynamic(
  () => import("./ProfileInsightsPageClient"),
  { ssr: false }
)

/** Owner-only Profile Insights (lazy RPC load in client). */
export default function ProfileInsightsPage() {
  return <ProfileInsightsPageClient />
}