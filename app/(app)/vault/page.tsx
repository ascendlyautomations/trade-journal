"use client"

import VaultHome from "@/app/components/vault/VaultHome"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"

export default function VaultPage() {
  useScrollPageTopOnMount()

  return (
    <main className="mx-auto max-w-2xl px-4 py-8 md:py-10">
      <h1 className="mb-6 text-2xl font-semibold text-blue-200">Vault</h1>
      <VaultHome />
    </main>
  )
}
