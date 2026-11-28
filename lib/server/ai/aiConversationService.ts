import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database, Json } from "@/lib/database.types"
import type {
  AiPersistTurnResult,
  AiPortfolioScope,
  AiTurnAssistantMessageInput,
  AiTurnUserMessageInput,
} from "@/lib/server/ai/aiConversationTypes"

type Db = SupabaseClient<Database>

const conversations = "ai_coach_conversations" as const
const messages = "ai_coach_messages" as const

export async function openTradeConversation(
  db: Db,
  userId: string,
  tradeId: string
): Promise<{ conversationId: string; error?: string }> {
  const existing = await loadTradeConversationId(db, userId, tradeId)
  if (existing) return { conversationId: existing }

  const { data: trade } = await db
    .from("trades")
    .select("ticker")
    .eq("id", tradeId)
    .eq("user_id", userId)
    .maybeSingle()

  if (!trade) {
    return { conversationId: "", error: "forbidden" }
  }

  const title = `${trade.ticker?.trim() || "Trade"} · Trade AI`

  const { data, error } = await db
    .from(conversations)
    .insert({
      user_id: userId,
      kind: "trade",
      trade_id: tradeId,
      title,
    })
    .select("id")
    .single()

  if (error) {
    if (error.code === "23505") {
      const retry = await loadTradeConversationId(db, userId, tradeId)
      if (retry) return { conversationId: retry }
    }
    return { conversationId: "", error: error.message }
  }

  return { conversationId: String(data.id) }
}

export async function createPsychologyConversation(
  db: Db,
  userId: string,
  input: {
    title: string
    scopeLabel: string
    scopeFingerprint: string
    factsHash: string
    scope?: Record<string, unknown>
    factsSnapshot?: Record<string, unknown>
  }
): Promise<{ conversationId: string; error?: string }> {
  const scopePayload = {
    ...(input.scope ?? {}),
    label: input.scopeLabel,
    fingerprint: input.scopeFingerprint,
    factsHash: input.factsHash,
    ...(input.factsSnapshot ? { factsSnapshot: input.factsSnapshot } : {}),
  }
  const { data, error } = await db
    .from(conversations)
    .insert({
      user_id: userId,
      kind: "psychology",
      title: input.title.trim() || "Psychology Coach",
      scope_label: input.scopeLabel,
      scope_fingerprint: input.scopeFingerprint,
      facts_hash: input.factsHash,
      scope: scopePayload as Json,
    })
    .select("id")
    .single()

  if (error) return { conversationId: "", error: error.message }
  return { conversationId: String(data.id) }
}

export async function createPortfolioConversation(
  db: Db,
  userId: string,
  title: string,
  scope: AiPortfolioScope
): Promise<{ conversationId: string; error?: string }> {
  const preset = scope.preset ?? "all_time"
  const scopeLabel =
    preset === "custom"
      ? `Custom · ${scope.startDate ?? ""} – ${scope.endDate ?? ""}`
      : preset.replace(/_/g, " ")

  const { data, error } = await db
    .from(conversations)
    .insert({
      user_id: userId,
      kind: "general_trade",
      title: title.trim() || "General Trade AI",
      scope_label: scopeLabel,
      scope: scope as unknown as Json,
    })
    .select("id")
    .single()

  if (error) return { conversationId: "", error: error.message }
  return { conversationId: String(data.id) }
}

export async function appendAssistantMessageIdempotent(
  db: Db,
  userId: string,
  conversationId: string,
  assistant: AiTurnAssistantMessageInput
): Promise<{ inserted: boolean; error?: string }> {
  const { data: conv } = await db
    .from(conversations)
    .select("id")
    .eq("id", conversationId)
    .eq("user_id", userId)
    .maybeSingle()

  if (!conv) {
    return { inserted: false, error: "conversation_not_found" }
  }

  const { data: existing } = await db
    .from(messages)
    .select("id")
    .eq("user_id", userId)
    .eq("client_message_id", assistant.id)
    .maybeSingle()

  if (existing) return { inserted: false }

  const createdAt = assistant.createdAt ?? new Date().toISOString()
  const { error } = await db.from(messages).insert({
    id: assistant.id,
    conversation_id: conversationId,
    user_id: userId,
    role: "assistant",
    content: assistant.content,
    display_content: assistant.content,
    prompt_key: assistant.promptKey ?? null,
    client_message_id: assistant.id,
    attachments: assistant.attachments ?? [],
    created_at: createdAt,
  })

  if (error && error.code !== "23505") {
    return { inserted: false, error: error.message }
  }

  const preview = assistant.content.trim().slice(0, 240)
  await db
    .from(conversations)
    .update({
      last_message_preview: preview,
      last_message_at: createdAt,
      updated_at: new Date().toISOString(),
    })
    .eq("id", conversationId)
    .eq("user_id", userId)

  return { inserted: !error }
}

