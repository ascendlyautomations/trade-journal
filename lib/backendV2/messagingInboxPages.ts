import type {
  MessagesBootstrapV1,
  MessagingConversationV1,
} from "./contracts.ts"

/** Safety stop if a cursor never advances. 25 pages × 80 rows covers large inboxes. */
export const MESSAGING_INBOX_MAX_PAGES = 25

/**
 * Inbox UI has no page control. Walk the existing bootstrap cursor so a long
 * inbox is not truncated at the first RPC page.
 */
export async function collectMessagingInboxConversations(
  first: MessagesBootstrapV1,
  loadNext: (cursor: string) => Promise<MessagesBootstrapV1>,
  shouldContinue: () => boolean = () => true
): Promise<MessagingConversationV1[]> {
  const seen = new Set<string>()
  const out: MessagingConversationV1[] = []

  const push = (rows: MessagingConversationV1[]) => {
    for (const row of rows) {
      if (seen.has(row.id)) continue
      seen.add(row.id)
      out.push(row)
    }
  }

  push(first.data.conversations)
  let cursor = first.data.next_cursor?.trim() || null
  let hasMore = first.data.page_meta.has_more === true
  let pages = 1

  while (
    hasMore &&
    cursor &&
    pages < MESSAGING_INBOX_MAX_PAGES &&
    shouldContinue()
  ) {
    const next = await loadNext(cursor)
    pages += 1
    const nextCursor = next.data.next_cursor?.trim() || null
    if (nextCursor === cursor) break
    push(next.data.conversations)
    cursor = nextCursor
    hasMore = next.data.page_meta.has_more === true
  }

  return out
}
