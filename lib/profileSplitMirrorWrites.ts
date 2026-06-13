import type { SupabaseClient } from "@supabase/supabase-js"

/** Mirror profiles.stripe_customer_id → billing_accounts (Phase 1B dual-write). */
export async function mirrorBillingAccountsStripeCustomerId(
  supabase: SupabaseClient,
  userId: string,
  stripeCustomerId: string
) {
  return supabase
    .from("billing_accounts")
    .upsert(
      { id: userId, stripe_customer_id: stripeCustomerId },
      { onConflict: "id" }
    )
}

/** Mirror profiles.onboarding_completed → account_settings (Phase 1B dual-write). */
export async function mirrorAccountSettingsOnboardingCompleted(
  supabase: SupabaseClient,
  userId: string,
  onboardingCompleted: boolean
) {
  return supabase
    .from("account_settings")
    .upsert(
      { id: userId, onboarding_completed: onboardingCompleted },
      { onConflict: "id" }
    )
}

/** Mirror profiles.max_drawdown_limit → account_settings (Phase 1B dual-write). */
export async function mirrorAccountSettingsMaxDrawdownLimit(
  supabase: SupabaseClient,
  userId: string,
  maxDrawdownLimit: number | null
) {
  return supabase
    .from("account_settings")
    .upsert(
      { id: userId, max_drawdown_limit: maxDrawdownLimit },
      { onConflict: "id" }
    )
}

/** Mirror profiles.has_used_csv_import → account_settings (Phase 1B dual-write). */
export async function mirrorAccountSettingsHasUsedCsvImport(
  supabase: SupabaseClient,
  userId: string,
  hasUsedCsvImport: boolean
) {
  return supabase
    .from("account_settings")
    .upsert(
      { id: userId, has_used_csv_import: hasUsedCsvImport },
      { onConflict: "id" }
    )
}

/** Mirror profiles.has_used_initial_import → account_settings (Phase 1B dual-write). */
export async function mirrorAccountSettingsHasUsedInitialImport(
  supabase: SupabaseClient,
  userId: string,
  hasUsedInitialImport: boolean
) {
  return supabase
    .from("account_settings")
    .upsert(
      { id: userId, has_used_initial_import: hasUsedInitialImport },
      { onConflict: "id" }
    )
}

/** Mirror profiles.username_change_count → account_settings (Phase 1B dual-write). */
export async function mirrorAccountSettingsUsernameChangeCount(
  supabase: SupabaseClient,
  userId: string,
  usernameChangeCount: number
) {
  return supabase
    .from("account_settings")
    .upsert(
      { id: userId, username_change_count: usernameChangeCount },
      { onConflict: "id" }
    )
}

export type LockedAccountMirrorValues = {
  locked_account_type: string | null
  locked_account_size: string | null
  locked_account_name: string | null
  locked_account_number: string | null
}

/** Mirror profiles locked_account_* → account_settings (Phase 1B dual-write). */
export async function mirrorAccountSettingsLockedAccount(
  supabase: SupabaseClient,
  userId: string,
  values: LockedAccountMirrorValues
) {
  return supabase.from("account_settings").upsert(
    {
      id: userId,
      locked_account_type: values.locked_account_type,
      locked_account_size: values.locked_account_size,
      locked_account_name: values.locked_account_name,
      locked_account_number: values.locked_account_number,
    },
    { onConflict: "id" }
  )
}
