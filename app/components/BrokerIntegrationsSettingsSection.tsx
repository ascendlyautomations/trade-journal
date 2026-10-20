"use client"

import "./brokerIntegrationsLight.css"
import TradovateIntegrationSettingsSection from "@/app/components/TradovateIntegrationSettingsSection"
import RithmicIntegrationSettingsSection from "@/app/components/RithmicIntegrationSettingsSection"

type BrokerIntegrationsSettingsSectionProps = {
  userId?: string
}

export default function BrokerIntegrationsSettingsSection({
  userId,
}: BrokerIntegrationsSettingsSectionProps) {
  return (
    <div className="tt-broker-integrations space-y-6">
      <TradovateIntegrationSettingsSection userId={userId} />
      <RithmicIntegrationSettingsSection userId={userId} />
    </div>
  )
}
