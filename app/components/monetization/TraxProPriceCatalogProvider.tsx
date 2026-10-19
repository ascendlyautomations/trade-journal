"use client"

import { useEffect, type ReactNode } from "react"
import { loadTraxProPriceCatalog } from "@/lib/traxProPriceCatalogClient"

/** Loads the shared Stripe price catalog once for pricing, upgrade, and settings surfaces. */
export function TraxProPriceCatalogProvider({ children }: { children: ReactNode }) {
  useEffect(() => {
    void loadTraxProPriceCatalog()
  }, [])
  return children
}
