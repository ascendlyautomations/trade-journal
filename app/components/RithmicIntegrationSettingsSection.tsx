"use client"

import { useCallback, useEffect, useState } from "react"
import RithmicBrokerAccountsPanel from "@/app/components/RithmicBrokerAccountsPanel"
import RithmicUserConnectionsPanel from "@/app/components/RithmicUserConnectionsPanel"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"

export default function RithmicIntegrationSettingsSection({
  userId,
}: {
  userId?: string
}) {
  const [resolved, setResolved] = useState(false)
  const [visible, setVisible] = useState(false)
  const [testEnvironment, setTestEnvironment] = useState(false)
  const [connectionsRevision, setConnectionsRevision] = useState(0)

  const notifyConnectionsChanged = useCallback(() => {
    setConnectionsRevision((n) => n + 1)
  }, [])

  useEffect(() => {
    if (!userId) {
      setResolved(true)
      setVisible(false)
      return
    }

    void (async () => {
      try {
        const headers = await supabaseBearerHeaders()
        const [capabilitiesRes, connectionsRes] = await Promise.all([
          fetch("/api/integrations/rithmic/connect", { headers }),
          fetch("/api/integrations/rithmic/connections", { headers }),
        ])

        let shouldShow = false
        if (capabilitiesRes.ok) {
          const capabilities = (await capabilitiesRes.json()) as {
            showConnectUi?: boolean
            apiEnvironment?: string
          }
          shouldShow = capabilities.showConnectUi === true
          setTestEnvironment(capabilities.apiEnvironment === "test")
        }
        if (connectionsRes.ok) {
          const body = (await connectionsRes.json()) as {
            connections?: unknown[]
          }
          if ((body.connections?.length ?? 0) > 0) {
            shouldShow = true
          }
        }
        setVisible(shouldShow)
      } catch {
        setVisible(false)
      } finally {
        setResolved(true)
      }
    })()
  }, [userId])

  if (!resolved || !visible) {
    return null
  }

  return (
    <section className="tt-rithmic-broker space-y-6 rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
      <div>
        <h2 className="text-lg font-semibold text-white">Rithmic</h2>
        <p className="mt-1 text-sm text-gray-400">
          Connect your Rithmic login, link broker accounts, and import trades on demand.
        </p>
        {testEnvironment ? (
          <p className="tt-rithmic-test-notice mt-2 text-sm text-amber-200/85">
            Rithmic is available in the test environment only. Use test credentials until
            production access is enabled.
          </p>
        ) : null}
      </div>

      <RithmicUserConnectionsPanel
        userId={userId}
        embedded
        onConnectionsChanged={notifyConnectionsChanged}
      />
      <RithmicBrokerAccountsPanel
        userId={userId}
        embedded
        connectionsRevision={connectionsRevision}
      />
    </section>
  )
}
