import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import type { AiMessageAttachment } from "@/lib/server/ai/aiConversationTypes"
import { signedUrlsForAttachments } from "@/lib/server/ai/aiAttachmentStorage"
import { buildAuthoritativeTradeContext } from "@/lib/server/ai/aiTradeContextBuilder"
import { buildAuthoritativeTradeAnalysisPrompt } from "@/lib/server/ai/buildTradeAnalysisUserPrompt"
import { publicImageUrlFromStoragePath } from "@/lib/server/ai/aiOpenAiTurn"

type Db = SupabaseClient<Database>

export function tradeIdsFromAttachments(
  attachments: AiMessageAttachment[]
): string[] {
  const ids: string[] = []
  for (const item of attachments) {
    if (item.kind !== "trade") continue
    const id = item.tradeId?.trim()
    if (id) ids.push(id)
  }
  return ids
}

export async function buildAttachedTradesPromptSection(
  db: Db,
  userId: string,
  tradeIds: string[]
): Promise<string> {
  if (tradeIds.length === 0) return ""
  const blocks: string[] = []
  for (const tradeId of tradeIds) {
    const context = await buildAuthoritativeTradeContext(db, userId, tradeId)
    if (!context) {
      blocks.push(
        `ATTACHED TRADE ${tradeId}: (not found or not owned by this user — do not invent data).`
      )
      continue
    }
    const label =
      typeof context.tradeForPrompt.ticker === "string"
        ? context.tradeForPrompt.ticker
        : tradeId
    const body = buildAuthoritativeTradeAnalysisPrompt(context, {
      hasScreenshot: Boolean(context.imagePath),
    })
    blocks.push(
      `ATTACHED TRADE — ${label} (${tradeId})\n${body}\n(Use the paired screenshot only when supplied for this attached trade.)`
    )
  }
  return blocks.join("\n\n")
}

/**
 * Image URLs for OpenAI: uploaded coach images + screenshots for explicitly attached trades only.
 */
export async function resolveOpenAiImageUrls(
  db: Db,
  userId: string,
  attachments: AiMessageAttachment[]
): Promise<string[]> {
  const urls: string[] = []
  const fileLike = attachments.filter(
    (a) => a.kind === "uploaded_image" || a.kind === "screenshot"
  )
  urls.push(...(await signedUrlsForAttachments(db, fileLike)))

  for (const item of attachments) {
    if (item.kind === "trade" && item.tradeId) {
      const context = await buildAuthoritativeTradeContext(db, userId, item.tradeId)
      if (!context?.imagePath) continue
      const url = publicImageUrlFromStoragePath(context.imagePath)
      if (url?.startsWith("http") && !urls.includes(url)) urls.push(url)
      continue
    }
    if (item.kind === "screenshot" && item.storagePath) {
      const url = publicImageUrlFromStoragePath(item.storagePath)
      if (url?.startsWith("http") && !urls.includes(url)) urls.push(url)
    }
  }
  return urls
}

export async function enrichPriorUserTurnContent(
  db: Db,
  userId: string,
  content: string,
  attachments: AiMessageAttachment[]
): Promise<string> {
  const tradeIds = tradeIdsFromAttachments(attachments)
  if (tradeIds.length === 0) return content
  const block = await buildAttachedTradesPromptSection(db, userId, tradeIds)
  if (!block.trim()) return content
  return `${content}\n\n${block}`
}