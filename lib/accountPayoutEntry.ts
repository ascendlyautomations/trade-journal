import type { SupabaseClient } from "@supabase/supabase-js"
import { supportsManualPayoutLedger } from "@/lib/accountPayoutPolicy"
import {
  encodeWithdrawalDrawdownNote,
  parseWithdrawalDrawdownBehaviorFromNote,
} from "@/lib/livePersonalDrawdownNote"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { getLocalTodayDateInputValue } from "@/lib/tradeDateValidation"
import { invalidateWithdrawalsLedger } from "@/lib/withdrawalsLedgerInvalidate"

export const ACCOUNT_PAYOUT_ENTRY_SELECT =
  "id,account_id,user_id,amount,payout_date,note,image_url,created_at,updated_at" as const

export type AccountPayoutEntryRecord = {
  id: string
  account_id: string
  user_id: string
  amount: number
  payout_date: string
  note: string | null
  image_url: string | null
}

function mapAccountPayoutEntryRow(
  row: Record<string, unknown>
): AccountPayoutEntryRecord | null {
  const id = String(row.id ?? "").trim()
  const account_id = String(row.account_id ?? "").trim()
  if (!id || !account_id) return null
  return {
    id,
    account_id,
    user_id: String(row.user_id ?? "").trim(),
    amount: Number(row.amount) || 0,
    payout_date: String(row.payout_date ?? "").trim(),
    note: row.note != null ? String(row.note) : null,
    image_url: row.image_url != null ? String(row.image_url) : null,
  }
}

export function mergePayoutEntryNotePreservingDrawdownPrefix(
  originalNote: string | null | undefined,
  userNote: string
): string | null {
  const behavior = parseWithdrawalDrawdownBehaviorFromNote(originalNote)
  const trimmed = String(userNote ?? "").trim()
  if (!behavior) return trimmed.length > 0 ? trimmed : null
  return encodeWithdrawalDrawdownNote(behavior, trimmed)
}

export type AccountPayoutEntryDraft = {
  amountDigits: string
  payoutDate: string
  note: string
}

export type CreateAccountPayoutEntryInput = {
  supabase: SupabaseClient
  userId: string
  accountId: string
  draft: AccountPayoutEntryDraft
  account?: { category?: unknown; mode?: unknown } | null
  /** Live personal drawdown — encoded into note prefix when set. */
  liveWithdrawalDrawdownBehavior?: "reset_to_account" | "keep_trailing" | null
}

export type CreateAccountPayoutEntryResult =
  | { ok: true; entryId: string }
  | { ok: false; message: string }

function plainNumericString(value: string): string {
  return value.replace(/,/g, "").trim()
}

export function parseWithdrawalAmount(
  amountDigits: string
): number | null {
  const trimmed = plainNumericString(amountDigits)
  if (!trimmed) return null
  const parsed = Number(trimmed)
  if (!Number.isFinite(parsed) || parsed <= 0) return null
  return parsed
}

export function validateAccountPayoutEntryDraft(
  draft: AccountPayoutEntryDraft,
  options?: { today?: string }
): string | null {
  const amount = parseWithdrawalAmount(draft.amountDigits)
  if (amount == null) {
    return "Enter a withdrawal amount greater than zero."
  }
  const payoutDate = String(draft.payoutDate ?? "").trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(payoutDate)) {
    return "Choose a valid withdrawal date."
  }
  const today = options?.today ?? getLocalTodayDateInputValue()
  if (payoutDate > today) {
    return "Withdrawal date cannot be in the future."
  }
  return null
}

export function buildAccountPayoutEntryInsertBody(
  userId: string,
  accountId: string,
  draft: AccountPayoutEntryDraft
): {
  account_id: string
  user_id: string
  amount: number
  payout_date: string
  note: string | null
} {
  const amount = parseWithdrawalAmount(draft.amountDigits)
  if (amount == null) {
    throw new Error("Enter a withdrawal amount greater than zero.")
  }
  const note = String(draft.note ?? "").trim()
  return {
    account_id: accountId,
    user_id: userId,
    amount,
    payout_date: String(draft.payoutDate).trim(),
    note: note.length > 0 ? note : null,
  }
}

