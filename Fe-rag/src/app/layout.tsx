import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "RAG AI Agent",
  description: "Upload PDF documents and chat with your knowledge base using RAG technology",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
