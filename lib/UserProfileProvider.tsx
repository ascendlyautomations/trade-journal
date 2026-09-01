"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
} from "react"
import type { AuthChangeEvent, Session } from "@supabase/supabase-js"
import {
  applyBetaReferralIfEligible,
  clearBetaReferralAfterApply,
} from "./applyBetaReferralIfEligible"
import { isBetaReferralRef } from "./betaReferralCode"
import {
  ensureProfileForUser,
  readStoredReferralCode,
} from "./ensureProfileForUser"
import { notifyAffiliateReferralAttribution } from "./notifyAffiliateReferralAttribution"
import {
  getPendingCreatorCode,
  isCreatorFlowActive,
} from "./creatorAccess"
import { supabase } from "./supabaseClient"
import { clearAppDataCache } from "./appDataCache"
import { invalidateExploreSession } from "./exploreSessionCache"
import { clearFeedSessionsForUser } from "./feedSessionCache"
import { clearConversationSessionsForUser } from "./conversationSessionCache"
import { clearImageUrlCache } from "./imageUrlCache"
import { invalidateStoriesSession } from "./storiesSessionCache"
import { resetRoutePrefetchSession } from "./routePrefetch"
import { warmAppDataCaches, resetDataPrefetchSession } from "./dataPrefetch"
import { resetNotificationRealtimeSession } from "./notificationRealtime"
import { clearAllNotificationsSessions } from "./notificationsSessionCache"
import { clearAllLeaderboardSessions } from "./leaderboardSessionCache"
import { clearAllNativeSilentCache } from "./nativeSilentCacheBridge"
import { fetchSettingsProfileRow } from "./settingsProfileSync"
import { readSettingsProfileCache, writeSettingsProfileCache } from "./settingsProfileCache"
import { clearAllMessagesInboxSessions } from "./messagesInboxSessionCache"
import { clearAllRoomSessions } from "./roomSessionCache"
import { clearAllSessionUserDataCaches } from "./sessionUserCache"
import {
  readUserBootstrapProfile,
  writeUserBootstrapProfile,
} from "./userBootstrapCache"
import { auditLogProfileLoaded } from "./onboardingChecklistAudit"
import { isProActive } from "./subscription"
import { syncMembershipAfterStripeCheckout as runMembershipSync } from "./syncMembershipAfterStripeCheckout"
import {
  captureStripeCheckoutSuccessFromUrl,
  clearStripeReconciliationSignals,
  dispatchStripeReconciliationComplete,
  markStripeReconciliationPending,
  shouldReconcileStripeMembership,
} from "./stripeReconciliation"
import { isDemoModeActive, disableDemoMode, subscribeDemoModeChanges } from "./demo/demoMode"
import {
  getDemoAuthUser,
  getDemoProfileSlice,
  seedDemoCaches,
} from "./demo/demoUser"
import { DEMO_PROFILE } from "./demo/fixtures"
import { DEMO_USER_ID, isDemoUserId } from "./demo/constants"
import { resolveBackendV2Flag, isBackendV2Enabled } from "./backendV2/flags.ts"
import {
  clearSessionBootstrapCache,
  loadSessionBootstrapForUser,
} from "./backendV2/sessionBootstrapRepository.ts"
import { clearDashboardBootstrapCache } from "./backendV2/dashboardBootstrapCache.ts"
import { clearFeedBootstrapCache } from "./backendV2/feedBootstrapCache.ts"
import { invalidateProfileBootstrapCache } from "./profileBootstrap/profileBootstrapCache.ts"
import { clearProfilePreviewCache } from "./profilePreviewCache.ts"
import { clearMessagingBootstrapCache } from "./backendV2/messagingBootstrapCache.ts"
import { clearRoomBootstrapCache } from "./backendV2/roomBootstrapCache.ts"
import { clearConversationThreadCache } from "./backendV2/conversationThreadBootstrapCache.ts"
import { clearConversationThreadAliases } from "./backendV2/conversationThreadInboxSeed.ts"
import { clearThreadReadLifecycle } from "./backendV2/conversationThreadReadLifecycle.ts"
import { clearThreadScrollSessions } from "./conversationThreadScroll.ts"
import { clearPropFirmBootstrapCache } from "./backendV2/propFirmBootstrapCache.ts"
import { patchSessionProfileSlice } from "./backendV2/sessionBootstrapCache.ts"
import { usePathname } from "next/navigation"
import { shouldWarmAppDataCachesForPath } from "./appWarmPaths"

