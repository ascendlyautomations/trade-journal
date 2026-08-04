"use client"

/**
 * Root app chrome. Implementation lives in the platform presentation layer so
 * native iOS and web can diverge later without duplicating pages or business logic.
 *
 * Behavior is intentionally identical to the previous inline AppChrome.
 */
export { default } from "./platform/PlatformChrome"
