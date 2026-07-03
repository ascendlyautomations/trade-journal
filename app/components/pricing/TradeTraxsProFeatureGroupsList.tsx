"use client"

import type { ReactNode } from "react"
import {
  TRADETRAXS_PRO_FEATURE_GROUPS,
  type TradeTraxsPlanFeatureGroup,
} from "@/lib/tradeTraxsPlans"

type TradeTraxsProFeatureGroupsListProps = {
  groupHeadingClassName: string
  listClassName: string
  itemClassName: string
  renderCheck: (options?: { bright?: boolean }) => ReactNode
  groups?: readonly TradeTraxsPlanFeatureGroup[]
}

export default function TradeTraxsProFeatureGroupsList({
  groupHeadingClassName,
  listClassName,
  itemClassName,
  renderCheck,
  groups = TRADETRAXS_PRO_FEATURE_GROUPS,
}: TradeTraxsProFeatureGroupsListProps) {
  return (
    <>
      {groups.map((group) => (
        <div key={group.heading}>
          <p className={groupHeadingClassName}>{group.heading}</p>
          {group.features.length > 0 ? (
            <ul className={listClassName}>
              {group.features.map((feature) => (
                <li key={feature} className={itemClassName}>
                  {renderCheck({ bright: true })}
                  <span>{feature}</span>
                </li>
              ))}
            </ul>
          ) : (
            <ul className={listClassName}>
              <li className={itemClassName}>
                {renderCheck({ bright: true })}
                <span>All Free plan features included</span>
              </li>
            </ul>
          )}
        </div>
      ))}
    </>
  )
}
