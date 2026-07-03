"use client"

import { useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { useToast } from "@/app/components/ui"

export default function SuggestionsPage() {
  const toast = useToast()
  const [note, setNote] = useState("")
  const [image, setImage] = useState<File | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!note.trim() || !image) return

    setLoading(true)

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      toast.error("Please log in first.")
      setLoading(false)
      return
    }

    let uploadFile: File = image
    if (image.type?.startsWith("image/")) {
      uploadFile = await compressImage(image)
    }
    const fileName = `${user.id}-${Date.now()}-${uploadFile.name}`

    const { error: uploadError } = await supabase.storage
      .from("suggestions")
      .upload(fileName, uploadFile)

    if (uploadError) {
      toast.error(uploadError.message)
      setLoading(false)
      return
    }

    const { data: publicUrl } = supabase.storage
      .from("suggestions")
      .getPublicUrl(fileName)

    const { error: insertError } = await supabase.from("suggestions").insert({
      user_id: user.id,
      note: note.trim(),
      image_url: publicUrl.publicUrl,
    })

    if (insertError) {
      toast.error(insertError.message)
      setLoading(false)
      return
    }

    setNote("")
    setImage(null)
    toast.success("Feedback submitted")
    setLoading(false)
  }

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-6 py-10 text-white">
        <div className="mx-auto w-full max-w-xl">
          <form
            onSubmit={handleSubmit}
            className="rounded-2xl border border-white/10 bg-white/10 p-8 shadow-2xl backdrop-blur-xl"
          >
            <h1 className="mb-6 text-center text-2xl font-semibold">
              Submit Feedback
            </h1>

            <label className="mb-2 block text-sm text-gray-300">
              Screenshot
            </label>
            <input
              type="file"
              accept="image/*"
              onChange={(e) => setImage(e.target.files?.[0] || null)}
              className="mb-4 w-full rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-white file:mr-3 file:rounded-lg file:border-0 file:bg-white file:px-3 file:py-2 file:text-black"
            />

            <label className="mb-2 block text-sm text-gray-300">
              Feedback Is Greatly Appreciated
            </label>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Tell us what to improve..."
              rows={5}
              className="mb-6 w-full resize-none rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400"
            />

            <button
              type="submit"
              disabled={loading || !note.trim() || !image}
              className="w-full rounded-xl bg-gradient-to-r from-blue-500 to-teal-400 py-3 font-semibold transition hover:scale-[1.02] disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:scale-100"
            >
              {loading ? "Submitting..." : "Submit"}
            </button>
          </form>
        </div>
      </div>
    </>
  )
}
