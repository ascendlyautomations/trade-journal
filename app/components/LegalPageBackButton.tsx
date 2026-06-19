"use client"

import { useRouter } from "next/navigation"

export default function LegalPageBackButton() {
  const router = useRouter()

  function handleBack() {
    if (typeof window !== "undefined" && window.history.length > 1) {
      router.back()
    } else {
      router.push("/")
    }
  }

  return (
    <button
      type="button"
      onClick={handleBack}
      className="mb-6 text-sm text-gray-400 transition hover:text-white"
    >
      ← Back
    </button>
  )
}
