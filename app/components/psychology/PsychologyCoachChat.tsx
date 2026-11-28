"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import type { PsychologyCoachFacts } from "@/lib/psychology/reports/types"
import { buildPsychologyCoachDeterministicSummary } from "@/lib/psychology/reports/coach"
import { normalizeAIGeneratedText } from "@/lib/normalizeAIGeneratedText"

type CoachMessage = { role: "user" | "assistant"; content: string; id?: string }

type PsychologyCoachChatProps = {
  facts: PsychologyCoachFacts
  initialConversationId?: string | null
  initialMessages?: CoachMessage[]
  initialFactsSnapshot?: PsychologyCoachFacts | null
}

type CoachApiResponse = {
  reply?: string
  error?: string
  conversationId?: string | null
  assistantMessageId?: string | null
  persistError?: string | null
}

export default function PsychologyCoachChat({
  facts: initialFacts,
  initialConversationId = null,
  initialMessages = [],
  initialFactsSnapshot = null,
}: PsychologyCoachChatProps) {
  const [facts, setFacts] = useState(
    initialFactsSnapshot ?? initialFacts
  )
  const deterministic = buildPsychologyCoachDeterministicSummary(facts).overview
  const [phase, setPhase] = useState<"idle" | "loading" | "ready" | "failed">("idle")
  const [conversationId, setConversationId] = useState<string | null>(
    initialConversationId
  )
  const [messages, setMessages] = useState<CoachMessage[]>(initialMessages)
  const [question, setQuestion] = useState("")
  const initialLoadDone = useRef(false)

  const callCoach = useCallback(
    async (
      mode: "explain" | "followUp",
      thread: CoachMessage[],
      options?: {
        createConversation?: boolean
        persistCachedOnly?: boolean
        cachedReply?: string
        userTurn?: { id: string; displayContent: string }
        assistantMessageId?: string
      }
    ) => {
      setPhase("loading")
      try {
        const headers = await supabaseBearerHeaders()
        const res = await fetch("/api/psychology-coach", {
          method: "POST",
          headers: { "Content-Type": "application/json", ...headers },
          body: JSON.stringify({
            facts,
            mode: mode === "followUp" ? "followUp" : "explain",
            messages: thread,
            conversationId: conversationId ?? undefined,
            createConversation: options?.createConversation ?? conversationId == null,
            persistCachedOnly: options?.persistCachedOnly ?? false,
            cachedReply: options?.cachedReply,
            assistantMessageId: options?.assistantMessageId,
            userMessage: options?.userTurn,
          }),
        })
        const data = (await res.json()) as CoachApiResponse
        if (!res.ok) {
          throw new Error(data.error ?? "Coach unavailable")
        }
        const reply = data.reply?.trim()
        if (!reply) throw new Error("Empty reply")
        if (data.conversationId) setConversationId(data.conversationId)
        return {
          reply: normalizeAIGeneratedText(reply),
          assistantMessageId: data.assistantMessageId ?? undefined,
        }
      } catch {
        setPhase("failed")
        return null
      }
    },
    [conversationId, facts]
  )

  useEffect(() => {
    if (initialLoadDone.current) return
    initialLoadDone.current = true
    if (initialMessages.length > 0) {
      setPhase("ready")
      return
    }
    let cancelled = false
    void (async () => {
      const result = await callCoach("explain", [], { createConversation: true })
      if (cancelled || !result) return
      setMessages([{ role: "assistant", content: result.reply, id: result.assistantMessageId }])
      setPhase("ready")
    })()
    return () => {
      cancelled = true
    }
  }, [callCoach, initialMessages.length])

  async function startNewConversation() {
    setConversationId(null)
    setMessages([])
    setFacts(initialFacts)
    setPhase("loading")
    const result = await callCoach("explain", [], { createConversation: true })
    if (result) {
      setMessages([{ role: "assistant", content: result.reply, id: result.assistantMessageId }])
      setPhase("ready")
    }
  }

  async function sendFollowUp() {
    const trimmed = question.trim()
    if (!trimmed || phase === "loading") return
    const userId = crypto.randomUUID()
    const userMessage: CoachMessage = { role: "user", content: trimmed, id: userId }
    const nextThread = [...messages, userMessage]
    setMessages(nextThread)
    setQuestion("")
    const result = await callCoach("followUp", nextThread, {
      createConversation: false,
      userTurn: { id: userId, displayContent: trimmed },
      assistantMessageId: crypto.randomUUID(),
    })
    if (result) {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: result.reply, id: result.assistantMessageId },
      ])
      setPhase("ready")
    }
  }

  const sendDisabled = !question.trim() || phase === "loading"

  return (
    <div
      className="tt-psych-coach flex min-h-[60vh] flex-col rounded-xl border border-white/10 bg-white/5"
      data-testid="psychologyCoach.view"
    >
      <div className="flex items-center justify-between gap-3 border-b border-white/10 px-4 py-3">
        <p className="text-xs text-gray-400">
          Scope: <span className="text-gray-300">{facts.scope.label}</span>
        </p>
        <button
          type="button"
          onClick={() => void startNewConversation()}
          className="text-xs font-medium text-blue-400 hover:text-blue-300"
          disabled={phase === "loading"}
        >
          New conversation
        </button>
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto p-4">
        <p className="text-xs text-gray-500">
          Your patterns are computed from your journal. The coach explains them, it
          never invents statistics.
        </p>

        {phase === "loading" && messages.length === 0 ? (
          <p className="text-sm text-gray-400">Loading coach…</p>
        ) : null}

        {phase === "failed" && messages.length === 0 ? (
          <div className="rounded-xl border border-white/10 bg-white/5 p-4">
            <p className="font-semibold text-white">Coach unavailable</p>
            <p className="mt-2 text-sm text-gray-400">{deterministic}</p>
          </div>
        ) : null}

        {messages.map((message, index) =>
          message.role === "assistant" ? (
            <CoachBubble key={message.id ?? `a-${index}`} text={message.content} />
          ) : (
            <UserBubble key={message.id ?? `u-${index}`} text={message.content} />
          )
        )}
      </div>

      <div className="border-t border-white/10 p-4">
        <div className="flex gap-2">
          <textarea
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="Ask a follow-up…"
            rows={2}
            className="min-h-[44px] flex-1 resize-none rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-sm text-white placeholder:text-gray-500"
            disabled={phase === "loading"}
          />
          <button
            type="button"
            onClick={() => void sendFollowUp()}
            disabled={sendDisabled}
            className="self-end rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
          >
            Send
          </button>
        </div>
        <p className="mt-2 text-[11px] text-gray-600">
          Not financial advice. Correlations in your data are not proof of causation.
        </p>
      </div>
    </div>
  )
}

function CoachBubble({ text }: { text: string }) {
  return (
    <div className="max-w-[95%] rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-gray-100">
      <MarkdownLite text={text} />
    </div>
  )
}

function UserBubble({ text }: { text: string }) {
  return (
    <div className="ml-auto max-w-[85%] rounded-xl bg-blue-600/20 px-4 py-3 text-sm text-blue-100">
      {text}
    </div>
  )
}

function MarkdownLite({ text }: { text: string }) {
  const lines = text.split("\n")
  return (
    <div className="space-y-2">
      {lines.map((line, i) => {
        const trimmed = line.trim()
        if (trimmed.startsWith("## ")) {
          return (
            <p key={i} className="font-semibold text-white">
              {trimmed.slice(3)}
            </p>
          )
        }
        if (trimmed.startsWith("- ")) {
          return (
            <p key={i} className="pl-2 text-gray-300">
              • {trimmed.slice(2)}
            </p>
          )
        }
        if (!trimmed) return <br key={i} />
        return (
          <p key={i} className="text-gray-200">
            {trimmed}
          </p>
        )
      })}
    </div>
  )
}