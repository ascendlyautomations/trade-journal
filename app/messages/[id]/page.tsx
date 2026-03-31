"use client"

import Navbar from "../../components/Navbar"
import { useEffect, useState, useRef } from "react"
import { supabase } from "../../../lib/supabaseClient"
import { useParams, useRouter } from "next/navigation"

export default function DMPage() {
  const params = useParams()
  const router = useRouter()
  const id = params.id as string

  const [messages, setMessages] = useState<any[]>([])
  const [input, setInput] = useState("")
  const [user, setUser] = useState<any>(null)
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [otherUser, setOtherUser] = useState<any>(null)

  const scrollRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    init()

    const channel = setupRealtime()

    return () => {
      if (channel) supabase.removeChannel(channel)
    }
  }, [id])

  useEffect(() => {
    scrollToBottom()
  }, [messages])

  async function init() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    setUser(user)

    await fetchMessages()

    if (user) {
      await markConversationMessagesRead(user.id)
      await fetchOtherUser(user.id)
    }
  }

  async function fetchOtherUser(currentUserId: string) {
    const { data } = await supabase
      .from("conversation_participants")
      .select(`
        user_id,
        profiles (username)
      `)
      .eq("conversation_id", id)

    const other = data?.find((u: any) => u.user_id !== currentUserId)

    setOtherUser(other?.profiles || null)
  }

  function scrollToBottom() {
    setTimeout(() => {
      if (scrollRef.current) {
        scrollRef.current.scrollTop = scrollRef.current.scrollHeight
      }
    }, 50)
  }

  async function fetchMessages() {
    const { data } = await supabase
      .from("direct_messages")
      .select("*")
      .eq("conversation_id", id)
      .order("created_at", { ascending: true })

    setMessages(data || [])
  }

  async function markConversationMessagesRead(currentUserId: string) {
    await supabase
      .from("direct_messages")
      .update({ is_read: true })
      .eq("conversation_id", id)
      .eq("recipient_id", currentUserId)
      .eq("is_read", false)
  }

  function setupRealtime() {
    const channel = supabase
      .channel(`dm-${id}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "direct_messages",
          filter: `conversation_id=eq.${id}`
        },
        (payload) => {
          setMessages((prev) => {
            if (prev.some((m) => m.id === payload.new.id)) return prev
            return [...prev, payload.new]
          })
        }
      )
      .subscribe()

    return channel
  }

  function removeImage() {
    setSelectedFile(null)
  }

  async function sendMessage() {
    if (!user) return
    if (!input.trim() && !selectedFile) return

    let imageUrl = null

    if (selectedFile) {
      const fileName = `${Date.now()}-${selectedFile.name}`

      await supabase.storage
        .from("screenshots")
        .upload(fileName, selectedFile)

      imageUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${fileName}`
    }

    const { data: participants } = await supabase
      .from("conversation_participants")
      .select("user_id")
      .eq("conversation_id", id)

    const recipientId = participants?.find((p) => p.user_id !== user.id)
      ?.user_id
    if (!recipientId) return

    await supabase.from("direct_messages").insert({
      conversation_id: id,
      sender_id: user.id,
      recipient_id: recipientId,
      content: input || "",
      image_url: imageUrl,
      is_read: false,
    })

    setInput("")
    setSelectedFile(null)
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] flex items-center justify-center text-white p-4">

        <div className="w-full max-w-3xl h-[75vh] bg-black/30 border border-white/10 rounded-xl flex flex-col overflow-hidden">

          {/* HEADER */}
          <div className="p-4 border-b border-white/10 flex items-center gap-3">

            <button
              onClick={() => router.push("/messages")}
              className="text-sm px-3 py-1 bg-white/10 rounded hover:bg-white/20"
            >
              ← Back
            </button>

            <div className="flex flex-col">
              <span className="font-semibold">
                {otherUser?.username ? `@${otherUser.username}` : "Loading..."}
              </span>
              <span className="text-xs text-gray-400">
                Direct Message
              </span>
            </div>

          </div>

          {/* MESSAGES */}
          <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3">
            {messages.map((m) => {
              const isMe = m.sender_id === user?.id

              return (
                <div key={m.id} className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
                  <div className={`p-3 rounded-xl max-w-[70%] ${isMe ? "bg-blue-500" : "bg-gray-700"}`}>
                    {m.content && <p>{m.content}</p>}
                    {m.image_url && (
                      <img src={m.image_url} className="mt-2 rounded-lg max-h-64" />
                    )}
                  </div>
                </div>
              )
            })}
          </div>

          {/* INPUT */}
          <div className="border-t border-white/10 p-4 bg-[#020617]">

            <div className="flex gap-2">
              <input
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="Send message..."
                className="flex-1 p-3 bg-black rounded border border-white/10"
                onKeyDown={(e) => e.key === "Enter" && sendMessage()}
              />

              <button
                onClick={sendMessage}
                className="bg-gradient-to-r from-blue-500 to-emerald-500 px-5 py-3 rounded"
              >
                Send
              </button>
            </div>

            {/* 🔥 IMAGE SECTION */}
            <div className="mt-2 flex flex-col gap-2 text-xs text-gray-400">

              <input
                type="file"
                onChange={(e) =>
                  setSelectedFile(e.target.files?.[0] || null)
                }
              />

              {selectedFile ? (
                <div className="bg-white/5 p-2 rounded flex flex-col gap-2">

                  <span>{selectedFile.name}</span>

                  <img
                    src={URL.createObjectURL(selectedFile)}
                    className="max-h-40 rounded"
                  />

                  <button
                    onClick={removeImage}
                    className="text-red-400 hover:underline text-xs self-start"
                  >
                    Remove image
                  </button>

                </div>
              ) : (
                <span>No file chosen</span>
              )}

            </div>

          </div>

        </div>

      </div>
    </>
  )
}