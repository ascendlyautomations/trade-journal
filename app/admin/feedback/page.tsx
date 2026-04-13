"use client"

import { useEffect, useState } from "react"

export default function AdminPage() {
  const [status, setStatus] = useState("Page loaded")

  useEffect(() => {
    try {
      console.log("ADMIN PAGE MOUNTED")
      setStatus("Admin page is rendering correctly")
    } catch (err) {
      console.error(err)
      setStatus("ERROR OCCURRED")
    }
  }, [])

  return (
    <div style={{ padding: "20px", color: "white" }}>
      <h1>ADMIN DEBUG</h1>
      <p>{status}</p>
    </div>
  )
}