/**
 * Shared profile columns for shell + dashboard + getting-started.
 * Avoids duplicate `profiles` reads across Navbar, checklist, and key pages.
 */
export const USER_PROFILE_SELECT =
  "id, name, username, bio, is_private, avatar_url, trading_style, trading_model, trader_type, primary_market, started_trading, username_change_count, referral_code, referral_count, is_pro, creator_access, creator_code, creator_granted_at, subscription_status, cancel_at_period_end, cancel_at, trial_end, current_period_end, stripe_customer_id, is_banned, banned_reason, is_beta_tester, use_free_tier, onboarding_completed, has_seen_getting_started_intro, has_seen_onboarding_complete_popup, max_drawdown_limit, has_email_password, signup_flow_source, early_access_enrolled_at, early_access_started_at, early_access_ends_at, early_access_status, early_access_campaign_id, early_access_enrollment_source, lifetime_access_source, lifetime_access_granted_at" as const

export type UserProfileSlice = {
  id: string
  name: string | null
  username: string | null
  avatar_url: string | null
  is_pro: boolean | null
  creator_access: boolean | null
  subscription_status: string | null
  trial_end: string | null
  stripe_customer_id: string | null
  signup_flow_source: string | null
  early_access_enrolled_at: string | null
  early_access_started_at: string | null
  early_access_ends_at: string | null
  early_access_status: string | null
  early_access_campaign_id: string | null
  early_access_enrollment_source: string | null
  lifetime_access_source: string | null
  lifetime_access_granted_at: string | null
  is_banned: boolean | null
  banned_reason: string | null
  referral_code: string | null
  is_beta_tester: boolean | null
  use_free_tier: boolean | null
  onboarding_completed: boolean | null
  has_seen_getting_started_intro: boolean | null
  has_seen_onboarding_complete_popup: boolean | null
  bio: string | null
  trading_style: string | null
  trader_type: string | null
  primary_market: string | null
  started_trading: string | null
  max_drawdown_limit: number | null
  is_private: boolean | null
  has_email_password: boolean | null
}

function pickUserProfileFields(row: unknown): UserProfileSlice | null {
  if (!row || typeof row !== "object") return null
  const o = row as Record<string, unknown>
  const id = o.id
  if (typeof id !== "string" || !id.trim()) return null

  return {
    id,
    name: o.name != null ? String(o.name) : null,
    username: o.username != null ? String(o.username) : null,
    avatar_url: o.avatar_url != null ? String(o.avatar_url) : null,
    is_pro: typeof o.is_pro === "boolean" ? o.is_pro : null,
    creator_access: typeof o.creator_access === "boolean" ? o.creator_access : null,
    subscription_status:
      o.subscription_status != null ? String(o.subscription_status) : null,
    trial_end: o.trial_end != null ? String(o.trial_end) : null,
    stripe_customer_id:
      o.stripe_customer_id != null ? String(o.stripe_customer_id) : null,
    signup_flow_source:
      o.signup_flow_source != null ? String(o.signup_flow_source) : null,
    early_access_enrolled_at:
      o.early_access_enrolled_at != null
        ? String(o.early_access_enrolled_at)
        : null,
    early_access_started_at:
      o.early_access_started_at != null
        ? String(o.early_access_started_at)
        : null,
    early_access_ends_at:
      o.early_access_ends_at != null ? String(o.early_access_ends_at) : null,
    early_access_status:
      o.early_access_status != null ? String(o.early_access_status) : null,
    early_access_campaign_id:
      o.early_access_campaign_id != null
        ? String(o.early_access_campaign_id)
        : null,
    early_access_enrollment_source:
      o.early_access_enrollment_source != null
        ? String(o.early_access_enrollment_source)
        : null,
    lifetime_access_source:
      o.lifetime_access_source != null
        ? String(o.lifetime_access_source)
        : null,
    lifetime_access_granted_at:
      o.lifetime_access_granted_at != null
        ? String(o.lifetime_access_granted_at)
        : null,
    is_banned: typeof o.is_banned === "boolean" ? o.is_banned : null,
    banned_reason: o.banned_reason != null ? String(o.banned_reason) : null,
    referral_code: o.referral_code != null ? String(o.referral_code) : null,
    is_beta_tester: typeof o.is_beta_tester === "boolean" ? o.is_beta_tester : null,
    use_free_tier: typeof o.use_free_tier === "boolean" ? o.use_free_tier : null,
    onboarding_completed:
      typeof o.onboarding_completed === "boolean" ? o.onboarding_completed : null,
    has_seen_getting_started_intro:
      typeof o.has_seen_getting_started_intro === "boolean"
        ? o.has_seen_getting_started_intro
        : null,
    has_seen_onboarding_complete_popup:
      typeof o.has_seen_onboarding_complete_popup === "boolean"
        ? o.has_seen_onboarding_complete_popup
        : null,
    bio: o.bio != null ? String(o.bio) : null,
    trading_style: o.trading_style != null ? String(o.trading_style) : null,
    trader_type: o.trader_type != null ? String(o.trader_type) : null,
    primary_market: o.primary_market != null ? String(o.primary_market) : null,
    started_trading: o.started_trading != null ? String(o.started_trading) : null,
    max_drawdown_limit: (() => {
      const v = o.max_drawdown_limit
      if (v == null || v === "") return null
      const n = typeof v === "number" ? v : Number(v)
      return Number.isFinite(n) ? n : null
    })(),
    is_private: typeof o.is_private === "boolean" ? o.is_private : null,
    has_email_password:
      typeof o.has_email_password === "boolean" ? o.has_email_password : null,
  }
}

