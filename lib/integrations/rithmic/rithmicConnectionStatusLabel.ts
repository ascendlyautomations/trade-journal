export function formatRithmicConnectionStatusLabel(status: string): string {
  switch (status) {
    case "connected":
      return "Connected"
    case "reconnect_required":
      return "Reconnect Required"
    case "disconnected":
      return "Disconnected"
    case "error":
      return "Error"
    default:
      return status.replace(/_/g, " ")
  }
}
