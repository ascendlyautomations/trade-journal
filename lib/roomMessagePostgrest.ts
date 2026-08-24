/** Dev-friendly logging for room_messages PostgREST failures. */
export function logRoomMessagePostgrestError(
  context: string,
  error: { code?: string; message?: string; details?: string } | null
): void {
  if (!error) return
  console.error(`room_messages ${context}:`, error)
  if (
    process.env.NODE_ENV !== "production" &&
    String(error.code ?? "") === "PGRST201"
  ) {
    console.error(
      "[room_messages] PGRST201: ambiguous room_message_reactions embed — use room_message_reactions!room_message_reactions_message_room_fkey(...)"
    )
  }
}
