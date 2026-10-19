/** Dedicated web create surfaces (Add Trade remains `/app`). */
export const CREATE_ROUTE = {
  post: "/create/post",
  clip: "/create/clip",
  achievement: "/create/achievement",
  story: "/create/story",
  addTrade: "/app",
} as const

export function isCreateHubPath(pathname: string): boolean {
  return (
    pathname === CREATE_ROUTE.post ||
    pathname.startsWith(`${CREATE_ROUTE.post}/`) ||
    pathname === CREATE_ROUTE.clip ||
    pathname.startsWith(`${CREATE_ROUTE.clip}/`) ||
    pathname === CREATE_ROUTE.achievement ||
    pathname.startsWith(`${CREATE_ROUTE.achievement}/`) ||
    pathname === CREATE_ROUTE.story ||
    pathname.startsWith(`${CREATE_ROUTE.story}/`)
  )
}
