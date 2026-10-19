"use client"

import { useCallback, useEffect, useState } from "react"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import type { PsychologyCoachFacts } from "@/lib/psychology/reports/types"
import { buildPsychologyCoachDeterministicSummary } from "@/lib/psychology/reports/coach"

type CoachMessage = { role: "user" | "assistant"; content: string }

type PsychologyCoachChatProps = {
  facts: PsychologyCoachFacts
}

export default function PsychologyCoachChat({ facts }: PsychologyCoachChatProps) {
  const deterministic = buildPsychologyCoachDeterministicSummary(facts).overview
  const [phase, setPhase] = useState<"idle" | "loading" | "ready" | "failed">("idle")
  const [aiReply, setAiReply] = useState<string | null>(null)
  const [messages, setMessages] = useState<CoachMessage[]>([])
  const [question, setQuestion] = useState("")

  const callCoach = useCallback(
    async (mode: "explain" | "followUp", thread: CoachMessage[]) => {
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
          }),
        })
        const data = (await res.json()) as { reply?: string; error?: string }
        if (!res.ok) {
          throw new Error(data.error ?? "Coach unavailable")
        }
        const reply = data.reply?.trim()
        if (!reply) throw new Error("Empty reply")
        return reply
      } catch {
        setPhase("failed")
        return null
      }
    },
    [facts]
  )

  useEffect(() => {
    let cancelled = false
    void (async () => {
      setPhase("loading")
      const reply = await callCoach("explain", [])
      if (cancelled) return
      if (reply) {
        setAiReply(reply)
        setPhase("ready")
      }
    })()
    return () => {
      cancelled = true
    }
  }, [callCoach])

  async function sendFollowUp() {
    const trimmed = question.trim()
    if (!trimmed || phase === "loading") return
    const nextThread: CoachMessage[] = [
      ...messages,
      { role: "user", content: trimmed },
    ]
    setMessages(nextThread)
    setQuestion("")
    const reply = await callCoach("followUp", nextThread)
    if (reply) {
      setMessages((prev) => [...prev, { role: "assistant", content: reply }])
      setAiReply(reply)
      setPhase("ready")
    }
  }

  return (
    <div
      className="tt-psych-coach flex min-h-[60vh] flex-col rounded-xl border border-white/10 bg-white/5"
      data-testid="psychologyCoach.view"
    >
      <div className="flex-1 space-y-4 overflow-y-auto p-4">
        <p className="text-xs text-gray-500">
          Your patterns are computed from your journal. The coach explains them — it
          never invents statistics.
        </p>
        <p className="text-[11px] text-gray-600">
          Not financial advice. Correlations in your data are not proof of causation.
        </p>

        {phase === "loading" && !aiReply && messages.length === 0 ? (
          <p className="text-sm text-gray-400">Loading coach…</p>
        ) : null}

        {phase === "failed" && messages.length === 0 ? (
          <div className="rounded-xl border border-white/10 bg-white/5 p-4">
            <p className="font-semibold text-white">Coach unavailable</p>
            <p className="mt-2 text-sm text-gray-400">{deterministic}</p>
          </div>
        ) : null}

        {aiReply && messages.length === 0 ? (
          <CoachBubble text={aiReply} />
        ) : null}

        {messages.map((message, index) =>
          message.role === "assistant" ? (
            <CoachBubble key={`${index}-${message.content.slice(0, 24)}`} text={message.content} />
          ) : (
            <UserBubble key={`${index}-${message.content.slice(0, 24)}`} text={message.content} />
          )
        )}
      </div>

      <div className="flex gap-2 border-t border-white/10 bg-white/5 p-3">
        <textarea
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="Ask about your patterns…"
          rows={2}
          className="min-h-[44px] flex-1 resize-none rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-sm text-white outline-none focus:ring-1 focus:ring-blue-400/50"
        />
        <button
          type="button"
          disabled={!question.trim() || phase === "loading"}
          onClick={() => void sendFollowUp()}
          className="shrink-0 rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
        >
          Ask
        </button>
      </div>
    </div>
  )
}

function CoachBubble({ text }: { text: string }) {
  return (
    <div className="rounded-xl bg-blue-500/10 p-3 text-sm leading-relaxed text-gray-100">
      {text}
    </div>
  )
}

function UserBubble({ text }: { text: string }) {
  return (
    <div className="ml-8 rounded-xl bg-white/10 p-3 text-right text-sm text-gray-200">
      {text}
    </div>
  )
}
