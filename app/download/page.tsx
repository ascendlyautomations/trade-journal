import Image from "next/image"
import LandingAppStoreButton from "@/app/components/landing/v2/LandingAppStoreButton"
import {
  DOWNLOAD_PAGE_TITLE,
  IOS_APP_STORE_DOWNLOAD_URL,
} from "@/lib/downloadPageMetadata"

export default function DownloadPage() {
  return (
    <main className="flex min-h-[100dvh] flex-col items-center justify-center bg-[#0b1f3a] px-6 py-12 text-center">
      <Image
        src="/ios-app-icon.png"
        alt=""
        width={120}
        height={120}
        priority
        className="h-[120px] w-[120px] rounded-[26px] shadow-lg shadow-black/30"
        sizes="120px"
      />
      <h1 className="mt-6 text-2xl font-semibold tracking-tight text-white sm:text-3xl">
        {DOWNLOAD_PAGE_TITLE}
      </h1>
      <p className="mt-8">
        <LandingAppStoreButton
          surface="final_cta"
          href={IOS_APP_STORE_DOWNLOAD_URL}
        />
      </p>
    </main>
  )
}