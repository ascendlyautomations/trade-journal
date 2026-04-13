"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "../../components/Navbar"
import { supabase } from "../../../lib/supabaseClient"

const ADMIN_ID = "PASTE_YOUR_SUPABASE_USER_ID_HERE"

type SuggestionRow = {
  id: string
  note: string
  image_url: string | null
  created_at: string
}

export default function AdminFeedbackPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(true)
  const [feedback, setFeedback] = useState<SuggestionRow[]>([])

  useEffect(() => {
    async function init() {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user || user.id !== ADMIN_ID) {
        router.replace("/dashboard")
        return
      }

      const { data } = await supabase
        .from("suggestions")
        .select("*")
        .order("created_at", { ascending: false })

      setFeedback((data as SuggestionRow[]) || [])
      setLoading(false)
    }

    void init()
  }, [router])

  async function handleDelete(id: string) {
    await supabase.from("suggestions").delete().eq("id", id)
    setFeedback((prev) => prev.filter((item) => item.id !== id))
  }

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-6 py-10 text-white">
        <div className="mx-auto w-full max-w-3xl">
          <h1 className="mb-6 text-2xl font-semibold">Admin Feedback</h1>

          {loading ? (
            <p className="text-sm text-gray-300">Loading feedback...</p>
          ) : feedback.length === 0 ? (
            <p className="text-sm text-gray-300">No feedback yet.</p>
          ) : (
            feedback.map((item) => (
              <div
                key={item.id}
                className="mb-4 rounded-xl border border-white/10 bg-white/5 p-4"
              >
                <p className="mb-2 text-white">{item.note}</p>

                {item.image_url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={item.image_url}
                    alt="Feedback screenshot"
                    className="max-h-[300px] w-full rounded-lg object-cover"
                  />
                ) : null}

                <p className="mt-2 text-xs text-gray-400">
                  {new Date(item.created_at).toLocaleString()}
                </p>

                <button
                  type="button"
                  onClick={() => void handleDelete(item.id)}
                  className="mt-2 text-xs text-red-400"
                >
                  Delete
                </button>
              </div>
            ))
          )}
        </div>
      </div>
    </>
  )
}
