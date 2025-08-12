import PDFUpload from '@/components/PDFUpload';
import ChatInterface from '@/components/ChatInterface';
import { useState } from 'react';

export default function Home() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 p-4">
      <div className="max-w-6xl mx-auto">
        <header className="text-center mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">
            RAG Ai Agent
          </h1>
          <p className="text-lg text-gray-600">
            Upload PDF documents and chat with your knowledge base
          </p>
        </header>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 items-start">
          <div className="flex justify-center">
            <PDFUpload />
          </div>
          
          <div className="flex justify-center">
            <ChatInterface />
          </div>
        </div>

        <footer className="text-center mt-12 text-sm text-gray-500">
          <p>
            Powered by RAG (Retrieval-Augmented Generation) technology
          </p>
        </footer>
      </div>
    </div>
  );
}
