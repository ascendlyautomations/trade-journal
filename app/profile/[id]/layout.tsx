import type { Metadata } from "next"
import type { ReactNode } from "react"
import {
  buildProfileMetadata,
  fetchProfileForSeo,
} from "@/lib/publicSeo"

type ProfileLayoutProps = {
  children: ReactNode
  params: Promise<{ id: string }>
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>
}): Promise<Metadata> {
  const { id } = await params
  const profile = await fetchProfileForSeo(id)
  return buildProfileMetadata(profile)
}

export default function ProfileLayout({ children }: ProfileLayoutProps) {
  return children
}
