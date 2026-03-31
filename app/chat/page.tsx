"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState, useRef } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"

export default function ChatPage() {
  const [messages, setMessages] = useState<any[]>([])
  const [input, setInput] = useState("")
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [user, setUser] = useState<any>(null)
  const [profile, setProfile] = useState<any>(null)
  const [channel, setChannel] = useState<"random" | "trades">("random")

  const [isAtBottom, setIsAtBottom] = useState(true)
  const [newMessages, setNewMessages] = useState(0)

  const scrollRef = useRef<HTMLDivElement>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const router = useRouter()

  useEffect(() => {
    init()
  }, [])

  useEffect(() => {
    fetchMessages()
  }, [channel])

  async function init() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    if (!user) {
      router.push("/login")
      return
    }

    setUser(user)

    const { data: prof } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", user.id)
      .single()

    setProfile(prof)

    setupRealtime()
  }

  function setupRealtime() {
    const channelSub = supabase
      .channel("chat-global")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "messages" },
        async (payload) => {
          const msg = payload.new
          if (msg.channel !== channel) return

          const { data: prof } = await supabase
            .from("profiles")
            .select("id, username")
            .eq("id", msg.user_id)
            .single()

          setMessages((prev) => {
            if (prev.some((m) => m.id === msg.id)) return prev

            if (!isAtBottom) {
              setNewMessages((c) => c + 1)
            }

            return [...prev, { ...msg, profiles: prof }]
          })
        }
      )
      .subscribe()

    return () => supabase.removeChannel(channelSub)
  }

  async function fetchMessages() {
    const { data } = await supabase
      .from("messages")
      .select(`
        *,
        profiles (id, username),
        message_likes (*)
      `)
      .eq("channel", channel)
      .order("created_at", { ascending: true })

    setMessages(data || [])

    // 🔥 scroll to bottom on load
    setTimeout(() => {
      if (scrollRef.current) {
        scrollRef.current.scrollTop = scrollRef.current.scrollHeight
      }
    }, 100)
  }

  async function sendMessage() {
    if (!input.trim() && !selectedFile) return

    let imageUrl = null

    if (selectedFile) {
      const fileName = `${Date.now()}-${selectedFile.name}`

      await supabase.storage
        .from("screenshots")
        .upload(fileName, selectedFile)

      imageUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${fileName}`
    }

    const temp = {
      id: Math.random(),
      content: input,
      image_url: imageUrl,
      created_at: new Date().toISOString(),
      profiles: { username: profile?.username }
    }

    setMessages((prev) => [...prev, temp])

    await supabase.from("messages").insert({
      user_id: user.id,
      content: input,
      image_url: imageUrl,
      channel
    })

    setInput("")
    setSelectedFile(null)
    if (fileRef.current) fileRef.current.value = ""
  }

  async function react(messageId: string, type: string) {
    const scrollPos = scrollRef.current?.scrollTop

    const { data: existing } = await supabase
      .from("message_likes")
      .select("*")
      .eq("message_id", messageId)
      .eq("user_id", user.id)
      .eq("type", type)

    if (existing && existing.length > 0) {
      await supabase
        .from("message_likes")
        .delete()
        .eq("message_id", messageId)
        .eq("user_id", user.id)
        .eq("type", type)
    } else {
      await supabase.from("message_likes").insert({
        message_id: messageId,
        user_id: user.id,
        type
      })
    }

    await fetchMessages()

    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollPos || 0
    }
  }

  function countReactions(msg: any, type: string) {
    return msg.message_likes?.filter((l: any) => l.type === type).length || 0
  }

  function formatTimeEST(date: string) {
    return new Date(date).toLocaleTimeString("en-US", {
      timeZone: "America/New_York",
      hour: "numeric",
      minute: "2-digit"
    })
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white flex flex-col items-center p-6">

        {/* HEADER */}
        <div className="text-center mb-4">
          <h1 className="text-3xl font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Global Chat
          </h1>
        </div>

        {/* CHANNEL SWITCH */}
        <div className="flex gap-4 mb-4">
          {["random", "trades"].map((c) => (
            <button
              key={c}
              onClick={() => setChannel(c as any)}
              className={`px-4 py-2 rounded ${
                channel === c ? "bg-emerald-500" : "bg-white/10"
              }`}
            >
              {c === "random" ? "Random Chat" : "Random ChatTrades"}
            </button>
          ))}
        </div>

        {/* CHAT BOX */}
        <div className="relative w-full max-w-4xl h-[70vh] bg-black/20 border border-white/10 rounded-xl flex flex-col overflow-hidden">

          {/* NEW MESSAGE BUTTON */}
          {newMessages > 0 && (
            <div className="absolute bottom-24 left-1/2 -translate-x-1/2 z-50">
              <button
                onClick={() => {
                  if (scrollRef.current) {
                    scrollRef.current.scrollTop = scrollRef.current.scrollHeight
                  }
                  setNewMessages(0)
                }}
                className="bg-blue-500 px-4 py-2 rounded-full"
              >
                {newMessages} new message{newMessages > 1 ? "s" : ""}
              </button>
            </div>
          )}

          {/* MESSAGES */}
          <div
            ref={scrollRef}
            onScroll={() => {
              const el = scrollRef.current
              if (!el) return

              const bottom =
                el.scrollHeight - el.scrollTop - el.clientHeight < 50

              setIsAtBottom(bottom)
              if (bottom) setNewMessages(0)
            }}
            className="flex-1 overflow-y-auto p-4 space-y-4"
          >
            {messages.map((msg) => (
              <div key={msg.id} className="bg-white/5 p-4 rounded-xl">

                <div className="flex justify-between text-sm">
                  <span
                    onClick={() => router.push(`/profile/${msg.profiles?.id}`)}
                    className="text-emerald-400 cursor-pointer hover:underline transition"
                  >
                    {msg.profiles?.username || "user"}
                  </span>
                  <span className="text-gray-400">
                    {formatTimeEST(msg.created_at)}
                  </span>
                </div>

                {msg.content && <p className="mt-1">{msg.content}</p>}

                {msg.image_url && (
                  <img src={msg.image_url} className="mt-3 rounded-lg max-h-64" />
                )}

                <div className="flex gap-4 mt-2 text-sm">
                  <button onClick={() => react(msg.id, "like")}>
                    👍 {countReactions(msg, "like")}
                  </button>
                  <button onClick={() => react(msg.id, "dislike")}>
                    👎 {countReactions(msg, "dislike")}
                  </button>
                  <button onClick={() => react(msg.id, "laugh")}>
                    😂 {countReactions(msg, "laugh")}
                  </button>
                </div>

              </div>
            ))}
          </div>

          {/* INPUT */}
          <div className="border-t border-white/10 p-4 flex gap-2 bg-[#020617]">

            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Send message..."
              className="flex-1 p-3 bg-black rounded border border-white/10"
              onKeyDown={(e) => e.key === "Enter" && sendMessage()}
            />

            <input
              ref={fileRef}
              type="file"
              onChange={(e) => setSelectedFile(e.target.files?.[0] || null)}
              className="text-sm"
            />

            <button
              onClick={sendMessage}
              className="bg-gradient-to-r from-blue-500 to-emerald-500 px-6 rounded"
            >
              Send
            </button>

          </div>

        </div>

      </div>
    </>
  )
}