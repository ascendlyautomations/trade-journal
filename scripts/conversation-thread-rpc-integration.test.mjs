#!/usr/bin/env node
/**
 * Authenticated integration smoke test for rpc_v1_conversation_thread_bootstrap.
 * Skips when staging credentials are absent.
 */

import { createClient } from "@supabase/supabase-js"

const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
const anonKey =
  process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const email = process.env.SUPABASE_TEST_EMAIL
const password = process.env.SUPABASE_TEST_PASSWORD
const conversationId = process.env.SUPABASE_TEST_CONVERSATION_ID

if (!url || !anonKey || !email || !password || !conversationId) {
  console.log(
    "[conversation-thread-rpc-integration] SKIP — set SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_TEST_EMAIL, SUPABASE_TEST_PASSWORD, SUPABASE_TEST_CONVERSATION_ID"
  )
  process.exit(0)
}

const client = createClient(url, anonKey)

const { error: signInError } = await client.auth.signInWithPassword({
  email,
  password,
})
if (signInError) {
  console.error("[conversation-thread-rpc-integration] sign-in failed", signInError)
  process.exit(1)
}

const { data, error } = await client.rpc("rpc_v1_conversation_thread_bootstrap", {
  p_conversation_id: conversationId,
  p_message_limit: 50,
  p_cursor: null,
  p_mark_read: false,
})

if (error) {
  console.error("[conversation-thread-rpc-integration] RPC failed", error)
  process.exit(1)
}

const payload = data?.data
if (!payload?.conversation?.id) {
  console.error("[conversation-thread-rpc-integration] invalid payload", data)
  process.exit(1)
}

console.log("[conversation-thread-rpc-integration] OK", {
  conversationId: payload.conversation.id,
  messageCount: payload.messages?.length ?? 0,
  hasMore: payload.has_more_messages,
})

process.exit(0)
