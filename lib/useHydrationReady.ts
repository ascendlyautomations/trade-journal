import { useSyncExternalStore } from "react"

/**
 * False during SSR and the hydration pass; true after the client has hydrated.
 * Use when auth/browser state must not differ between server HTML and first client render.
 */
export function useHydrationReady(): boolean {
  return useSyncExternalStore(
    () => () => {},
    () => true,
    () => false
  )
}
