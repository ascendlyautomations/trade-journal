/** Public-only means the public subset, including when that subset is empty. */
export function applyPublicVisibilityFilter<T>(
  trades: readonly T[],
  showPublicOnly: boolean,
  isPublic: (trade: T) => boolean
): T[] {
  if (!showPublicOnly) return [...trades]
  return trades.filter(isPublic)
}
