export const VAULT_FOLDER_NAME_MAX_LENGTH = 64

export function normalizedVaultFolderName(raw: string): string | null {
  const trimmed = raw.trim()
  if (!trimmed) return null
  if (trimmed.length > VAULT_FOLDER_NAME_MAX_LENGTH) {
    return trimmed.slice(0, VAULT_FOLDER_NAME_MAX_LENGTH)
  }
  return trimmed
}

export function mapVaultFolderMutationError(error: unknown): string {
  const text = String(error)
  if (text.includes("23505") || /duplicate/i.test(text)) {
    return "You already have a folder with that name."
  }
  return "Could not update folder."
}
