import { SkeletonExplorePage } from "@/app/components/ui/skeletons"

export default function ExploreLoading() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-3 py-6 text-white sm:px-4 md:px-8">
      <div className="mx-auto w-full max-w-7xl">
        <SkeletonExplorePage />
      </div>
    </main>
  )
}
