"use client"

import { useLayoutEffect, useRef } from "react"
import type { CreatePagePrimaryRegistration } from "./useCreatePagePrimaryAction"

type RegisterCreatePagePrimaryOptions = {
  enabled: boolean
  registerPrimary?: (update: CreatePagePrimaryRegistration) => void
  action: () => void
  canAct: boolean
  busy: boolean
}

/**
 * Registers the latest primary action without unstable callback deps.
 * Parent re-renders only when `canAct` or `busy` change.
 */
export function useRegisterCreatePagePrimary({
  enabled,
  registerPrimary,
  action,
  canAct,
  busy,
}: RegisterCreatePagePrimaryOptions) {
  const actionRef = useRef(action)
  actionRef.current = action

  useLayoutEffect(() => {
    if (!enabled || !registerPrimary) return

    registerPrimary({
      publish: () => actionRef.current(),
      canPublish: canAct,
      busy,
    })

    return () => {
      registerPrimary({
        publish: () => {},
        canPublish: false,
        busy: false,
      })
    }
  }, [enabled, registerPrimary, canAct, busy])
}
