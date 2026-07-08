"use client"

import { useEffect, useState } from "react"
import { createReelVideoPreviewObjectUrl } from "@/lib/reelVideo"

type ReelVideoFilePreviewProps = {
  file: File
  className?: string
  containerClassName?: string
}

export default function ReelVideoFilePreview({
  file,
  className = "aspect-[9/16] w-full object-cover",
  containerClassName = "mx-auto w-full max-w-[220px] overflow-hidden rounded-xl border border-white/10 bg-black/40 shadow-lg shadow-black/40",
}: ReelVideoFilePreviewProps) {
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    let objectUrl: string | null = null

    setLoading(true)
    setPreviewUrl(null)

    void createReelVideoPreviewObjectUrl(file)
      .then((result) => {
        if (cancelled) {
          URL.revokeObjectURL(result.previewUrl)
          return
        }
        objectUrl = result.previewUrl
        setPreviewUrl(result.previewUrl)
        setLoading(false)
      })
      .catch(() => {
        if (!cancelled) setLoading(false)
      })

    return () => {
      cancelled = true
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [file])

  return (
    <div className={containerClassName}>
      {previewUrl ? (
        <img
          src={previewUrl}
          alt=""
          draggable={false}
          className={className}
        />
      ) : (
        <div
          className={`${className} ${
            loading ? "animate-pulse bg-gradient-to-br from-white/10 to-black/40" : "bg-black/60"
          }`}
          aria-hidden
        />
      )}
    </div>
  )
}
