"use client"

type Variant = "inline" | "panel"

/**
 * Compact phone-web network / load failure UI. Shown only inside `md:hidden`
 * parents or via CSS that hides at ≥768px.
 */
export default function MobileWebNetworkNotice({
  message,
  onRetry,
  retryLabel = "Retry",
  retrying = false,
  variant = "panel",
  title,
}: {
  message: string
  onRetry?: () => void
  retryLabel?: string
  retrying?: boolean
  variant?: Variant
  title?: string
}) {
  const className =
    variant === "inline"
      ? "tt-mobile-web-network-notice tt-mobile-web-network-notice--inline"
      : "tt-mobile-web-network-notice tt-mobile-web-network-notice--panel"

  return (
    <div className={className} role="alert">
      {title ? (
        <p className="tt-mobile-web-network-notice__title">{title}</p>
      ) : null}
      <p className="tt-mobile-web-network-notice__message">{message}</p>
      {onRetry ? (
        <button
          type="button"
          className="tt-mobile-web-network-notice__retry"
          onClick={onRetry}
          disabled={retrying}
          aria-busy={retrying}
        >
          {retrying ? "Retrying…" : retryLabel}
        </button>
      ) : null}
    </div>
  )
}
