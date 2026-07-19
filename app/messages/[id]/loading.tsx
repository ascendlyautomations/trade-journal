import { SkeletonMessagesPage } from "@/app/components/ui/skeletons"

export default function MessageDetailLoading() {
  return (
    <main className="min-h-screen w-full px-4 py-6 text-white md:px-8">
      <SkeletonMessagesPage />
    </main>
  )
}
