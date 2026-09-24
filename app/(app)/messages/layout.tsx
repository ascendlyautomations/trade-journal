import type { ReactNode } from "react"
import MessagesShell from "./MessagesShell"

export default function MessagesLayout({ children }: { children: ReactNode }) {
  return <MessagesShell>{children}</MessagesShell>
}
