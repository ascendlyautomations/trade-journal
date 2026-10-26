import type { MouseEvent } from "react"

/** Double-tap / double-click toggles the heart reaction on message bubbles. */
export function handleMessageReactionDoubleClick(
  event: MouseEvent,
  canReact: boolean,
  onToggleHeart: () => void
) {
  if (!canReact) return
  const target = event.target as HTMLElement
  if (target.closest("button, a, [role='button'], input, textarea")) return
  event.preventDefault()
  onToggleHeart()
}
