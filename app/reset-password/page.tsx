"use client"

import { useRef, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import AuthPasswordInput from "@/app/components/ui/AuthPasswordInput"

export default function ResetPasswordPage() {
  const [password, setPassword] = useState("")
  const [message, setMessage] = useState("")
  const [isSubmitting, setIsSubmitting] = useState(false)
  const submittingRef = useRef(false)

  const updatePassword = async () => {
    if (submittingRef.current || isSubmitting || !password.trim()) return

    submittingRef.current = true
    setIsSubmitting(true)
    setMessage("Updating...")

    try {
      const { error } = await supabase.auth.updateUser({
        password,
      })

      if (error) {
        console.error("Update error:", error)
        setMessage("Error updating password")
      } else {
        setMessage("Password updated successfully")
      }
    } finally {
      submittingRef.current = false
      setIsSubmitting(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46]">
      <div className="w-full max-w-md rounded-xl border border-white/10 bg-black/40 p-6">
        <h1 className="mb-4 text-xl text-white">Set New Password</h1>

        <AuthPasswordInput
          placeholder="New password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="w-full rounded border border-white/10 bg-black/30 p-2"
        />

        <button
          type="button"
          onClick={() => void updatePassword()}
          disabled={isSubmitting || !password.trim()}
          className="mt-3 w-full rounded bg-green-500 py-2 text-white hover:bg-green-600 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {isSubmitting ? "Updating…" : "Update Password"}
        </button>

        {message ? <p className="mt-3 text-sm text-gray-300">{message}</p> : null}
      </div>
    </div>
  )
}
