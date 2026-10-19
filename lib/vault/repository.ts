import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import type {
  VaultContentFilter,
  VaultContentRef,
  VaultFolder,
  VaultItem,
  VaultItemState,
  VaultListPage,
} from "./types"
import { VAULT_NOT_SAVED, vaultRefKey } from "./types"
import { normalizedVaultFolderName } from "./support"

type Client = SupabaseClient<Database>

type StateBatchWire = {
  content_type: string
  content_id: string
  vault_item_id: string
  folder_ids?: string[] | null
}

export async function vaultStateBatch(
  client: Client,
  refs: VaultContentRef[]
): Promise<Map<string, VaultItemState>> {
  const result = new Map<string, VaultItemState>()
  if (refs.length === 0) return result

  const payload = refs.map((r) => ({
    content_type: r.contentType,
    content_id: r.contentID,
  }))

  const { data, error } = await client.rpc("rpc_v1_vault_state_batch", {
    p_items: payload,
  })
  if (error) {
    for (const ref of refs) result.set(vaultRefKey(ref), VAULT_NOT_SAVED)
    return result
  }

  const wire = (Array.isArray(data) ? data : []) as StateBatchWire[]
  for (const entry of wire) {
    const ref: VaultContentRef = {
      contentType: entry.content_type as VaultContentRef["contentType"],
      contentID: entry.content_id,
    }
    result.set(vaultRefKey(ref), {
      isVaulted: true,
      vaultItemID: entry.vault_item_id,
      folderIDs: entry.folder_ids ?? [],
    })
  }
  for (const ref of refs) {
    const key = vaultRefKey(ref)
    if (!result.has(key)) result.set(key, VAULT_NOT_SAVED)
  }
  return result
}

export async function vaultListFolders(client: Client): Promise<VaultFolder[]> {
  const { data, error } = await client
    .from("vault_folders")
    .select("id,user_id,name,created_at,updated_at")
    .order("name", { ascending: true })
  if (error || !data) return []
  return data.map((row) => ({
    id: row.id,
    name: row.name,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }))
}

export async function vaultCreateFolder(
  client: Client,
  userId: string,
  name: string
): Promise<VaultFolder> {
  const normalized = normalizedVaultFolderName(name)
  if (!normalized) throw new Error("Folder name cannot be empty.")
  const { data, error } = await client
    .from("vault_folders")
    .insert({ user_id: userId, name: normalized })
    .select("id,user_id,name,created_at,updated_at")
    .single()
  if (error || !data) throw error ?? new Error("Could not create folder.")
  return {
    id: data.id,
    name: data.name,
    createdAt: data.created_at,
    updatedAt: data.updated_at,
  }
}

export async function vaultRenameFolder(
  client: Client,
  folderId: string,
  name: string
): Promise<VaultFolder> {
  const normalized = normalizedVaultFolderName(name)
  if (!normalized) throw new Error("Folder name cannot be empty.")
  const { data, error } = await client
    .from("vault_folders")
    .update({
      name: normalized,
      updated_at: new Date().toISOString(),
    })
    .eq("id", folderId)
    .select("id,user_id,name,created_at,updated_at")
    .single()
  if (error || !data) throw error ?? new Error("Could not rename folder.")
  return {
    id: data.id,
    name: data.name,
    createdAt: data.created_at,
    updatedAt: data.updated_at,
  }
}

export async function vaultDeleteFolder(
  client: Client,
  folderId: string
): Promise<void> {
  const { error } = await client.from("vault_folders").delete().eq("id", folderId)
  if (error) throw error
}

async function folderMembership(
  client: Client,
  itemIds: string[]
): Promise<Record<string, string[]>> {
  if (itemIds.length === 0) return {}
  const { data, error } = await client
    .from("vault_folder_items")
    .select("folder_id,vault_item_id")
    .in("vault_item_id", itemIds)
  if (error || !data) return {}
  const map: Record<string, string[]> = {}
  for (const row of data) {
    const list = map[row.vault_item_id] ?? []
    list.push(row.folder_id)
    map[row.vault_item_id] = list
  }
  return map
}

export async function vaultSaveToVault(
  client: Client,
  userId: string,
  ref: VaultContentRef,
  folderId: string | null
): Promise<VaultItem> {
  const { data: row, error } = await client
    .from("vault_items")
    .upsert(
      {
        user_id: userId,
        content_type: ref.contentType,
        content_id: ref.contentID,
      },
      { onConflict: "user_id,content_type,content_id" }
    )
    .select("id,user_id,content_type,content_id,created_at")
    .single()
  if (error || !row) throw error ?? new Error("Could not save to Vault.")

  if (folderId) {
    const { error: linkError } = await client.from("vault_folder_items").insert({
      folder_id: folderId,
      vault_item_id: row.id,
    })
    if (linkError && !String(linkError).includes("23505")) throw linkError
  }

  const folderMap = await folderMembership(client, [row.id])
  return {
    id: row.id,
    ref,
    createdAt: row.created_at,
    folderIDs: folderMap[row.id] ?? [],
  }
}