export async function appendTurnIdempotent(
  db: Db,
  userId: string,
  conversationId: string,
  user: AiTurnUserMessageInput,
  assistant: AiTurnAssistantMessageInput
): Promise<{ result: AiPersistTurnResult | null; error?: string }> {
  const { data: conv } = await db
    .from(conversations)
    .select("id")
    .eq("id", conversationId)
    .eq("user_id", userId)
    .maybeSingle()

  if (!conv) {
    return { result: null, error: "conversation_not_found" }
  }

  const userContent = user.openaiContent?.trim() || user.displayContent.trim()
  const userCreatedAt = user.createdAt ?? new Date().toISOString()
  const assistantCreatedAt = assistant.createdAt ?? new Date().toISOString()

  let insertedUser = false
  let insertedAssistant = false

  const { data: existingUser } = await db
    .from(messages)
    .select("id")
    .eq("user_id", userId)
    .eq("client_message_id", user.id)
    .maybeSingle()

  if (!existingUser) {
    const { error: userErr } = await db.from(messages).insert({
      id: user.id,
      conversation_id: conversationId,
      user_id: userId,
      role: "user",
      content: userContent || " ",
      display_content: user.displayContent,
      openai_content: user.openaiContent ?? null,
      prompt_key: user.promptKey ?? null,
      client_message_id: user.id,
      attachments: user.attachments ?? [],
      created_at: userCreatedAt,
    })
    if (userErr && userErr.code !== "23505") {
      return { result: null, error: userErr.message }
    }
    insertedUser = !userErr
  }

  const { data: existingAssistant } = await db
    .from(messages)
    .select("id")
    .eq("user_id", userId)
    .eq("client_message_id", assistant.id)
    .maybeSingle()

  if (!existingAssistant) {
    const { error: assistantErr } = await db.from(messages).insert({
      id: assistant.id,
      conversation_id: conversationId,
      user_id: userId,
      role: "assistant",
      content: assistant.content,
      client_message_id: assistant.id,
      attachments: assistant.attachments ?? [],
      created_at: assistantCreatedAt,
    })
    if (assistantErr && assistantErr.code !== "23505") {
      return { result: null, error: assistantErr.message }
    }
    insertedAssistant = !assistantErr
  }

  const preview = assistant.content.trim().slice(0, 240)
  await db
    .from(conversations)
    .update({
      last_message_preview: preview,
      last_message_at: assistantCreatedAt,
      updated_at: new Date().toISOString(),
    })
    .eq("id", conversationId)
    .eq("user_id", userId)

  return {
    result: {
      conversationId,
      userMessageId: user.id,
      assistantMessageId: assistant.id,
      insertedUser,
      insertedAssistant,
    },
  }
}

export async function loadConversationMessages(
  db: Db,
  userId: string,
  conversationId: string
) {
  const { data, error } = await db
    .from(messages)
    .select(
      "id, role, content, display_content, prompt_key, attachments, created_at"
    )
    .eq("conversation_id", conversationId)
    .eq("user_id", userId)
    .order("created_at", { ascending: true })

  if (error || !data) return []

  return data.map((row) => ({
    id: String(row.id),
    role: String(row.role),
    content: String(row.content),
    displayContent: row.display_content ?? null,
    promptKey: row.prompt_key ?? null,
    attachments: row.attachments,
    createdAt: String(row.created_at),
  }))
}

export async function loadTradeConversationId(
  db: Db,
  userId: string,
  tradeId: string
): Promise<string | null> {
  const { data } = await db
    .from(conversations)
    .select("id")
    .eq("user_id", userId)
    .eq("kind", "trade")
    .eq("trade_id", tradeId)
    .maybeSingle()
  return data?.id ? String(data.id) : null
}

export async function listConversationInbox(
  db: Db,
  userId: string,
  limit: number
) {
  const { data, error } = await db
    .from(conversations)
    .select(
      "id, kind, trade_id, title, scope, scope_label, last_message_preview, last_message_at, updated_at, created_at"
    )
    .eq("user_id", userId)
    .order("last_message_at", { ascending: false })
    .limit(limit)

  if (error) return { rows: [], error: error.message }
  return { rows: data ?? [], error: undefined }
}

export async function logAiUsage(
  db: Db,
  input: {
    userId: string
    conversationId?: string | null
    route: string
    model?: string | null
    promptTokens?: number | null
    completionTokens?: number | null
    totalTokens?: number | null
  }
): Promise<void> {
  await db.from("ai_usage_events").insert({
    user_id: input.userId,
    conversation_id: input.conversationId ?? null,
    route: input.route,
    model: input.model ?? null,
    prompt_tokens: input.promptTokens ?? null,
    completion_tokens: input.completionTokens ?? null,
    total_tokens: input.totalTokens ?? null,
  })
}