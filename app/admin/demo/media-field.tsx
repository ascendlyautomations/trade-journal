"use client"

import { useState } from "react"
import { uploadDemoMedia } from "@/lib/demo/demoAdminClient"
import { resolvedMime, validateDemoMediaFile, type DemoMediaEntityType, type DemoMediaKind } from "@/lib/demo/demoMedia"

export function DemoMediaField({
  label,
  url,
  entityType,
  entityId,
  kind,
  onChange,
}: {
  label: string
  url: string
  entityType: DemoMediaEntityType
  entityId: string
  kind: DemoMediaKind | "either"
  onChange: (url: string, mediaKind: DemoMediaKind) => void
}) {
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const previewKind = url.match(/\.mp4|\.mov|\.webm|video/i) ? "video" : "image"

  async function onFile(file: File | null) {
    if (!file) return
    setError(null)
    const chosenKind: DemoMediaKind =
      kind === "either" ? (file.type.startsWith("video/") ? "video" : "image") : kind
    const bytes = new Uint8Array(await file.arrayBuffer())
    const problem = validateDemoMediaFile(
      { name: file.name, type: file.type || resolvedMime({ name: file.name, type: file.type }) || "", size: file.size, bytes },
      { entityType, kind: chosenKind }
    )
    if (problem) {
      setError(problem)
      return
    }
    setBusy(true)
    try {
      const uploaded = await uploadDemoMedia({ file, entityType, entityId, kind: chosenKind })
      onChange(uploaded.url, chosenKind)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Upload failed. The current Demo media was left unchanged.")
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-2">
      <p className="text-xs text-gray-400">{label}</p>
      {url && previewKind === "image" ? (
        <img src={url} alt="" className="h-28 w-28 rounded-lg object-cover" />
      ) : null}
      {url && previewKind === "video" ? (
        <video src={url} className="h-28 w-40 rounded-lg bg-black" muted preload="metadata" />
      ) : null}
      {!url ? <p className="text-xs text-gray-500">No media</p> : null}
      <div className="flex flex-wrap gap-2">
        <label className="cursor-pointer rounded-lg border border-white/15 px-3 py-1.5 text-sm">
          {busy ? "Uploading…" : url ? "Replace" : "Upload"}
          <input
            className="hidden"
            type="file"
            accept={kind === "video" ? "video/mp4,video/quicktime,video/webm" : kind === "image" ? "image/jpeg,image/png,image/webp,image/gif" : "image/jpeg,image/png,image/webp,image/gif,video/mp4,video/quicktime,video/webm"}
            disabled={busy || !entityId}
            onChange={(event) => {
              const file = event.target.files?.[0] ?? null
              event.target.value = ""
              void onFile(file)
            }}
          />
        </label>
        {url ? (
          <button type="button" className="rounded-lg border border-white/15 px-3 py-1.5 text-sm" onClick={() => onChange("", previewKind)}>
            Remove
          </button>
        ) : null}
      </div>
      {error ? <p className="text-xs text-red-200">{error}</p> : null}
    </div>
  )
}