export async function vaultAddToFolder(
  client: Client,
  vaultItemId: string,
  folderId: string
): Promise<void> {
  const { error } = await client.from("vault_folder_items").insert({
    folder_id: folderId,
    vault_item_id: vaultItemId,
  })
  if (error && !String(error).includes("23505")) throw error
}

export async function vaultRemoveFromFolder(
  client: Client,
  vaultItemId: string,
  folderId: string
): Promise<void> {
  const { error } = await client
    .from("vault_folder_items")
    .delete()
    .eq("folder_id", folderId)
    .eq("vault_item_id", vaultItemId)
  if (error) throw error
}

export async function vaultRemoveFromVault(
  client: Client,
  vaultItemId: string
): Promise<void> {
  const { error } = await client.from("vault_items").delete().eq("id", vaultItemId)
  if (error) throw error
}

export async function vaultListItems(
  client: Client,
  filter: VaultContentFilter,
  folderId: string | null,
  cursor: string | null,
  limit: number
): Promise<VaultListPage> {
  if (folderId) {
    return listItemsInFolder(client, folderId, cursor, limit)
  }
  return listAllItems(client, filter, cursor, limit)
}

async function listAllItems(
  client: Client,
  filter: VaultContentFilter,
  cursor: string | null,
  limit: number
): Promise<VaultListPage> {
  let query = client
    .from("vault_items")
    .select("id,user_id,content_type,content_id,created_at")
    .order("created_at", { ascending: false })
    .limit(limit)

  if (cursor) {
    query = query.lt("created_at", cursor)
  }

  switch (filter) {
    case "trades":
      query = query.eq("content_type", "trade")
      break
    case "clips":
      query = query.eq("content_type", "reel")
      break
    case "posts":
      query = query.in("content_type", ["profile_post", "feed_post"])
      break
    case "achievements":
      query = query.eq("content_type", "achievement")
      break
    default:
      break
  }

  const { data: rows, error } = await query
  if (error || !rows) return { items: [], nextCursor: null }

  const folderMap = await folderMembership(
    client,
    rows.map((r) => r.id)
  )
  const items: VaultItem[] = rows
    .map((row) => ({
      id: row.id,
      ref: {
        contentType: row.content_type as VaultContentRef["contentType"],
        contentID: row.content_id,
      },
      createdAt: row.created_at,
      folderIDs: folderMap[row.id] ?? [],
    }))
    .filter((item) => item.ref.contentType)

  const nextCursor =
    rows.length >= limit ? rows[rows.length - 1]?.created_at ?? null : null
  return { items, nextCursor }
}

async function listItemsInFolder(
  client: Client,
  folderId: string,
  cursor: string | null,
  limit: number
): Promise<VaultListPage> {
  let linkQuery = client
    .from("vault_folder_items")
    .select("folder_id,vault_item_id,created_at")
    .eq("folder_id", folderId)
    .order("created_at", { ascending: false })
    .limit(limit)

  if (cursor) {
    linkQuery = linkQuery.lt("created_at", cursor)
  }

  const { data: links, error: linkError } = await linkQuery
  if (linkError || !links?.length) return { items: [], nextCursor: null }

  const ids = links.map((l) => l.vault_item_id)
  const { data: rows, error } = await client
    .from("vault_items")
    .select("id,user_id,content_type,content_id,created_at")
    .in("id", ids)
  if (error || !rows) return { items: [], nextCursor: null }

  const order = new Map(ids.map((id, index) => [id, index]))
  const sorted = [...rows].sort(
    (a, b) => (order.get(a.id) ?? 999) - (order.get(b.id) ?? 999)
  )

  const folderMap = await folderMembership(client, sorted.map((r) => r.id))
  const items: VaultItem[] = sorted.map((row) => ({
    id: row.id,
    ref: {
      contentType: row.content_type as VaultContentRef["contentType"],
      contentID: row.content_id,
    },
    createdAt: row.created_at,
    folderIDs: folderMap[row.id] ?? [],
  }))

  const nextCursor =
    links.length >= limit ? links[links.length - 1]?.created_at ?? null : null
  return { items, nextCursor }
}
