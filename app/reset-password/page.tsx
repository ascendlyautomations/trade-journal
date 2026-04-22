"use client"

import { useState } from "react"
import { supabase } from "@/lib/supabaseClient"

export default function ResetPasswordPage() {
  const [password, setPassword] = useState("")
  const [message, setMessage] = useState("")

  const updatePassword = async () => {
    setMessage("Updating...")

    const { error } = await supabase.auth.updateUser({
      password,
    })

    if (error) {
      console.error("Update error:", error)
      setMessage("Error updating password")
    } else {
      setMessage("Password updated successfully")
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46]">
      <div className="p-6 rounded-xl bg-black/40 border border-white/10 w-full max-w-md">
        <h1 className="text-xl mb-4 text-white">Set New Password</h1>

        <input
          type="password"
          placeholder="New password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="w-full p-2 rounded bg-black/30 border border-white/10 text-white"
        />

        <button
          type="button"
          onClick={updatePassword}
          className="mt-3 w-full bg-green-500 hover:bg-green-600 text-white py-2 rounded"
        >
          Update Password
        </button>

        {message && <p className="text-sm mt-3 text-gray-300">{message}</p>}
      </div>
    </div>
  )
}
