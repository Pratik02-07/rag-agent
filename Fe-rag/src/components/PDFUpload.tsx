'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Upload, FileText, CheckCircle, AlertCircle } from 'lucide-react';

interface PDFUploadProps {
  onUploadSuccess?: () => void;
}

export default function PDFUpload({ onUploadSuccess }: PDFUploadProps) {
  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadStatus, setUploadStatus] = useState<'idle' | 'success' | 'error'>('idle');
  const [message, setMessage] = useState('');

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0];
    if (selectedFile && selectedFile.type === 'application/pdf') {
      setFile(selectedFile);
      setUploadStatus('idle');
      setMessage('');
    } else {
      setFile(null);
      setUploadStatus('error');
      setMessage('Please select a valid PDF file.');
    }
  };

  const handleUpload = async () => {
    if (!file) return;

    setUploading(true);
    setUploadStatus('idle');
    setMessage('');

    const formData = new FormData();
    formData.append('file', file);

    try {
      const response = await fetch('http://localhost:5000/upload', {
        method: 'POST',
        body: formData,
      });

      const result = await response.json();

      if (response.ok) {
        setUploadStatus('success');
        setMessage(`File uploaded successfully! ${result.chunks_added} chunks added to the database.`);
        setFile(null);
        // Reset the input
        const input = document.getElementById('pdf-upload') as HTMLInputElement;
        if (input) input.value = '';
        
        onUploadSuccess?.();
      } else {
        setUploadStatus('error');
        setMessage(result.error || 'Upload failed');
      }
    } catch (error) {
      setUploadStatus('error');
      setMessage('Network error. Please make sure the backend server is running.');
    } finally {
      setUploading(false);
    }
  };

  return (
    <Card className="w-full max-w-md">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <FileText className="h-5 w-5" />
          Upload PDF
        </CardTitle>
        <CardDescription>
          Upload a PDF document to add it to the knowledge base
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <Input
            id="pdf-upload"
            type="file"
            accept=".pdf"
            onChange={handleFileChange}
            className="cursor-pointer"
          />
          {file && (
            <p className="text-sm text-muted-foreground">
              Selected: {file.name}
            </p>
          )}
        </div>

        <Button
          onClick={handleUpload}
          disabled={!file || uploading}
          className="w-full"
        >
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

        {message && (
          <div className={`flex items-center gap-2 p-3 rounded-md text-sm ${
            uploadStatus === 'success' 
              ? 'bg-green-50 text-green-700 border border-green-200' 
              : 'bg-red-50 text-red-700 border border-red-200'
          }`}>
            {uploadStatus === 'success' ? (
              <CheckCircle className="h-4 w-4" />
            ) : (
              <AlertCircle className="h-4 w-4" />
            )}
            {message}
          </div>
        )}
      </CardContent>
    </Card>
  );
}