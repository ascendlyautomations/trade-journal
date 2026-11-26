"use client"

import { useCallback, useEffect, useRef } from "react"
import type { SupabaseClient } from "@supabase/supabase-js"
import { feedContentKey } from "@/lib/feedRotatingSession"
import { queueFeedImpression, flushFeedImpressionQueue } from "@/lib/feedImpressionRecorder"
import { isBackendV2Enabled } from "@/lib/backendV2/flags"

type TrackableItem = { id: string; feedKind?: string }

type Options = {
  active: boolean
  supabase: SupabaseClient | null
}

export function useFeedImpressionTracker(options: Options) {
  const timersRef = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map())
  const firedRef = useRef<Set<string>>(new Set())
  const observersRef = useRef<Map<string, IntersectionObserver>>(new Map())
  const activeRef = useRef(options.active)
  activeRef.current = options.active

  const clearEntry = useCallback((key: string) => {
    const t = timersRef.current.get(key)
    if (t) clearTimeout(t)
    timersRef.current.delete(key)
    const obs = observersRef.current.get(key)
    if (obs) obs.disconnect()
    observersRef.current.delete(key)
  }, [])

  const observeCard = useCallback(
    (el: HTMLElement | null, item: TrackableItem) => {
      if (
        !el ||
        !isBackendV2Enabled("feedRotatingRank") ||
        !item?.id ||
        !item.feedKind
      ) {
        return () => {}
      }
      const key = feedContentKey(item.feedKind, item.id)
      if (firedRef.current.has(key)) return () => {}

      if (typeof IntersectionObserver === "undefined") return () => {}

      const existing = observersRef.current.get(key)
      if (existing) existing.disconnect()

      const observer = new IntersectionObserver(
        (entries) => {
          const entry = entries[0]
          if (!entry) return
          const visible = entry.isIntersecting && entry.intersectionRatio >= 0.5
          if (!visible || !activeRef.current) {
            const t = timersRef.current.get(key)
            if (t) clearTimeout(t)
            timersRef.current.delete(key)
            return
          }
          if (timersRef.current.has(key) || firedRef.current.has(key)) return
          const timer = setTimeout(() => {
            timersRef.current.delete(key)
            if (!activeRef.current || firedRef.current.has(key)) return
            firedRef.current.add(key)
            const kind =
              item.feedKind === "trade"
                ? "post"
                : item.feedKind === "profile"
                  ? "profile_post"
                  : item.feedKind === "achievement"
                    ? "achievement_post"
                    : "reel"
            queueFeedImpression({ content_kind: kind, content_id: String(item.id) })
            observer.disconnect()
            observersRef.current.delete(key)
          }, 2000)
          timersRef.current.set(key, timer)
        },
        { threshold: [0, 0.5, 1] }
      )
      observer.observe(el)
      observersRef.current.set(key, observer)

      return () => clearEntry(key)
    },
    [clearEntry]
  )

  useEffect(() => {
    const client = options.supabase
    if (!options.active || !client) return
    const onVis = () => {
      if (document.visibilityState === "hidden") {
        void flushFeedImpressionQueue(client)
      }
    }
    document.addEventListener("visibilitychange", onVis)
    return () => {
      document.removeEventListener("visibilitychange", onVis)
      for (const key of [...timersRef.current.keys()]) clearEntry(key)
      void flushFeedImpressionQueue(client)
    }
  }, [options.active, options.supabase, clearEntry])

  return { observeCard }
}