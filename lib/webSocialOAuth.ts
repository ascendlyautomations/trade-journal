import type { SupabaseClient } from "@supabase/supabase-js"
import { startNativeIosGoogleOAuth } from "@/lib/nativeIosOAuth"
import { isNativeIos } from "@/lib/nativePlatform"

export {
  isApplePrivateRelayEmail,
  mapWebSocialOAuthError,
  resolveWebSocialOAuthRedirectPath,
  validateWebSocialOAuthSignup,
  type WebSocialOAuthProvider,
  type WebSocialOAuthRedirectContext,
  type WebSocialOAuthSignupContext,
} from "@/lib/webSocialOAuthPolicy"

import {
  mapWebSocialOAuthError,
  type WebSocialOAuthProvider,
} from "@/lib/webSocialOAuthPolicy"

export type StartWebSocialOAuthOptions = {
  supabase: SupabaseClient
  provider: WebSocialOAuthProvider
  redirectPath: string
  /** When true, use native iOS Google bridge (Apple uses native app — web only). */
  allowNativeIosGoogleBridge?: boolean
}

/**
 * Starts provider OAuth. Web navigates away on success; native iOS Google uses
 * the existing ASWebAuthenticationSession bridge. Apple web OAuth is browser-only.
 */
export async function startWebSocialOAuth(
  options: StartWebSocialOAuthOptions
): Promise<{ ok: true } | { ok: false; message: string }> {
  const { supabase, provider, redirectPath, allowNativeIosGoogleBridge = true } =
    options

  if (
    provider === "google" &&
    allowNativeIosGoogleBridge &&
    isNativeIos()
  ) {
    try {
      await startNativeIosGoogleOAuth(redirectPath)
      return { ok: true }
    } catch (err) {
      return {
        ok: false,
        message: mapWebSocialOAuthError(err),
      }
    }
  }

  const redirectTo =
    typeof location !== "undefined"
      ? `${location.origin}${redirectPath}`
      : redirectPath

  const oauthOptions: {
    redirectTo: string
    scopes?: string
    queryParams?: Record<string, string>
  } = { redirectTo }

  if (provider === "apple") {
    oauthOptions.scopes = "name email"
  }

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider,
    options: oauthOptions,
  })

  if (error) {
    return { ok: false, message: mapWebSocialOAuthError(error) }
  }

  if (data?.url && typeof window !== "undefined") {
    window.location.assign(data.url)
  }

  return { ok: true }
}

/** Reads OAuth error params left in the URL after a failed provider redirect. */
export function readWebSocialOAuthCallbackError(): string | null {
  if (typeof window === "undefined") return null

  const readParams = (raw: string) => {
    const trimmed = raw.replace(/^#/, "").replace(/^\?/, "")
    if (!trimmed) return null
    return new URLSearchParams(trimmed)
  }

  const hashParams = readParams(window.location.hash)
  const searchParams = readParams(window.location.search)

  const errorCode =
    hashParams?.get("error") ??
    searchParams?.get("error") ??
    hashParams?.get("error_code") ??
    searchParams?.get("error_code")

  const description =
    hashParams?.get("error_description") ??
    searchParams?.get("error_description")

  if (!errorCode && !description) return null

  return mapWebSocialOAuthError({
    message: description ?? errorCode ?? "OAuth sign-in failed",
    name: errorCode ?? "OAuthError",
  })
}

/** Clears OAuth error/hash fragments from the URL without a navigation. */
export function clearWebSocialOAuthCallbackParams() {
  if (typeof window === "undefined") return
  const url = new URL(window.location.href)
  url.hash = ""
  if (url.searchParams.has("error") || url.searchParams.has("error_description")) {
    url.searchParams.delete("error")
    url.searchParams.delete("error_description")
    url.searchParams.delete("error_code")
  }
  window.history.replaceState({}, "", url.pathname + url.search)
}
