import { CREATE_ROUTE } from "./createRoutes.ts"
import { isAppAddTradePath } from "./addTradePath.ts"

export type MobileWebCreateChrome = {
  title: string
  backHref: string
}

const CREATE_PATH_CHROME: Record<string, MobileWebCreateChrome> = {
  [CREATE_ROUTE.post]: { title: "New Post", backHref: "/feed" },
  [CREATE_ROUTE.story]: { title: "Story", backHref: "/feed" },
  [CREATE_ROUTE.clip]: { title: "New Clip", backHref: "/feed" },
  [CREATE_ROUTE.achievement]: {
    title: "Achievement",
    backHref: "/achievements",
  },
  [CREATE_ROUTE.withdrawal]: { title: "Withdrawal", backHref: "/dashboard" },
}

/** Phone navbar title + back for full-page create surfaces (≤767px). */
export function resolveMobileWebCreateChrome(
  pathname: string
): MobileWebCreateChrome | null {
  const normalized =
    pathname.length > 1 && pathname.endsWith("/")
      ? pathname.slice(0, -1)
      : pathname
  const direct = CREATE_PATH_CHROME[normalized]
  if (direct) return direct
  if (isAppAddTradePath(normalized)) {
    return { title: "Add Trade", backHref: "/dashboard" }
  }
  return null
}
