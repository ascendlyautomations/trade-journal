"use client"

import { AFFILIATE_PRIMARY_BUTTON_CLASS } from "@/lib/affiliateUi"
import { useAffiliateProgramApply } from "@/app/components/marketing/AffiliateProgramApplyContext"
import { useUserProfile } from "@/lib/useUserProfile"

export default function AffiliateProgramHeroApplyButton() {
  const { user, loading: authLoading } = useUserProfile()
  const { scrollToApplication } = useAffiliateProgramApply()

  if (!user?.id) return null

  return (
    <div className="mt-6 flex justify-center">
      <button
        type="button"
        onClick={scrollToApplication}
        disabled={authLoading}
        className={`${AFFILIATE_PRIMARY_BUTTON_CLASS} inline-flex min-w-[200px] items-center justify-center px-8 py-3.5 text-base disabled:cursor-not-allowed disabled:opacity-60`}
      >
        Apply Now
      </button>
    </div>
  )
}
