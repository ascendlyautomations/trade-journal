"use client"

import { useCallback, useLayoutEffect, useRef } from "react"
import {
  syncTextareaHeight,
  type SyncTextareaHeightOptions,
} from "./resizeTextarea"

export function useAutoResizeTextarea(
  value: string,
  options?: SyncTextareaHeightOptions
) {
  const ref = useRef<HTMLTextAreaElement>(null)
  const maxLines = options?.maxLines
  const minLines = options?.minLines

  const sync = useCallback(() => {
    if (ref.current) syncTextareaHeight(ref.current, { maxLines, minLines })
  }, [maxLines, minLines])

  useLayoutEffect(() => {
    sync()
  }, [value, sync])

  return ref
}
