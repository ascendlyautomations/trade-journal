"use client"

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react"
import { scrollToAffiliateApplication } from "@/lib/affiliateApplicationNavigation"

type AffiliateProgramApplyContextValue = {
  expanded: boolean
  setExpanded: (expanded: boolean) => void
  scrollToApplication: () => void
  registerFocusFirstField: (focus: (() => void) | null) => void
}

const AffiliateProgramApplyContext =
  createContext<AffiliateProgramApplyContextValue | null>(null)

export function AffiliateProgramApplyProvider({ children }: { children: ReactNode }) {
  const [expanded, setExpanded] = useState(true)
  const focusFirstFieldRef = useRef<(() => void) | null>(null)

  const registerFocusFirstField = useCallback((focus: (() => void) | null) => {
    focusFirstFieldRef.current = focus
  }, [])

  const scrollToApplication = useCallback(() => {
    setExpanded(true)

    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        scrollToAffiliateApplication({
          onScrollComplete: () => {
            window.requestAnimationFrame(() => {
              focusFirstFieldRef.current?.()
            })
          },
        })
      })
    })
  }, [])

  const value = useMemo(
    () => ({
      expanded,
      setExpanded,
      scrollToApplication,
      registerFocusFirstField,
    }),
    [expanded, scrollToApplication, registerFocusFirstField]
  )

  return (
    <AffiliateProgramApplyContext.Provider value={value}>
      {children}
    </AffiliateProgramApplyContext.Provider>
  )
}

export function useAffiliateProgramApply(): AffiliateProgramApplyContextValue {
  const ctx = useContext(AffiliateProgramApplyContext)
  if (!ctx) {
    throw new Error("useAffiliateProgramApply must be used within AffiliateProgramApplyProvider")
  }
  return ctx
}