export async function createAccountPayoutEntry(
  input: CreateAccountPayoutEntryInput
): Promise<CreateAccountPayoutEntryResult> {
  const { supabase, userId, accountId, draft, account } = input

  if (account && !supportsManualPayoutLedger(account)) {
    return {
      ok: false,
      message:
        "This account uses Prop Firm Mode to record payouts. Open Prop Firm Mode and use Record Payout.",
    }
  }

  const validationError = validateAccountPayoutEntryDraft(draft)
  if (validationError) {
    return { ok: false, message: validationError }
  }

  let body: ReturnType<typeof buildAccountPayoutEntryInsertBody>
  try {
    body = buildAccountPayoutEntryInsertBody(userId, accountId, draft)
    if (input.liveWithdrawalDrawdownBehavior) {
      body = {
        ...body,
        note: encodeWithdrawalDrawdownNote(
          input.liveWithdrawalDrawdownBehavior,
          draft.note
        ),
      }
    }
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Invalid withdrawal.",
    }
  }

  const { data, error } = await supabase
    .from("account_payout_entries")
    .insert(body)
    .select("id")
    .single()

  if (error) {
    return { ok: false, message: handleSupabaseError(error) }
  }

  const entryId = String(data?.id ?? "").trim()
  if (!entryId) {
    return { ok: false, message: "Withdrawal could not be saved. Please try again." }
  }

  invalidateWithdrawalsLedger()
  return { ok: true, entryId }
}

export type ManualPayoutLedgerEntry = {
  amount: number
  payout_date: string
  note?: string | null
}

export type FetchAccountPayoutEntriesResult = {
  entries: AccountPayoutEntryRecord[]
  error: string | null
}

/** Manual ledger rows for the signed-in owner (all accounts). */
export async function fetchAccountPayoutEntriesForUser(
  supabase: SupabaseClient,
  userId: string
): Promise<FetchAccountPayoutEntriesResult> {
  const ownerId = String(userId).trim()
  if (!ownerId) {
    return { entries: [], error: "Sign in to load withdrawal history." }
  }

  const { data, error } = await supabase
    .from("account_payout_entries")
    .select(ACCOUNT_PAYOUT_ENTRY_SELECT)
    .eq("user_id", ownerId)
    .order("payout_date", { ascending: false })
    .order("id", { ascending: false })

  if (error) {
    return { entries: [], error: handleSupabaseError(error) }
  }

  const entries = (data ?? [])
    .map((row) => mapAccountPayoutEntryRow(row as Record<string, unknown>))
    .filter((row): row is AccountPayoutEntryRecord => row != null)

  return { entries, error: null }
}

export async function fetchAccountPayoutEntriesForAccountIds(
  supabase: SupabaseClient,
  accountIds: string[]
): Promise<AccountPayoutEntryRecord[]> {
  const unique = [...new Set(accountIds.map((id) => String(id).trim()).filter(Boolean))]
  if (unique.length === 0) return []

  const { data, error } = await supabase
    .from("account_payout_entries")
    .select(ACCOUNT_PAYOUT_ENTRY_SELECT)
    .in("account_id", unique)
    .order("payout_date", { ascending: false })
    .order("id", { ascending: false })

  if (error) {
    console.error("fetchAccountPayoutEntriesForAccountIds", error)
    return []
  }

  return (data ?? [])
    .map((row) => mapAccountPayoutEntryRow(row as Record<string, unknown>))
    .filter((row): row is AccountPayoutEntryRecord => row != null)
}

export function groupPayoutEntriesByAccountId(
  entries: AccountPayoutEntryRecord[]
): Record<string, AccountPayoutEntryRecord[]> {
  const grouped: Record<string, AccountPayoutEntryRecord[]> = {}
  for (const entry of entries) {
    const key = entry.account_id
    if (!grouped[key]) grouped[key] = []
    grouped[key].push(entry)
  }
  return grouped
}

