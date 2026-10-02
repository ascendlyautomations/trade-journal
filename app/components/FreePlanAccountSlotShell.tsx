"use client"

/**
 * Legacy Free-plan account slot picker — retired.
 * Account limits are enforced at creation; owned accounts stay writable.
 */
export default function FreePlanAccountSlotShell({
  children,
}: {
  children: React.ReactNode
}) {
  return <>{children}</>
}
