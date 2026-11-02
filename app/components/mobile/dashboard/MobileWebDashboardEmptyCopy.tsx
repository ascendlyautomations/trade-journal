import { mwDashText } from "./mobileWebDashboardChrome"

export default function MobileWebDashboardEmptyCopy({
  title,
  body,
}: {
  title?: string
  body: string
}) {
  return (
    <div className="py-1.5">
      {title ? (
        <p className={`text-[13px] font-semibold leading-snug ${mwDashText.primary}`}>
          {title}
        </p>
      ) : null}
      <p
        className={`${title ? "mt-1" : ""} text-[13px] leading-snug ${mwDashText.muted}`}
      >
        {body}
      </p>
    </div>
  )
}
