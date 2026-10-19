"use client"

import { useCallback, useRef, useState } from "react"

/** Primary action registration from create composers to `CreatePageLayout`. */
export type CreatePagePrimaryRegistration = {
  publish?: () => void
  save?: () => void
  post?: () => void
  canPublish?: boolean
  canPost?: boolean
  busy: boolean
}

function resolveAction(update: CreatePagePrimaryRegistration): () => void {
  return update.publish ?? update.save ?? update.post ?? (() => {})
}

function resolveCanAct(update: CreatePagePrimaryRegistration): boolean {
  if (update.canPublish !== undefined) return update.canPublish
  if (update.canPost !== undefined) return update.canPost
  return true
}

/**
 * Stable bridge for page-level Publish/Save buttons.
 * Stores the latest action in a ref; re-renders the page only when busy/disabled flags change.
 */
export function useCreatePagePrimaryAction() {
  const actionRef = useRef<() => void>(() => {})
  const [flags, setFlags] = useState({ primaryDisabled: true, primaryBusy: false })

  const registerPrimary = useCallback((update: CreatePagePrimaryRegistration) => {
    actionRef.current = resolveAction(update)
    const primaryDisabled = !resolveCanAct(update)
    const primaryBusy = update.busy
    setFlags((prev) =>
      prev.primaryDisabled === primaryDisabled && prev.primaryBusy === primaryBusy
        ? prev
        : { primaryDisabled, primaryBusy }
    )
  }, [])

  const invokePrimary = useCallback(() => {
    actionRef.current()
  }, [])

  return {
    registerPrimary,
    invokePrimary,
    primaryDisabled: flags.primaryDisabled,
    primaryBusy: flags.primaryBusy,
  }
}
