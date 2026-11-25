import { supabase } from "@/lib/supabaseClient"

/** Session-scoped grant so room members can preview a private trade shared in live chat (does not publish). */
export async function registerBroadcastChatTradeShare(options: {
  broadcastSessionId: string
  tradeId: string
  chatMessageId: string
}): Promise<void> {
  const sessionId = options.broadcastSessionId.trim()
  const tradeId = options.tradeId.trim()
  const chatMessageId = options.chatMessageId.trim()
  if (!sessionId || !tradeId || !chatMessageId) return

  const { error } = await supabase.rpc("rpc_v1_broadcast_chat_register_trade_share", {
    p_broadcast_session_id: sessionId,
    p_trade_id: tradeId,
    p_chat_message_id: chatMessageId,
  })

  if (error) {
    console.warn("[broadcast/chat] register trade share failed", error.message)
  }
}