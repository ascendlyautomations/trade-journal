const listeners = new Set<() => void>()
let currentTitle: string | null = null

export function getMobileWebTradeTitle(): string | null {
  return currentTitle
}

export function setMobileWebTradeTitle(title: string | null) {
  const next = title && title.trim() ? title.trim() : null
  if (next === currentTitle) return
  currentTitle = next
  listeners.forEach((listener) => listener())
}

export function subscribeMobileWebTradeTitle(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}
