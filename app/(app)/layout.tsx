import Navbar from "../components/Navbar"

export default function AppShellLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="w-full px-2 pb-6 pt-3 text-white md:px-4 md:pb-10">
          {children}
        </div>
      </div>
    </>
  )
}
