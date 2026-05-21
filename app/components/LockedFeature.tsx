import Link from "next/link"
import { buttonVariants, Card, cn } from "@/app/components/ui"

type LockedFeatureProps = {
  title: string
  className?: string
}

export default function LockedFeature({ title, className = "" }: LockedFeatureProps) {
  return (
    <Card
      variant="solid"
      padding="lg"
      className={cn(
        "flex min-h-[220px] h-full w-full flex-col items-center justify-center bg-[#0b1f3a] text-center",
        className
      )}
    >
      <h3 className="mb-2 text-lg font-semibold text-white">🔒 {title}</h3>
      <p className="mb-4 max-w-sm text-sm text-gray-400">
        Upgrade to Pro to unlock this feature
      </p>
      <Link
        href="/pricing"
        className={buttonVariants({ variant: "primary", size: "md" })}
      >
        Upgrade to Pro
      </Link>
    </Card>
  )
}
