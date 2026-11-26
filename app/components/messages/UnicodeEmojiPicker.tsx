"use client"

import { useEffect, useRef } from "react"

type EmojiClickEvent = CustomEvent<{ unicode: string }>

type Props = {
  className?: string
  onPick: (emoji: string) => void
  theme?: "light" | "dark"
}

export default function UnicodeEmojiPicker({
  className = "",
  onPick,
  theme = "dark",
}: Props) {
  const hostRef = useRef<HTMLDivElement | null>(null)
  const onPickRef = useRef(onPick)

  useEffect(() => {
    onPickRef.current = onPick
  }, [onPick])

  useEffect(() => {
    const host = hostRef.current
    if (!host) return

    let picker: (HTMLElement & { classList: DOMTokenList }) | null = null
    let onEmoji: ((event: Event) => void) | null = null
    let cancelled = false

    void import("emoji-picker-element").then(() => {
      if (cancelled || !host) return

      picker = document.createElement("emoji-picker") as HTMLElement & {
        classList: DOMTokenList
      }
      if (theme === "dark") {
        picker.classList.add("dark")
      }
      picker.setAttribute(
        "style",
        "width: 100%; height: min(420px, 55vh); --background: transparent; --border-color: transparent;"
      )

      onEmoji = (event: Event) => {
        const detail = (event as EmojiClickEvent).detail
        const unicode = detail?.unicode?.trim()
        if (unicode) onPickRef.current(unicode)
      }

      picker.addEventListener("emoji-click", onEmoji)
      host.replaceChildren(picker)
    })

    return () => {
      cancelled = true
      if (picker && onEmoji) {
        picker.removeEventListener("emoji-click", onEmoji)
      }
      host.replaceChildren()
    }
  }, [theme])

  return (
    <div
      ref={hostRef}
      className={`unicode-emoji-picker-host overflow-hidden rounded-xl border border-white/10 bg-card/95 shadow-xl backdrop-blur-md ${className}`.trim()}
      role="region"
      aria-label="Emoji picker"
    />
  )
}