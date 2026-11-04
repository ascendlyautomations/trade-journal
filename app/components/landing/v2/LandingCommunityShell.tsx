import type { ReactNode } from "react"

/** Visual wrapper for live featured trades + weekly leaderboard sections. */
export default function LandingCommunityShell({ children }: { children: ReactNode }) {
  return (
    <div id="community" className="tt-community-band scroll-mt-24">
      <div className="tt-section-inner tt-community-intro">
        <p className="tt-section-eyebrow">Live community</p>
        <h2 className="tt-section-title">Proof from traders on the platform</h2>
        <p className="tt-section-lede tt-section-lede--center">
          Featured trades and leaderboard picks come from public activity on TradeTraxs. We
          widen the window (week → month → year) when needed so top P&L and top R:R
          highlight different traders.
        </p>
      </div>
      <div className="tt-community-sections">{children}</div>
    </div>
  )
}
