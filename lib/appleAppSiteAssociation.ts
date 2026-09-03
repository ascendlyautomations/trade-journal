import { NATIVE_IOS_APP_ID } from "@/lib/nativeIosIdentity"

/** Apple Developer Team ID (Xcode DEVELOPMENT_TEAM). */
export const APPLE_TEAM_ID = "486KAM395Y" as const

/**
 * Universal Link paths claimed for the native iOS app.
 *
 * Keep in sync with `DeepLinkParser` (`native-ios/.../DeepLinkParsing.swift`).
 * Paths intentionally omitted (pricing, admin, demo, marketing, legal, etc.)
 * continue to open in Safari when the app is not installed — and are not
 * hijacked into native when it is.
 */
export const APPLE_APP_SITE_ASSOCIATION_PATHS = [
  "/",
  "/dashboard",
  "/dashboard/*",
  "/trades",
  "/trade",
  "/trade/*",
  "/calendar",
  "/analyst",
  "/ai",
  "/feed",
  "/feed/*",
  "/explore",
  "/leaderboard",
  "/post/*",
  "/reel/*",
  "/story/*",
  "/profile",
  "/profile/*",
  "/messages",
  "/messages/*",
  "/notifications",
  "/community",
  "/community/*",
  "/trade-rooms",
  "/trade-rooms/*",
  "/room/*",
  "/settings",
  "/settings/*",
  "/affiliate",
  "/affiliate/*",
  "/referrals",
  "/import",
  "/app",
  "/input",
  "/input-trade",
  "/login",
  "/auth/*",
  "/reset-password",
  "/forgot-password",
  "/choose-plan",
  "/onboarding",
] as const

export const APPLE_APP_SITE_ASSOCIATION = {
  applinks: {
    apps: [] as string[],
    details: [
      {
        appID: `${APPLE_TEAM_ID}.${NATIVE_IOS_APP_ID}`,
        paths: [...APPLE_APP_SITE_ASSOCIATION_PATHS],
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
