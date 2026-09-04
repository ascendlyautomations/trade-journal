import Link from "next/link"

type Props = {
  params: Promise<{ id: string }>
}

/** Minimal public fallback when the native app is not installed. */
export default async function StorySharePage({ params }: Props) {
  const { id } = await params
  const storyURL = `https://www.tradetraxs.com/story/${encodeURIComponent(id)}`

  return (
    <main className="mx-auto flex min-h-[60vh] max-w-lg flex-col items-center justify-center gap-4 px-6 py-16 text-center">
      <h1 className="text-2xl font-semibold">View this story on TradeTraxs</h1>
      <p className="text-muted-foreground">
        Open the link in the TradeTraxs app to watch this story while it is still active.
      </p>
      <div className="flex flex-wrap items-center justify-center gap-3">
        <Link
          href="/feed"
          className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
        >
          Go to Feed
        </Link>
        <a href={storyURL} className="text-sm font-medium underline">
          Copy story link
        </a>
      </div>
    </main>
  )
}
