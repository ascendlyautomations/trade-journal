import { NATIVE_IOS_APP_ID } from "@/lib/nativeIosIdentity"

/** Apple Developer Team ID (Xcode DEVELOPMENT_TEAM). */
export const APPLE_TEAM_ID = "486KAM395Y" as const

export const APPLE_APP_SITE_ASSOCIATION = {
  applinks: {
    apps: [] as string[],
    details: [
      {
        appID: `${APPLE_TEAM_ID}.${NATIVE_IOS_APP_ID}`,
        paths: [
          "/",
          "/dashboard",
          "/dashboard/*",
          "/explore",
          "/explore/*",
          "/feed",
          "/feed/*",
          "/leaderboard",
          "/leaderboard/*",
          "/messages",
          "/messages/*",
          "/notifications",
          "/notifications/*",
          "/community",
          "/community/*",
          "/trade-rooms",
          "/trade-rooms/*",
          "/profile/*",
          "/trade/*",
          "/post/*",
          "/reel/*",
          "/story/*",
          "/room/*",
          "/analyst",
          "/analyst/*",
          "/onboarding",
          "/onboarding/*",
        ],
      },
    ],
  },
} as const

export function appleAppSiteAssociationResponse(): Response {
  return new Response(JSON.stringify(APPLE_APP_SITE_ASSOCIATION), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
    },
  })
}