export async function fetchManualPayoutEntriesForAccount(
  supabase: SupabaseClient,
  accountId: string
): Promise<ManualPayoutLedgerEntry[]> {
  const rows = await fetchAccountPayoutEntriesForAccountIds(supabase, [accountId])
  return rows.map((row) => ({
    amount: row.amount,
    payout_date: row.payout_date,
    note: row.note,
  }))
}

export type UpdateAccountPayoutEntryInput = {
  supabase: SupabaseClient
  userId: string
  entryId: string
  draft: AccountPayoutEntryDraft
  /** Preserve `[[tt:dd=…]]` drawdown behavior prefix when editing notes. */
  priorNote?: string | null
}

export type MutateAccountPayoutEntryResult =
  | { ok: true; entry: AccountPayoutEntryRecord }
  | { ok: false; message: string }

export async function updateAccountPayoutEntry(
  input: UpdateAccountPayoutEntryInput
): Promise<MutateAccountPayoutEntryResult> {
  const ownerId = String(input.userId).trim()
  const entryId = String(input.entryId).trim()
  if (!ownerId || !entryId) {
    return { ok: false, message: "Withdrawal could not be updated." }
  }

  const validationError = validateAccountPayoutEntryDraft(input.draft)
  if (validationError) {
    return { ok: false, message: validationError }
  }

  const amount = parseWithdrawalAmount(input.draft.amountDigits)
  if (amount == null) {
    return { ok: false, message: "Enter a withdrawal amount greater than zero." }
  }

  const note = mergePayoutEntryNotePreservingDrawdownPrefix(
    input.priorNote ?? null,
    input.draft.note
  )

  const { data, error } = await input.supabase
    .from("account_payout_entries")
    .update({
      amount,
      payout_date: String(input.draft.payoutDate).trim(),
      note,
    })
    .eq("id", entryId)
    .eq("user_id", ownerId)
    .select(ACCOUNT_PAYOUT_ENTRY_SELECT)
    .maybeSingle()

  if (error) {
    return { ok: false, message: handleSupabaseError(error) }
  }
  if (!data) {
    return {
      ok: false,
      message: "Withdrawal not found or you do not have permission to edit it.",
    }
  }

  const entry = mapAccountPayoutEntryRow(data as Record<string, unknown>)
  if (!entry) {
    return { ok: false, message: "Withdrawal could not be updated." }
  }

  invalidateWithdrawalsLedger()
  return { ok: true, entry }
}

export async function deleteAccountPayoutEntry(
  supabase: SupabaseClient,
  userId: string,
  entryId: string
): Promise<{ ok: true } | { ok: false; message: string }> {
  const ownerId = String(userId).trim()
  const id = String(entryId).trim()
  if (!ownerId || !id) {
    return { ok: false, message: "Withdrawal could not be deleted." }
  }

  const { data, error } = await supabase
    .from("account_payout_entries")
    .delete()
    .eq("id", id)
    .eq("user_id", ownerId)
    .select("id")
    .maybeSingle()

  if (error) {
    return { ok: false, message: handleSupabaseError(error) }
  }
  if (!data) {
    return {
      ok: false,
      message: "Withdrawal not found or you do not have permission to delete it.",
    }
  }

  invalidateWithdrawalsLedger()
  return { ok: true }
}

export function sumManualWithdrawals(
  entries: ReadonlyArray<{ amount: number }>
): number {
  return entries.reduce((sum, entry) => sum + (Number(entry.amount) || 0), 0)
}

export function ledgerTrackedBalance(
  startingBalance: number,
  lifetimeRealizedPnL: number,
  payoutEntries: ReadonlyArray<{ amount: number }>,
  additionalWithdrawal = 0
): number {
  const withdrawals =
    sumManualWithdrawals(payoutEntries) + Math.max(0, additionalWithdrawal)
  return startingBalance + lifetimeRealizedPnL - withdrawals
}
