"use client"

import { formatEST } from "@/lib/formatEST"
import { useEffect, useState, useRef } from "react"
import { supabase } from "../../lib/supabaseClient"
import { compressScreenshot } from "@/lib/compressImage"
import ImageCropModal from "@/app/components/ImageCropModal"
import { useImageCropUpload } from "@/lib/useImageCropUpload"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { logSupabaseError } from "@/lib/logSupabaseError"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { useRouter } from "next/navigation"
import { profilePath } from "@/lib/profileRoutes"
import { useUserProfile } from "@/lib/useUserProfile"

export default function ChatPage() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { user, profile, loading: authLoading } = useUserProfile()
  const [messages, setMessages] = useState<any[]>([])
  const [input, setInput] = useState("")
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const imageCrop = useImageCropUpload({
    preset: "content",
    onCropped: setSelectedFile,
  })
  const fileRef = imageCrop.fileInputRef
  const [channel, setChannel] = useState<"random" | "trades">("random")
  const [isAtBottom, setIsAtBottom] = useState(true)
  const [newMessages, setNewMessages] = useState(0)
  const scrollRef = useRef<HTMLDivElement>(null)
  const router = useRouter()
  const selectedRoom = channel
  const setSelectedRoom = setChannel
  const rooms = [
    { id: "random" as const, name: "Random Chat" },
    { id: "trades" as const, name: "Trade Chat" },
  ]

  useEffect(() => {
    if (authLoading) return
    if (!user) {
      router.push("/login")
    }
  }, [authLoading, user, router])

  useEffect(() => {
    fetchMessages()
  }, [channel])

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

    const sortedMessages = (data || []).sort(
      (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    )

    setMessages(sortedMessages)

    // 🔥 scroll to bottom on load
    setTimeout(() => {
      if (scrollRef.current) {
        scrollRef.current.scrollTop = scrollRef.current.scrollHeight
      }
    }, 100)
  }

  async function sendMessage() {
    if (!input.trim() && !selectedFile) return
    if (!user?.id) return

    let imageUrl = null

    if (selectedFile) {
      let uploadFile: File = selectedFile
      if (selectedFile.type?.startsWith("image/")) {
        uploadFile = await compressScreenshot(selectedFile)
      }
      const fileName = `${Date.now()}-${uploadFile.name}`

      await supabase.storage
        .from("screenshots")
        .upload(fileName, uploadFile)

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

    const sendPayload = {
      user_id: user.id,
      content: input,
      image_url: imageUrl,
      channel,
    }
    const { error: sendErr } = await supabase.from("messages").insert(sendPayload)
    if (sendErr) {
      logSupabaseError("chat sendMessage insert", sendErr, {
        table: "messages",
        query: "insert",
        payload: sendPayload,
        userId: user.id,
        channel,
      })
      showPopup({ type: "error", message: handleSupabaseError(sendErr) })
      return
    }

    setInput("")
    setSelectedFile(null)
    if (fileRef.current) fileRef.current.value = ""
    imageCrop.resetFileInput()
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

  useEffect(() => {
    const el = document.getElementById("chat-bottom")
    el?.scrollIntoView({ behavior: "smooth" })
  }, [messages])

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <ImageCropModal
        open={imageCrop.cropSourceFile != null}
        file={imageCrop.cropSourceFile}
        preset="content"
        onCancel={imageCrop.handleCropCancel}
        onSave={imageCrop.handleCropSave}
      />

      <div className="h-screen w-full flex flex-col md:flex-row overflow-hidden">
        {/* SIDEBAR (ROOM LIST) */}
        <aside className="hidden md:flex w-[250px] flex-col border-r border-white/10">
          <h2 className="mb-4 text-xl font-semibold text-blue-300">
            Trade Rooms
          </h2>
          <div className="space-y-2">
            {rooms.map((room) => (
              <button
                key={room.id}
                type="button"
                onClick={() => setChannel(room.id)}
                className={`w-full rounded px-4 py-2 text-left ${
                  channel === room.id ? "bg-emerald-500" : "bg-white/10"
                }`}
              >
                {room.name}
              </button>
            ))}
          </div>
        </aside>

        {/* CHAT AREA */}
        <div className="flex-1 flex flex-col w-full h-full">
          {/* MOBILE TOP TABS */}
          <div className="md:hidden w-full overflow-x-auto flex gap-2 px-2 py-2 border-b border-white/10">
            {rooms.map((room) => (
              <button
                key={`mobile-${room.id}`}
                onClick={() => setSelectedRoom(room.id)}
                className={`whitespace-nowrap rounded-full px-3 py-1 text-sm ${
                  selectedRoom === room.id
                    ? "bg-blue-500 text-white"
                    : "bg-[#1f2937] text-gray-300"
                }`}
              >
                {room.name}
              </button>
            ))}
          </div>

          <div className="hidden border-b border-white/10 bg-black/20 px-6 py-4 md:block">
            <h1 className="text-3xl font-semibold text-blue-300">
              Global Chat
            </h1>
          </div>

          {/* NEW MESSAGE BUTTON */}
          {newMessages > 0 && (
            <div className="absolute inset-x-0 bottom-24 z-50 flex justify-center">
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
            className="flex-1 overflow-y-auto w-full px-3 py-2"
          >
            {messages.map((msg, idx) => {
              const prev = idx > 0 ? messages[idx - 1] : null
              const showName = !prev || prev.sender_id !== msg.sender_id
              const isMe = msg.sender_id === user?.id
              return (
                <div
                  key={msg.id}
                  className={`mb-2 flex ${isMe ? "justify-end" : "justify-start"}`}
                >
                  <div className="max-w-[80%] md:max-w-[60%] rounded-xl bg-white/5 p-3 md:p-4">
                    {showName && (
                      <div className="mb-1 flex justify-between text-sm">
                        <span
                          onClick={() =>
                            router.push(
                              profilePath({
                                id: msg.profiles?.id,
                                username: msg.profiles?.username,
                              })
                            )
                          }
                          className="cursor-pointer text-emerald-400 transition hover:underline"
                        >
                          {msg.profiles?.username || "user"}
                        </span>
                        <span className="text-gray-400">
                          {formatEST(String(msg.created_at ?? ""))}
                        </span>
                      </div>
                    )}

                    {msg.content && <p className="mt-1 break-words">{msg.content}</p>}

                    {msg.image_url && (
                      <img
                        src={msg.image_url}
                        alt=""
                        loading="lazy"
                        decoding="async"
                        className="mt-3 max-h-64 rounded-lg"
                      />
                    )}

                    <div className="mt-2 flex gap-4 text-sm">
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
                </div>
              )
            })}
            <div id="chat-bottom" />
          </div>

          {/* INPUT */}
          <div className="sticky bottom-0 w-full bg-[#0B1220] border-t border-white/10 p-2">
            <div className="flex gap-2">

              <input
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="Send message..."
                className="w-full rounded bg-[#111827] px-3 py-2 text-white"
                onKeyDown={(e) => e.key === "Enter" && sendMessage()}
              />

              <input
                ref={fileRef}
                type="file"
                onChange={(e) => imageCrop.handleFileSelected(e.target.files?.[0])}
                className="text-sm"
              />

              <button
                onClick={sendMessage}
                className="rounded bg-blue-500 px-3 py-2 text-white"
              >
                Send
              </button>
            </div>

          </div>

        </div>

      </div>
    </>
  )
}