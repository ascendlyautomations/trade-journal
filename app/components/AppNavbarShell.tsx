"use client"

import { usePathname } from "next/navigation"
import Navbar from "./Navbar"
import { shouldRenderGlobalAppNavbar } from "@/lib/appNavbarShell"

/**
 * Single source of truth for the authenticated app navbar.
 * Marketing/legal/demo routes supply their own chrome.
 * Navbar portals to document.body so page stacking (e.g. trades filter bar
 * backdrop-blur) cannot cover the fixed header on mobile.
 */
export default function AppNavbarShell() {
  const pathname = usePathname()
  if (!shouldRenderGlobalAppNavbar(pathname)) return null
  return <Navbar />
}
