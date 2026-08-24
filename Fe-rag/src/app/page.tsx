import PDFUpload from "@/components/PDFUpload";
import ChatInterface from "@/components/ChatInterface";

export default function Home() {
  return (
    <main className="min-h-screen bg-[#f5f7fb] text-slate-950">
      <div className="mx-auto flex min-h-screen w-full max-w-[1440px] flex-col px-4 py-5 sm:px-6 lg:px-10">
        <header className="mb-8 flex flex-col gap-5 border-b border-slate-200 pb-6 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.22em] text-rose-600">Private document workspace</p>
            <h1 className="text-3xl font-semibold tracking-tight text-slate-950 sm:text-4xl">RAG AI Agent</h1>
            <p className="mt-2 max-w-xl text-sm leading-6 text-slate-500 sm:text-base">
              Upload your PDFs, then ask grounded questions with page-level sources.
            </p>
          </div>
          <div className="flex items-center gap-2 text-sm text-slate-500">
            <span className="h-2 w-2 rounded-full bg-emerald-500" />
            Local knowledge base
          </div>
        </header>

        <div className="grid flex-1 grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(260px,340px)_minmax(0,1fr)] lg:gap-8">
          <aside className="space-y-4">
            <PDFUpload />
            <div className="hidden rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-500 shadow-sm lg:block">
              <p className="font-medium text-slate-800">How it works</p>
              <p className="mt-2 leading-6">Documents are indexed locally. Answers are generated only from the retrieved PDF context.</p>
            </div>
          </aside>

          <section className="min-w-0">
            <ChatInterface />
          </section>
        </div>

        <footer className="py-6 text-xs text-slate-400">Powered by local retrieval-augmented generation</footer>
      </div>
    </main>
  );
}
