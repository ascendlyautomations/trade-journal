"use client"

type VaultHexagonIconProps = {
  filled?: boolean
  className?: string
}

/** SF Symbol–style hexagon for Vault affordance. */
export default function VaultHexagonIcon({
  filled = false,
  className = "h-4 w-4",
}: VaultHexagonIconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={className}
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth={filled ? 0 : 1.75}
      aria-hidden
    >
      <path
        strokeLinejoin="round"
        d="M12 2.5 19.5 7v10L12 21.5 4.5 17V7L12 2.5z"
      />
    </svg>
  )
}
