"use client"

import { useEffect, useState } from "react"

type ChatMessage = { role: "user" | "assistant"; content: string }

export default function AIAssistant() {
  const [open, setOpen] = useState(false)
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState("")
  const [loading, setLoading] = useState(false)
  const [position, setPosition] = useState({ x: 0, y: 0 })
  const [dragging, setDragging] = useState(false)

  useEffect(() => {
    if (!dragging) return

    const onMove = (e: MouseEvent) => {
      setPosition((prev) => ({
        x: prev.x + e.movementX,
        y: prev.y + e.movementY,
      }))
    }

    const onUp = () => setDragging(false)

    window.addEventListener("mousemove", onMove)
    window.addEventListener("mouseup", onUp)

    return () => {
      window.removeEventListener("mousemove", onMove)
      window.removeEventListener("mouseup", onUp)
    }
  }, [dragging])

  const sendMessage = async () => {
    const text = input.trim()
    if (!text || loading) return

    const userMsg: ChatMessage = { role: "user", content: text }
    setMessages((prev) => [...prev, userMsg])
    setInput("")
    setLoading(true)

    try {
      const res = await fetch("/api/ai-chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text }),
      })

      const data = await res.json().catch(() => ({}))

      if (!res.ok) {
        const err =
          typeof data?.error === "string"
            ? data.error
            : "Something went wrong."
        setMessages((prev) => [
          ...prev,
          { role: "assistant", content: err },
        ])
        return
      }

      const reply =
        typeof data?.reply === "string" && data.reply.trim() !== ""
          ? data.reply
          : "No response."

      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: reply },
      ])
    } catch {
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          content: "Network error. Check your connection and try again.",
        },
      ])
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="pointer-events-none fixed bottom-5 right-5 z-50 flex flex-col items-end">
      <div className="pointer-events-auto">
        {!open ? (
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="rounded-full bg-blue-500 px-4 py-2 text-sm font-medium text-white shadow-lg shadow-black/30 hover:bg-blue-600"
          >
            Ask AI
          </button>
        ) : (
          <div
            className="w-[min(20rem,calc(100vw-2.5rem))] rounded-xl border border-white/10 bg-[#1e293b] p-3 shadow-lg shadow-black/40"
            style={{
              transform: `translate(${position.x}px, ${position.y}px)`,
            }}
          >
            <div
              className="mb-2 flex cursor-grab select-none items-center justify-between active:cursor-grabbing"
              onMouseDown={(e) => {
                if ((e.target as HTMLElement).closest("button")) return
                e.preventDefault()
                setDragging(true)
              }}
            >
              <p className="text-sm text-gray-300">Ask TradeTrax</p>
              <button
                type="button"
                onMouseDown={(e) => e.stopPropagation()}
                onClick={() => setOpen(false)}
                className="rounded px-2 py-0.5 text-gray-400 hover:bg-white/10 hover:text-white"
                aria-label="Close assistant"
              >
                ✕
              </button>
            </div>

            <div className="mb-2 h-64 space-y-2 overflow-y-auto text-sm">
              {messages.length === 0 ? (
                <p className="text-xs text-gray-500">
                  Ask how journaling, the feed, messages, or leaderboards work.
                </p>
              ) : (
                messages.map((m, i) => (
                  <div
                    key={i}
                    className={`break-words rounded-lg p-2 ${
                      m.role === "user"
                        ? "bg-blue-500 text-right text-white"
                        : "bg-[#0f172a] text-gray-200"
                    }`}
                  >
                    {m.content}
                  </div>
                ))
              )}
              {loading ? (
                <p className="text-xs text-gray-400">Thinking...</p>
              ) : null}
            </div>

            <div className="flex gap-2">
              <input
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault()
                    void sendMessage()
                  }
                }}
                disabled={loading}
                className="min-w-0 flex-1 rounded bg-[#0f172a] p-2 text-sm text-white placeholder:text-gray-500 outline-none ring-1 ring-white/10 focus:ring-blue-500/50 disabled:opacity-50"
                placeholder="Ask about TradeTrax…"
                aria-label="Message to AI assistant"
              />
              <button
                type="button"
                onClick={() => void sendMessage()}
                disabled={loading || !input.trim()}
                className="shrink-0 rounded bg-blue-500 px-3 py-2 text-sm font-medium text-white hover:bg-blue-600 disabled:opacity-40"
              >
                Send
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
