'use client';

import { useEffect, useState } from 'react';
import { AlertCircle, CheckCircle, FileText, Trash2, Upload } from 'lucide-react';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';

interface PDFUploadProps {
  onUploadSuccess?: () => void;
}

export default function PDFUpload({ onUploadSuccess }: PDFUploadProps) {
  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadStatus, setUploadStatus] = useState<'idle' | 'success' | 'error'>('idle');
  const [message, setMessage] = useState('');
  const [documents, setDocuments] = useState<string[]>([]);

  const loadDocuments = async () => {
    try {
      const response = await fetch('/api/documents');
      if (response.ok) {
        const result = await response.json();
        setDocuments(result.documents ?? []);
      }
    } catch {
      // The upload form remains usable when the document list is unavailable.
    }
  };

  useEffect(() => {
    loadDocuments();
  }, []);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0] ?? null;
    const isPdf = selectedFile ? selectedFile.name.toLowerCase().endsWith('.pdf') : false;

    if (selectedFile && isPdf) {
      setFile(selectedFile);
      setUploadStatus('idle');
      setMessage('');
      return;
    }

    setFile(null);
    setUploadStatus('error');
    setMessage('Please select a valid PDF file.');
  };

  const handleUpload = async () => {
    if (!file) return;

    setUploading(true);
    setUploadStatus('idle');
    setMessage('');

    const formData = new FormData();
    formData.append('file', file);

    try {
      const response = await fetch('/api/upload', {
        method: 'POST',
        body: formData,
      });

      const result = await response.json();

      if (response.ok) {
        setUploadStatus('success');
        setMessage(
          `File uploaded successfully! ${result.filename} indexed with ${result.pages ?? 0} pages and ${result.chunks ?? 0} chunks.`
        );
        setFile(null);
        const input = document.getElementById('pdf-upload') as HTMLInputElement | null;
        if (input) input.value = '';
        onUploadSuccess?.();
        await loadDocuments();
      } else {
        setUploadStatus('error');
        setMessage(result.error || 'Upload failed');
      }
    } catch {
      setUploadStatus('error');
      setMessage('Network error. Please make sure the backend is running.');
    } finally {
      setUploading(false);
    }
  };

  const handleDelete = async (filename: string) => {
    if (!window.confirm(`Delete ${filename} and its indexed content?`)) return;

    setMessage('');
    try {
      const response = await fetch(`/api/documents/${encodeURIComponent(filename)}`, {
        method: 'DELETE',
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Delete failed');
      setUploadStatus('success');
      setMessage(`${filename} deleted from storage and search.`);
      await loadDocuments();
    } catch (error) {
      setUploadStatus('error');
      setMessage(error instanceof Error ? error.message : 'The PDF could not be deleted.');
    }
  };

  return (
    <Card className="w-full max-w-md shadow-lg border border-slate-200">
      <CardHeader className="border-b bg-slate-50/80">
        <CardTitle className="flex items-center gap-2 text-slate-900">
          <FileText className="h-5 w-5" />
          Upload PDF
        </CardTitle>
        <CardDescription>Upload a PDF to add it to the knowledge base.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4 pt-5">
        <div className="space-y-2">
          <Input id="pdf-upload" type="file" accept=".pdf" onChange={handleFileChange} className="cursor-pointer" />
          {file && <p className="text-sm text-muted-foreground">Selected: {file.name}</p>}
        </div>

        <Button onClick={handleUpload} disabled={!file || uploading} className="w-full">
          {uploading ? (
            <>
              <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2" />
              Uploading...
            </>
          ) : (
            <>
              <Upload className="h-4 w-4 mr-2" />
              Upload PDF
            </>
          )}
        </Button>

        {documents.length > 0 && (
          <div className="border-t pt-4 space-y-2">
            <p className="text-sm font-medium text-slate-700">Stored PDFs</p>
            {documents.map((document) => (
              <div key={document} className="flex items-center justify-between gap-3 text-sm">
                <span className="truncate text-slate-600">{document}</span>
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  onClick={() => handleDelete(document)}
                  title={`Delete ${document}`}
                  aria-label={`Delete ${document}`}
                >
                  <Trash2 className="h-4 w-4 text-red-600" />
                </Button>
              </div>
            ))}
          </div>
        )}

        {message && (
          <div
            className={`flex items-center gap-2 p-3 rounded-md text-sm ${
              uploadStatus === 'success' ? 'bg-green-50 text-green-700 border border-green-200' : 'bg-red-50 text-red-700 border border-red-200'
            }`}
          >
            {uploadStatus === 'success' ? <CheckCircle className="h-4 w-4" /> : <AlertCircle className="h-4 w-4" />}
            {message}
          </div>
        )}
      </CardContent>
    </Card>
  );
}