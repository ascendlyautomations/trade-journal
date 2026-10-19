export type VaultContentType =
  | "trade"
  | "profile_post"
  | "feed_post"
  | "reel"
  | "achievement"

export type VaultContentRef = {
  contentType: VaultContentType
  contentID: string
}

export type VaultContentFilter =
  | "all"
  | "trades"
  | "clips"
  | "posts"
  | "achievements"

export type VaultItemState = {
  isVaulted: boolean
  vaultItemID: string | null
  folderIDs: string[]
}

export const VAULT_NOT_SAVED: VaultItemState = {
  isVaulted: false,
  vaultItemID: null,
  folderIDs: [],
}

export type VaultFolder = {
  id: string
  name: string
  createdAt: string
  updatedAt: string
}

export type VaultItem = {
  id: string
  ref: VaultContentRef
  createdAt: string
  folderIDs: string[]
}

export type VaultListPage = {
  items: VaultItem[]
  nextCursor: string | null
}

export function vaultRefKey(ref: VaultContentRef): string {
  return `${ref.contentType}:${ref.contentID}`
}

export function vaultContentFilterLabel(filter: VaultContentFilter): string {
  switch (filter) {
    case "all":
      return "All"
    case "trades":
      return "Trades"
    case "clips":
      return "Clips"
    case "posts":
      return "Posts"
    case "achievements":
      return "Achievements"
  }
}

export function vaultContentTypeLabel(type: VaultContentType): string {
  switch (type) {
    case "trade":
      return "Trades"
    case "profile_post":
    case "feed_post":
      return "Posts"
    case "reel":
      return "Clips"
    case "achievement":
      return "Achievements"
  }
}

export function vaultItemTitle(type: VaultContentType): string {
  switch (type) {
    case "trade":
      return "Trade"
    case "profile_post":
    case "feed_post":
      return "Post"
    case "reel":
      return "Clip"
    case "achievement":
      return "Achievement"
  }
}
