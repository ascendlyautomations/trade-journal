import { setAccountsCache, setTradesCache } from "@/lib/appDataCache"
import type { UserProfileSlice } from "@/lib/UserProfileProvider"
import { DEMO_USER_ID } from "./constants"
import { DEMO_ACCOUNTS, DEMO_PROFILE, DEMO_TRADES } from "./fixtures"

export function getDemoAuthUser() {
  return {
    id: DEMO_USER_ID,
    email: "demo@tradetraxs.local",
    aud: "authenticated",
    role: "authenticated",
    app_metadata: {},
    user_metadata: { name: DEMO_PROFILE.name },
  }
}

export function getDemoProfileSlice(): UserProfileSlice {
  return {
    id: DEMO_USER_ID,
    username: DEMO_PROFILE.username,
    avatar_url: DEMO_PROFILE.avatar_url,
    is_pro: DEMO_PROFILE.is_pro,
    creator_access: false,
    subscription_status: DEMO_PROFILE.subscription_status,
    trial_end: null,
    is_banned: DEMO_PROFILE.is_banned,
    banned_reason: DEMO_PROFILE.banned_reason,
    referral_code: DEMO_PROFILE.referral_code,
    is_beta_tester: DEMO_PROFILE.is_beta_tester,
    use_free_tier: false,
    onboarding_completed: DEMO_PROFILE.onboarding_completed,
    has_seen_getting_started_intro: DEMO_PROFILE.has_seen_getting_started_intro,
    has_seen_onboarding_complete_popup:
      DEMO_PROFILE.has_seen_onboarding_complete_popup,
    bio: DEMO_PROFILE.bio,
    trading_style: DEMO_PROFILE.trading_style,
    trader_type: DEMO_PROFILE.trader_type,
    primary_market: DEMO_PROFILE.primary_market,
    started_trading: DEMO_PROFILE.started_trading,
    max_drawdown_limit: DEMO_PROFILE.max_drawdown_limit,
    is_private: DEMO_PROFILE.is_private,
    has_email_password: DEMO_PROFILE.has_email_password,
  }
}

export function seedDemoCaches(): void {
  setTradesCache(DEMO_USER_ID, DEMO_TRADES)
  setAccountsCache(DEMO_USER_ID, [...DEMO_ACCOUNTS])
}
