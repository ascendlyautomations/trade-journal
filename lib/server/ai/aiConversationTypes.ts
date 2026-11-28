export type AiConversationKind =
  | "trade"
  | "general_trade"
  | "psychology"
  /** @deprecated use `general_trade` */
  | "portfolio"

export type AiPortfolioScope = {
  accountIds?: string[] | "all"
  preset?: "all_time" | "last_7" | "last_30" | "last_90" | "custom"
  startDate?: string | null
  endDate?: string | null
}

export type AiMessageAttachment = {
  kind: "screenshot" | "uploaded_image" | "trade"
  url?: string
  storagePath?: string | null
  tradeId?: string | null
}

export type AiTurnUserMessageInput = {
  id: string
  displayContent: string
  openaiContent?: string | null
  promptKey?: string | null
  attachments?: AiMessageAttachment[]
  createdAt?: string | null
}

export type AiTurnAssistantMessageInput = {
  id: string
  content: string
  promptKey?: string | null
  attachments?: AiMessageAttachment[]
  createdAt?: string | null
}

export type AiPersistTurnResult = {
  conversationId: string
  userMessageId: string
  assistantMessageId: string
  insertedUser: boolean
  insertedAssistant: boolean
}