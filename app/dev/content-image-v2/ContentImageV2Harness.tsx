"use client"

import { useState } from "react"
import ImageCropModal from "@/app/components/ImageCropModal"

type Result = {
  name: string
  type: string
  bytes: number
  width: number
  height: number
}

/** Local-only preview of Content Image V2. Does not upload. */
export default function ContentImageV2Harness() {
  const [file, setFile] = useState<File | null>(null)
  const [open, setOpen] = useState(false)
  const [result, setResult] = useState<Result | null>(null)

  return (
    <main className="mx-auto flex min-h-screen max-w-lg flex-col gap-4 bg-[#0b1220] p-6 text-white">
      <h1 className="text-lg font-semibold">Content image V2 harness</h1>
      <p className="text-sm text-gray-400">
        Development only. This does not upload and does not change Add Trade, posts, or
        achievements.
      </p>
      <input
        type="file"
        accept="image/*"
        onChange={(event) => {
          const next = event.target.files?.[0] ?? null
          setResult(null)
          setFile(next)
          setOpen(Boolean(next))
        }}
      />
      {result ? (
        <dl className="grid grid-cols-[8rem_1fr] gap-y-1 text-sm">
          <dt className="text-gray-400">File</dt>
          <dd>{result.name}</dd>
          <dt className="text-gray-400">MIME</dt>
          <dd>{result.type}</dd>
          <dt className="text-gray-400">Bytes</dt>
          <dd>{result.bytes.toLocaleString()}</dd>
          <dt className="text-gray-400">Dimensions</dt>
          <dd>
            {result.width}×{result.height}
          </dd>
        </dl>
      ) : null}
      <ImageCropModal
        open={open}
        file={file}
        preset="contentV2"
        onCancel={() => {
          setOpen(false)
          setFile(null)
        }}
        onSave={(cropped) => {
          const url = URL.createObjectURL(cropped)
          const image = new Image()
          image.onload = () => {
            setResult({
              name: cropped.name,
              type: cropped.type,
              bytes: cropped.size,
              width: image.naturalWidth,
              height: image.naturalHeight,
            })
            URL.revokeObjectURL(url)
          }
          image.onerror = () => {
            URL.revokeObjectURL(url)
          }
          image.src = url
          setOpen(false)
          setFile(null)
        }}
      />
    </main>
  )
}
