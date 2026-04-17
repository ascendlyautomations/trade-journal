"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "../components/Navbar"
import { supabase } from "../../lib/supabaseClient"

export default function FeedbackPage() {
  const router = useRouter()
  const [subject, setSubject] = useState("")
  const [message, setMessage] = useState("")
  const [image, setImage] = useState<File | null>(null)
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState("")
  const [error, setError] = useState("")

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!message.trim()) return

    setLoading(true)
    setSuccess("")
    setError("")

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser()

    if (authError || !user) {
      setLoading(false)
      router.push("/login")
      return
    }

    let screenshotUrl: string | null = null
    if (image) {
      const safeName = image.name.replace(/\s+/g, "-")
      const filePath = `feedback/${user.id}/${Date.now()}-${safeName}`
      const { error: uploadError } = await supabase.storage
        .from("screenshots")
        .upload(filePath, image, { upsert: false })

      if (uploadError) {
        setError(uploadError.message)
        setLoading(false)
        return
      }

      const { data: publicData } = supabase.storage
        .from("screenshots")
        .getPublicUrl(filePath)
      screenshotUrl = publicData.publicUrl
    }

    const { error: insertError } = await supabase.from("feedback_submissions").insert({
      user_id: user.id,
      email: user.email ?? null,
      subject: subject.trim() || null,
      message: message.trim(),
      screenshot_url: screenshotUrl,
      status: "open",
    })

    if (insertError) {
      setError(insertError.message)
      setLoading(false)
      return
    }

    setSubject("")
    setMessage("")
    setImage(null)
    setSuccess("Feedback submitted. Thank you!")
    setLoading(false)
  }

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 md:px-6 text-white">
        <div className="mx-auto w-full max-w-2xl">
          <form
            onSubmit={handleSubmit}
            className="rounded-2xl border border-white/10 bg-white/10 p-5 md:p-8 shadow-2xl backdrop-blur-xl"
          >
            <h1 className="text-center text-2xl font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
              Send feedback
            </h1>
            <p className="mt-2 mb-6 text-center text-sm text-gray-300">
              Tell us what you want changed or improved.
            </p>

            <label className="mb-2 block text-sm text-gray-300">Subject (optional)</label>
            <input
              type="text"
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
              placeholder="Short summary"
              className="mb-4 w-full rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400"
            />

            <label className="mb-2 block text-sm text-gray-300">Message</label>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="What should we change?"
              rows={6}
              className="mb-4 w-full resize-none rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400"
            />

            <label className="mb-2 block text-sm text-gray-300">Screenshot (optional)</label>
            <label className="mb-4 flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-gray-200 hover:bg-white/15">
              <span className="truncate">{image ? image.name : "Choose an image..."}</span>
              <span className="rounded bg-white text-black px-3 py-1 text-xs font-medium">
                Browse
              </span>
              <input
                type="file"
                accept="image/*"
                onChange={(e) => setImage(e.target.files?.[0] || null)}
                className="hidden"
              />
            </label>

            {error ? <p className="mb-3 text-sm text-red-300">{error}</p> : null}
            {success ? <p className="mb-3 text-sm text-emerald-300">{success}</p> : null}

            <button
              type="submit"
              disabled={loading || !message.trim()}
              className="w-full rounded-xl bg-gradient-to-r from-blue-500 to-teal-400 py-3 font-semibold transition hover:scale-[1.01] disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:scale-100"
            >
              {loading ? "Submitting..." : "Submit Feedback"}
            </button>
          </form>
        </div>
      </div>
    </>
  )
}

