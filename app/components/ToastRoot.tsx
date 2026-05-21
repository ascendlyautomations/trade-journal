"use client"

import type { ReactNode } from "react"
import { ToastProvider } from "@/app/components/ui/ToastProvider"

/** Client boundary for global toasts — wrap once in root layout. */
export default function ToastRoot({ children }: { children: ReactNode }) {
  return <ToastProvider>{children}</ToastProvider>
}
