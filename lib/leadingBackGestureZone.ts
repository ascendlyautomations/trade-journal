/** Match native ``NavigationInteractivePopEdgeSupport.leadingBackZoneWidthRatio``. */
export const LEADING_BACK_ZONE_WIDTH_RATIO = 0.1

export function leadingBackZoneMaxX(viewportWidth: number): number {
  return viewportWidth * LEADING_BACK_ZONE_WIDTH_RATIO
}

export function isLeadingBackGestureZone(
  clientX: number,
  viewportWidth?: number
): boolean {
  const width =
    viewportWidth ??
    (typeof window !== "undefined" ? window.innerWidth : 0)
  if (width <= 0) return false
  return clientX <= leadingBackZoneMaxX(width)
}
