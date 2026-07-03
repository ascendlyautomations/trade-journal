const AFFILIATE_APPLICATION_ANCHOR = "affiliate-application"

export function getAffiliateApplicationElement(): HTMLElement | null {
  return document.getElementById(AFFILIATE_APPLICATION_ANCHOR)
}

export function isAffiliateApplicationInView(element: HTMLElement, threshold = 0.35): boolean {
  const rect = element.getBoundingClientRect()
  const viewportHeight = window.innerHeight || document.documentElement.clientHeight
  const visibleHeight = Math.min(rect.bottom, viewportHeight) - Math.max(rect.top, 0)
  if (visibleHeight <= 0) return false
  return visibleHeight / rect.height >= threshold
}

export function scrollToAffiliateApplication(options?: {
  onScrollComplete?: () => void
}): void {
  const element = getAffiliateApplicationElement()
  if (!element) return

  const alreadyVisible = isAffiliateApplicationInView(element)

  const complete = () => {
    options?.onScrollComplete?.()
  }

  if (alreadyVisible) {
    complete()
    return
  }

  let completed = false
  const finish = () => {
    if (completed) return
    completed = true
    complete()
  }

  element.addEventListener("scrollend", finish, { once: true })
  window.setTimeout(finish, 700)

  element.scrollIntoView({ behavior: "smooth", block: "start" })
}
