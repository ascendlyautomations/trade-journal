"use client"

import { useEffect, useState } from "react"
import { useHydrationReady } from "@/lib/useHydrationReady"
import { useVault } from "@/lib/vault/VaultProvider"
import type { VaultContentRef } from "@/lib/vault/types"
import VaultDestinationModal from "./VaultDestinationModal"
import VaultHexagonIcon from "./VaultHexagonIcon"

type VaultEngagementButtonProps = {
  contentRef: VaultContentRef
  variant?: "boxed" | "inline"
  className?: string
}

export default function VaultEngagementButton({
  contentRef,
  variant = "inline",
  className = "",
}: VaultEngagementButtonProps) {
  const vault = useVault()
  const hydrationReady = useHydrationReady()
  const [sheetOpen, setSheetOpen] = useState(false)
  const snap = vault.stateFor(contentRef)
  const vaulted = snap.isVaulted

  useEffect(() => {
    vault.prefetch([contentRef])
  }, [contentRef, vault])

  const variantClass =
    variant === "boxed"
      ? "inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-white/5 text-gray-300 transition hover:bg-white/10 hover:text-white disabled:opacity-50"
      : "inline-flex shrink-0 items-center justify-center p-1 text-gray-400 hover:text-gray-200 disabled:opacity-50"

  return (
    <>
      <button
        type="button"
        disabled={!hydrationReady}
        aria-label={vaulted ? "Manage in Vault" : "Add to Vault"}
        className={`${variantClass} ${vaulted ? "text-blue-400 hover:text-blue-300" : ""} ${className}`.trim()}
        onClick={(e) => {
          e.stopPropagation()
          vault.loadFoldersIfNeeded()
          setSheetOpen(true)
        }}
      >
        <VaultHexagonIcon filled={vaulted} className="h-4 w-4" />
      </button>
      <VaultDestinationModal
        open={sheetOpen}
        onClose={() => setSheetOpen(false)}
        ref={contentRef}
      />
    </>
  )
}

/** Spacer + vault button aligned to the trailing edge (iOS EngagementBar layout). */
export function VaultEngagementTrailing({
  contentRef,
  variant = "inline",
}: {
  contentRef: VaultContentRef | null | undefined
  variant?: "boxed" | "inline"
}) {
  if (!contentRef) return null
  return (
    <>
      <span className="min-w-0 flex-1" aria-hidden />
      <VaultEngagementButton contentRef={contentRef} variant={variant} />
    </>
  )
}
