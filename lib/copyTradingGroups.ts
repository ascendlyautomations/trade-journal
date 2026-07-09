import type { SupabaseClient } from "@supabase/supabase-js"
import type { TradingAccountListItem } from "./tradingAccounts"
import { tradingAccountDisplayTitle } from "./tradingAccounts"

export type CopyTradingGroup = {
  id: string
  name: string
  accountIds: string[]
  createdAt: string
  updatedAt: string
}

export const COPY_TRADING_GROUPS_DESCRIPTION =
  "Automatically journal the same trade across multiple trading accounts. Perfect for traders running copy traders across prop firm or personal accounts."

export const COPY_TRADING_GROUPS_SETTINGS_DESCRIPTION =
  "If you trade multiple funded or personal accounts using a copy trader, Copy Trading Groups let you journal every account simultaneously with a single trade submission."

type CopyTradingGroupRow = {
  id: string
  name: string
  created_at: string
  updated_at: string
}

type CopyTradingGroupAccountRow = {
  group_id: string
  account_id: string
  sort_order: number
}

function mapGroupRows(
  groups: CopyTradingGroupRow[],
  members: CopyTradingGroupAccountRow[]
): CopyTradingGroup[] {
  const membersByGroup = new Map<string, CopyTradingGroupAccountRow[]>()
  for (const member of members) {
    const list = membersByGroup.get(member.group_id) ?? []
    list.push(member)
    membersByGroup.set(member.group_id, list)
  }

  return groups.map((group) => {
    const groupMembers = (membersByGroup.get(group.id) ?? []).sort(
      (a, b) => a.sort_order - b.sort_order || a.account_id.localeCompare(b.account_id)
    )
    return {
      id: group.id,
      name: group.name,
      accountIds: groupMembers.map((row) => row.account_id),
      createdAt: group.created_at,
      updatedAt: group.updated_at,
    }
  })
}

export async function fetchCopyTradingGroups(
  client: SupabaseClient,
  userId: string
): Promise<{ groups: CopyTradingGroup[]; error: Error | null }> {
  const { data: groupRows, error: groupError } = await client
    .from("copy_trading_groups")
    .select("id, name, created_at, updated_at")
    .eq("user_id", userId)
    .order("name", { ascending: true })

  if (groupError) {
    return { groups: [], error: new Error(groupError.message) }
  }

  const groups = (groupRows ?? []) as CopyTradingGroupRow[]
  if (groups.length === 0) {
    return { groups: [], error: null }
  }

  const groupIds = groups.map((group) => group.id)
  const { data: memberRows, error: memberError } = await client
    .from("copy_trading_group_accounts")
    .select("group_id, account_id, sort_order")
    .eq("user_id", userId)
    .in("group_id", groupIds)

  if (memberError) {
    return { groups: [], error: new Error(memberError.message) }
  }

  return {
    groups: mapGroupRows(groups, (memberRows ?? []) as CopyTradingGroupAccountRow[]),
    error: null,
  }
}

export function resolveCopyGroupAccounts(
  group: CopyTradingGroup,
  accounts: TradingAccountListItem[]
): TradingAccountListItem[] {
  const byId = new Map(accounts.map((account) => [account.id, account]))
  return group.accountIds
    .map((accountId) => byId.get(accountId))
    .filter((account): account is TradingAccountListItem => account != null)
}

export function formatCopyGroupAccountLabels(
  group: CopyTradingGroup,
  accounts: TradingAccountListItem[]
): string[] {
  return resolveCopyGroupAccounts(group, accounts).map((account) =>
    tradingAccountDisplayTitle(account)
  )
}

export async function createCopyTradingGroup(
  client: SupabaseClient,
  userId: string,
  name: string,
  accountIds: string[]
): Promise<{ group: CopyTradingGroup | null; error: Error | null }> {
  const trimmedName = name.trim()
  if (!trimmedName) {
    return { group: null, error: new Error("Group name is required") }
  }
  if (accountIds.length === 0) {
    return { group: null, error: new Error("Select at least one account") }
  }

  const { data: groupRow, error: insertError } = await client
    .from("copy_trading_groups")
    .insert({ user_id: userId, name: trimmedName })
    .select("id, name, created_at, updated_at")
    .single()

  if (insertError || !groupRow) {
    if (insertError?.code === "23505") {
      return { group: null, error: new Error("A group with this name already exists") }
    }
    return {
      group: null,
      error: new Error(insertError?.message ?? "Could not create group"),
    }
  }

  const memberRows = accountIds.map((accountId, index) => ({
    group_id: groupRow.id,
    account_id: accountId,
    user_id: userId,
    sort_order: index,
  }))

  const { error: memberError } = await client
    .from("copy_trading_group_accounts")
    .insert(memberRows)

  if (memberError) {
    await client.from("copy_trading_groups").delete().eq("id", groupRow.id)
    return { group: null, error: new Error(memberError.message) }
  }

  return {
    group: {
      id: groupRow.id,
      name: groupRow.name,
      accountIds: [...accountIds],
      createdAt: groupRow.created_at,
      updatedAt: groupRow.updated_at,
    },
    error: null,
  }
}

export async function updateCopyTradingGroup(
  client: SupabaseClient,
  userId: string,
  groupId: string,
  name: string,
  accountIds: string[]
): Promise<{ group: CopyTradingGroup | null; error: Error | null }> {
  const trimmedName = name.trim()
  if (!trimmedName) {
    return { group: null, error: new Error("Group name is required") }
  }
  if (accountIds.length === 0) {
    return { group: null, error: new Error("Select at least one account") }
  }

  const { data: groupRow, error: updateError } = await client
    .from("copy_trading_groups")
    .update({ name: trimmedName })
    .eq("id", groupId)
    .eq("user_id", userId)
    .select("id, name, created_at, updated_at")
    .single()

  if (updateError || !groupRow) {
    if (updateError?.code === "23505") {
      return { group: null, error: new Error("A group with this name already exists") }
    }
    return {
      group: null,
      error: new Error(updateError?.message ?? "Could not update group"),
    }
  }

  const { error: deleteError } = await client
    .from("copy_trading_group_accounts")
    .delete()
    .eq("group_id", groupId)
    .eq("user_id", userId)

  if (deleteError) {
    return { group: null, error: new Error(deleteError.message) }
  }

  const memberRows = accountIds.map((accountId, index) => ({
    group_id: groupId,
    account_id: accountId,
    user_id: userId,
    sort_order: index,
  }))

  const { error: memberError } = await client
    .from("copy_trading_group_accounts")
    .insert(memberRows)

  if (memberError) {
    return { group: null, error: new Error(memberError.message) }
  }

  return {
    group: {
      id: groupRow.id,
      name: groupRow.name,
      accountIds: [...accountIds],
      createdAt: groupRow.created_at,
      updatedAt: groupRow.updated_at,
    },
    error: null,
  }
}

export async function deleteCopyTradingGroup(
  client: SupabaseClient,
  userId: string,
  groupId: string
): Promise<{ error: Error | null }> {
  const { error } = await client
    .from("copy_trading_groups")
    .delete()
    .eq("id", groupId)
    .eq("user_id", userId)

  if (error) {
    return { error: new Error(error.message) }
  }

  return { error: null }
}