type UserProfileContextValue = {
  user: any
  profile: UserProfileSlice | null
  loading: boolean
  /** True while post-Stripe membership/profile reconciliation is in flight. */
  membershipReconciling: boolean
  setProfile: Dispatch<SetStateAction<UserProfileSlice | null>>
  /** Re-fetch shared profile slice from Supabase (e.g. after ensure-profile upsert). */
  refreshProfile: () => Promise<void>
  /** After Stripe checkout — poll until trial/subscription is active; returns true when reconciled. */
  syncMembershipAfterStripeCheckout: () => Promise<boolean>
}

const UserProfileContext = createContext<UserProfileContextValue | null>(null)

const AUTH_SYNC_EVENTS: AuthChangeEvent[] = [
  "INITIAL_SESSION",
  "SIGNED_IN",
]

export function UserProfileProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const pathnameRef = useRef(pathname)
  pathnameRef.current = pathname

  const [user, setUser] = useState<any>(null)
  const [profile, setProfileState] = useState<UserProfileSlice | null>(null)
  const [loading, setLoading] = useState(true)
  const [membershipReconciling, setMembershipReconciling] = useState(false)
  const realtimeTopicSuffix = useId().replace(/:/g, "")
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null)
  const profileRealtimeUserIdRef = useRef<string | null>(null)
  const profileRef = useRef<UserProfileSlice | null>(null)
  const sessionUserIdRef = useRef<string | null>(null)
  const loadGenerationRef = useRef(0)
  profileRef.current = profile

  const removeProfileChannel = useCallback(() => {
    const ch = channelRef.current
    channelRef.current = null
    profileRealtimeUserIdRef.current = null
    if (ch) {
      void supabase.removeChannel(ch)
    }
  }, [])

  const applyProfileRealtimePayload = useCallback(
    (sessionUserId: string, row: unknown) => {
      const picked = pickUserProfileFields(row)
      if (!picked) return
      setProfileState(picked)
      if (isProActive(picked) && shouldReconcileStripeMembership(sessionUserId)) {
        clearStripeReconciliationSignals()
        dispatchStripeReconciliationComplete()
      }
      writeUserBootstrapProfile(sessionUserId, picked)
      if (row && typeof row === "object") {
        writeSettingsProfileCache(sessionUserId, row as Record<string, unknown>)
        if (isBackendV2Enabled("session")) {
          patchSessionProfileSlice(sessionUserId, row as Record<string, unknown>)
        }
      }
    },
    []
  )

  /** One viewer-profile Realtime channel — idempotent for the same authenticated user. */
  const ensureProfileRealtimeSubscription = useCallback(
    (
      sessionUserId: string,
      options?: { generation?: number; isActive?: () => boolean }
    ) => {
      if (isDemoUserId(sessionUserId)) return

      if (
        profileRealtimeUserIdRef.current === sessionUserId &&
        channelRef.current
      ) {
        return
      }

      removeProfileChannel()

      const topic = `profile:${sessionUserId}:${realtimeTopicSuffix}`
      const ch = supabase.channel(topic)
      channelRef.current = ch
      profileRealtimeUserIdRef.current = sessionUserId

      const generation = options?.generation
      const isActive = options?.isActive ?? (() => true)

      ch.on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "profiles",
          filter: `id=eq.${sessionUserId}`,
        },
        (payload) => {
          if (!isActive()) return
          if (
            generation !== undefined &&
            generation !== loadGenerationRef.current
          ) {
            return
          }
          applyProfileRealtimePayload(sessionUserId, payload.new)
        }
      )

      if (
        !isActive() ||
        (generation !== undefined && generation !== loadGenerationRef.current)
      ) {
        removeProfileChannel()
        return
      }

      ch.subscribe()
    },
    [applyProfileRealtimePayload, realtimeTopicSuffix, removeProfileChannel]
  )

  const setProfile = useCallback<Dispatch<SetStateAction<UserProfileSlice | null>>>(
    (action) => {
      setProfileState((prev) => {
        const next = typeof action === "function" ? action(prev) : action
        if (next == null) return null
        return pickUserProfileFields(next)
      })
    },
    []
  )

  const refreshProfile = useCallback(async () => {
    const userId = user?.id ?? profileRef.current?.id
    if (!userId) return
    if (isDemoUserId(userId)) return

    const row = await fetchSettingsProfileRow(supabase, userId, { force: true })
    const picked = pickUserProfileFields(row)
    if (picked) {
      setProfileState(picked)
      writeUserBootstrapProfile(userId, picked)
    }
  }, [user?.id])

  const profileReconcileInFlightRef = useRef(false)

  const syncMembershipAfterStripeCheckout = useCallback(async (): Promise<boolean> => {
    const userId = user?.id ?? profileRef.current?.id
    if (!userId || isDemoUserId(userId)) return false

    setMembershipReconciling(true)
    markStripeReconciliationPending(userId)

    try {
      const { profile: slice, reconciled } = await runMembershipSync(supabase, userId, {
        pickProfile: (row) => pickUserProfileFields(row),
      })

      if (reconciled && slice) {
        setProfileState(slice)
        clearStripeReconciliationSignals()
        warmAppDataCaches(supabase, userId)
        dispatchStripeReconciliationComplete()
        return true
      }

      return false
    } finally {
      setMembershipReconciling(false)
    }
  }, [user?.id])

  useEffect(() => {
    let mounted = true
    let loadGeneration = 0

    const clearAuthState = () => {
      loadGeneration += 1
      removeProfileChannel()
      const signedOutUserId = sessionUserIdRef.current
      sessionUserIdRef.current = null
      clearAppDataCache()
      invalidateExploreSession()
      invalidateStoriesSession()
      clearImageUrlCache()
      resetRoutePrefetchSession()
      resetDataPrefetchSession()
      resetNotificationRealtimeSession()
      clearAllMessagesInboxSessions()
      clearAllRoomSessions()
      clearAllSessionUserDataCaches()
      clearSessionBootstrapCache()
      clearDashboardBootstrapCache()
      clearFeedBootstrapCache()
      clearMessagingBootstrapCache()
      clearRoomBootstrapCache()
      clearConversationThreadCache()
      clearConversationThreadAliases()
      clearThreadReadLifecycle()
      clearThreadScrollSessions()
      clearPropFirmBootstrapCache()
      if (signedOutUserId) {
        invalidateProfileBootstrapCache({ viewerKey: signedOutUserId })
      }
      clearProfilePreviewCache()
      clearAllNotificationsSessions()
      clearAllLeaderboardSessions()
      void clearAllNativeSilentCache()
      if (signedOutUserId) {
        clearFeedSessionsForUser(signedOutUserId)
        clearConversationSessionsForUser(signedOutUserId)
        clearConversationThreadCache(signedOutUserId)
        clearConversationThreadAliases(signedOutUserId)
        clearThreadReadLifecycle(signedOutUserId)
        clearThreadScrollSessions(signedOutUserId)
      }
      if (!mounted) return
      setUser(null)
      setProfileState(null)
      setLoading(false)
    }

    async function runDeferredBootstrap(
      sessionUserId: string,
      generation: number,
      initialProfile: UserProfileSlice | null
    ) {
      const storedBetaRef = isBetaReferralRef(readStoredReferralCode())
      if (storedBetaRef) {
        const repair = await applyBetaReferralIfEligible(supabase, sessionUserId)
        if (!mounted || generation !== loadGeneration) return

        if (repair.applied) {
          const refetched = await fetchSettingsProfileRow(supabase, sessionUserId, {
            force: true,
          })
          if (!mounted || generation !== loadGeneration) return
          const picked = pickUserProfileFields(refetched)
          if (picked) {
            setProfileState(picked)
            writeUserBootstrapProfile(sessionUserId, picked)
          }
        } else if (initialProfile) {
          clearBetaReferralAfterApply(initialProfile.is_beta_tester)
        }
      }

      if (!mounted || generation !== loadGeneration) return
      if (shouldWarmAppDataCachesForPath(pathnameRef.current)) {
        ensureProfileRealtimeSubscription(sessionUserId, {
          generation,
          isActive: () => mounted && generation === loadGeneration,
        })
      }
    }

    async function applyDemoAuthSession(generation: number) {
      const demoUser = getDemoAuthUser()
      sessionUserIdRef.current = demoUser.id
      setUser(demoUser)
      const profileSlice = getDemoProfileSlice()
      setProfileState(profileSlice)
      writeUserBootstrapProfile(demoUser.id, profileSlice)
      writeSettingsProfileCache(demoUser.id, DEMO_PROFILE as Record<string, unknown>)
      seedDemoCaches()
      auditLogProfileLoaded({
        userId: demoUser.id,
        onboarding_completed: profileSlice.onboarding_completed,
        has_seen_getting_started_intro: profileSlice.has_seen_getting_started_intro,
        has_seen_onboarding_complete_popup:
          profileSlice.has_seen_onboarding_complete_popup,
        profileLoading: false,
        profileLoaded: true,
      })
      if (mounted && generation === loadGeneration) {
        setLoading(false)
      }
    }

    async function applyAuthSession(
      session: Session | null,
      authEvent: AuthChangeEvent | "demo" = "INITIAL_SESSION"
    ) {
      const generation = ++loadGeneration
      loadGenerationRef.current = generation

      removeProfileChannel()

      const sessionUser = session?.user ?? null

      if (!mounted || generation !== loadGeneration) return

      sessionUserIdRef.current = sessionUser?.id ?? null
      setUser(sessionUser)

      if (!sessionUser) {
        if (isDemoModeActive()) {
          await applyDemoAuthSession(generation)
          return
        }
        setProfileState(null)
        setLoading(false)
        return
      }

      const cachedRow =
        readSettingsProfileCache(sessionUser.id) ??
        readUserBootstrapProfile(sessionUser.id)
      const cachedPicked = pickUserProfileFields(cachedRow)
      const billingProfilePending =
        cachedPicked?.onboarding_completed === true &&
        !isProActive({
          is_pro: cachedPicked.is_pro,
          creator_access: cachedPicked.creator_access,
          subscription_status: cachedPicked.subscription_status,
          trial_end: cachedPicked.trial_end,
          early_access_enrolled_at: cachedPicked.early_access_enrolled_at,
          early_access_started_at: cachedPicked.early_access_started_at,
          early_access_status: cachedPicked.early_access_status,
          early_access_ends_at: cachedPicked.early_access_ends_at,
          early_access_campaign_id: cachedPicked.early_access_campaign_id,
          early_access_enrollment_source:
            cachedPicked.early_access_enrollment_source,
        })
      if (cachedPicked) {
        setProfileState(cachedPicked)
        // Unblock shell first paint: Session RPC continues in parallel.
        // Navbar badges/admin subscribe to Session cache; gates use cached profile.
        if (!billingProfilePending) {
          setLoading(false)
        }
        auditLogProfileLoaded({
          userId: sessionUser.id,
          onboarding_completed: cachedPicked.onboarding_completed,
          has_seen_getting_started_intro:
            cachedPicked.has_seen_getting_started_intro,
          has_seen_onboarding_complete_popup:
            cachedPicked.has_seen_onboarding_complete_popup,
          profileLoading: billingProfilePending,
          profileLoaded: !billingProfilePending,
        })
      }

      // Bucket A: Dashboard bootstrap in parallel with Session — app routes, or fresh sign-in.
      const shouldWarmDashboard =
        shouldWarmAppDataCachesForPath(pathnameRef.current) ||
        authEvent === "SIGNED_IN"
      if (
        !shouldReconcileStripeMembership(sessionUser.id) &&
        shouldWarmDashboard
      ) {
        warmAppDataCaches(supabase, sessionUser.id)
      }

      let resolvedProfile: Record<string, unknown> | null = null
      const sessionFlag = resolveBackendV2Flag("session")
      const isDemo = isDemoUserId(sessionUser.id)

      try {
        if (sessionFlag.enabled && !isDemo) {
          const loaded = await loadSessionBootstrapForUser(
            supabase,
            sessionUser.id,
            {
              authEvent,
              caller: "UserProfileProvider.applyAuthSession",
            }
          )
          resolvedProfile = {
            ...loaded.bootstrap.data.session_profile,
            name: loaded.bootstrap.data.viewer.display_name,
          }
          writeSettingsProfileCache(sessionUser.id, resolvedProfile)
          writeUserBootstrapProfile(sessionUser.id, resolvedProfile)
        } else {
          resolvedProfile = await fetchSettingsProfileRow(
            supabase,
            sessionUser.id
          )

          if (!resolvedProfile) {
            const ensureResult = await ensureProfileForUser(supabase, {
              userId: sessionUser.id,
              name: null,
              referredBy: readStoredReferralCode(),
              userMetadata: sessionUser.user_metadata,
              signupFlowSource:
                isCreatorFlowActive() || getPendingCreatorCode()
                  ? "creator"
                  : String(sessionUser.app_metadata?.provider ?? "").toLowerCase() ===
                      "email"
                    ? "standard_email"
                    : "standard_oauth",
            })

            if (ensureResult.ok) {
              if (ensureResult.created && readStoredReferralCode()?.trim()) {
                notifyAffiliateReferralAttribution()
              }
              resolvedProfile = await fetchSettingsProfileRow(
                supabase,
                sessionUser.id,
                {
                  force: true,
                }
              )
              if (resolvedProfile && isBetaReferralRef(readStoredReferralCode())) {
                clearBetaReferralAfterApply(
                  typeof resolvedProfile.is_beta_tester === "boolean"
                    ? resolvedProfile.is_beta_tester
                    : null
                )
              }
            } else if (ensureResult.error) {
              console.error("ensureProfileForUser:", ensureResult.error)
            }
          }
        }
      } catch (err) {
        console.error("[UserProfileProvider] profile hydrate:", err)
        if (sessionFlag.enabled && !resolvedProfile) {
          try {
            resolvedProfile = await fetchSettingsProfileRow(
              supabase,
              sessionUser.id,
              { force: true }
            )
          } catch (fallbackErr) {
            console.error(
              "[UserProfileProvider] session RPC fallback REST failed:",
              fallbackErr
            )
          }
        }
      }

      if (!mounted || generation !== loadGeneration) return

      const picked = pickUserProfileFields(resolvedProfile)
      if (picked) {
        setProfileState(picked)
        writeUserBootstrapProfile(sessionUser.id, picked)
        if (
          isProActive(picked) &&
          shouldReconcileStripeMembership(sessionUser.id)
        ) {
          clearStripeReconciliationSignals()
          dispatchStripeReconciliationComplete()
        }
        auditLogProfileLoaded({
          userId: sessionUser.id,
          onboarding_completed: picked.onboarding_completed,
          has_seen_getting_started_intro: picked.has_seen_getting_started_intro,
          has_seen_onboarding_complete_popup:
            picked.has_seen_onboarding_complete_popup,
          profileLoading: false,
          profileLoaded: true,
        })
      }

      if (mounted && generation === loadGeneration) {
        setLoading(false)
      }

      if (picked) {
        void runDeferredBootstrap(sessionUser.id, generation, picked)
      }
    }

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      if (!mounted) return

      // TOKEN_REFRESHED / USER_UPDATED / PASSWORD_RECOVERY → never Session Bootstrap.
      if (event === "SIGNED_OUT") {
        clearAuthState()
        if (isDemoModeActive() && mounted) {
          void applyDemoAuthSession(++loadGeneration)
        }
        return
      }

      if (!AUTH_SYNC_EVENTS.includes(event)) {
        return
      }

      const nextUserId = session?.user?.id ?? null

      // Same authenticated user already applied this mount — never re-enter.
      // Covers INITIAL_SESSION after SIGNED_IN (and the reverse) without a 2nd apply.
      if (nextUserId && nextUserId === sessionUserIdRef.current) {
        if (process.env.NODE_ENV === "development") {
          console.info(
            "[backendV2.session] skip auth re-apply — same user already applied",
            { event, userId: nextUserId }
          )
        }
        return
      }

      if (event === "SIGNED_IN") {
        // Fresh sign-in (logged out → logged in) exits preview.
        if (nextUserId && !sessionUserIdRef.current) {
          disableDemoMode()
        }
      }

      // Remount / new listener: refs may be null while global flight/cache exists.
      // applyAuthSession still runs to hydrate React state; RPC single-flights to 0–1 calls.
      void applyAuthSession(session, event)
    })

    const unsubDemoMode = subscribeDemoModeChanges(() => {
      if (!mounted) return
      if (isDemoModeActive()) {
        if (!sessionUserIdRef.current) {
          void applyDemoAuthSession(++loadGeneration)
        }
        return
      }
      if (sessionUserIdRef.current === DEMO_USER_ID) {
        clearAuthState()
      }
    })

    if (isDemoModeActive() && !sessionUserIdRef.current) {
      void applyDemoAuthSession(++loadGeneration)
    }

    return () => {
      mounted = false
      loadGeneration += 1
      subscription.unsubscribe()
      unsubDemoMode()
      removeProfileChannel()
    }
  }, [ensureProfileRealtimeSubscription, realtimeTopicSuffix, removeProfileChannel])

  // Entering an app route after auth on marketing/login — start Dashboard warm + profile WS once.
  useEffect(() => {
    const uid = sessionUserIdRef.current
    if (!uid || isDemoUserId(uid)) return
    if (!shouldWarmAppDataCachesForPath(pathname)) return
    if (shouldReconcileStripeMembership(uid)) return

    warmAppDataCaches(supabase, uid)
    ensureProfileRealtimeSubscription(uid)
  }, [ensureProfileRealtimeSubscription, pathname, realtimeTopicSuffix])

  useEffect(() => {
    captureStripeCheckoutSuccessFromUrl()
  }, [])

  useEffect(() => {
    if (typeof window === "undefined") return
    const userId = user?.id
    if (!userId || isDemoUserId(userId)) return

    const attemptReconcile = () => {
      if (!shouldReconcileStripeMembership(userId)) return
      if (profileReconcileInFlightRef.current) return
      profileReconcileInFlightRef.current = true
      void syncMembershipAfterStripeCheckout().finally(() => {
        profileReconcileInFlightRef.current = false
      })
    }

    attemptReconcile()
    window.addEventListener("focus", attemptReconcile)
    return () => window.removeEventListener("focus", attemptReconcile)
  }, [user?.id, syncMembershipAfterStripeCheckout])

  const value = useMemo(
    () => ({
      user,
      profile,
      loading,
      membershipReconciling,
      setProfile,
      refreshProfile,
      syncMembershipAfterStripeCheckout,
    }),
    [
      user,
      profile,
      loading,
      membershipReconciling,
      setProfile,
      refreshProfile,
      syncMembershipAfterStripeCheckout,
    ]
  )

  return (
    <UserProfileContext.Provider value={value}>{children}</UserProfileContext.Provider>
  )
}

export function useUserProfile() {
  const context = useContext(UserProfileContext)
  if (!context) {
    throw new Error("useUserProfile must be used within UserProfileProvider")
  }
  return context
}
