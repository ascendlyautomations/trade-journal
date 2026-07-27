import { redirect } from "next/navigation"

type PageProps = {
  params: Promise<{ id: string }>
  searchParams?: Promise<Record<string, string | string[] | undefined>>
}

function appendSearch(
  base: URLSearchParams,
  searchParams: Record<string, string | string[] | undefined> | undefined
) {
  if (!searchParams) return
  for (const [key, value] of Object.entries(searchParams)) {
    if (value == null) continue
    if (Array.isArray(value)) {
      for (const v of value) base.append(key, v)
    } else {
      base.set(key, value)
    }
  }
}

/** Short share URL → Trade Room in community. */
export default async function RoomUniversalRedirect({
  params,
  searchParams,
}: PageProps) {
  const { id } = await params
  const resolved = searchParams ? await searchParams : undefined
  const q = new URLSearchParams()
  q.set("room", id)
  appendSearch(q, resolved)
  redirect(`/community?${q.toString()}`)
}
