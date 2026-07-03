"use client"

import CsvImportPanel from "../components/CsvImportPanel"

export default function ImportPage() {
  return (
    <>
      <div className="min-h-screen bg-[#0f172a] p-6 text-white">
        <div className="mx-auto max-w-4xl">
          <h1 className="mb-4 text-2xl">Import Trades</h1>
          <CsvImportPanel />
        </div>
      </div>
    </>
  )
}
