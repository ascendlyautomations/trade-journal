"use client"

import dynamic from "next/dynamic"

/**
 * Web app top navbar — currently the existing Navbar.
 * Future web-only chrome changes belong here.
 */
const Navbar = dynamic(() => import("@/app/components/Navbar"), {
  ssr: false,
  loading: () => null,
})

export default function WebNavbar() {
  return <Navbar />
}
