import { SkeletonCommunityPage } from "@/app/components/ui/skeletons"

export default function CommunityLoading() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-white md:p-6">
      <SkeletonCommunityPage />
    </main>
  )
}
