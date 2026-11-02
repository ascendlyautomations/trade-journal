import { SkeletonCommunityPage } from "@/app/components/ui/skeletons"
import { MOBILE_WEB_NEUTRAL_PAGE_BG } from "@/lib/mobileWebPageSurface"

export default function CommunityLoading() {
  return (
    <main className={`tt-community min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-white md:p-6 ${MOBILE_WEB_NEUTRAL_PAGE_BG}`}>
      <SkeletonCommunityPage />
    </main>
  )
}
