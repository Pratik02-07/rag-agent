from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import tempfile
from werkzeug.utils import secure_filename
from populate_DB import load_documents, split_documents, add_to_chroma
from query_DB import query_rag
from langchain_community.document_loaders import PyPDFLoader
from langchain.schema.document import Document
import shutil

app = Flask(__name__)
CORS(app)

UPLOAD_FOLDER = 'data'
ALLOWED_EXTENSIONS = {'pdf'}

# Ensure upload folder exists
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

@app.route('/upload', methods=['POST'])
def upload_file():
    try:
        if 'file' not in request.files:
            return jsonify({'error': 'No file part'}), 400
        
        file = request.files['file']
        
        if file.filename == '':
            return jsonify({'error': 'No selected file'}), 400
        
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            filepath = os.path.join(UPLOAD_FOLDER, filename)
            file.save(filepath)
            
            # Process the uploaded PDF
            try:
                # Load and split the document
                loader = PyPDFLoader(filepath)
                documents = loader.load()
                
                from populate_DB import split_documents, add_to_chroma
                chunks = split_documents(documents)
                add_to_chroma(chunks)
                
                return jsonify({
                    'message': 'File uploaded and processed successfully',
                    'filename': filename,
                    'chunks_added': len(chunks)
                }), 200
                
            except Exception as e:
                return jsonify({'error': f'Error processing PDF: {str(e)}'}), 500
        
        return jsonify({'error': 'Invalid file type. Only PDF files are allowed.'}), 400
        
    except Exception as e:
        return jsonify({'error': f'Upload failed: {str(e)}'}), 500

@app.route('/chat', methods=['POST'])
def chat():
    try:
        data = request.get_json()
        
        if not data or 'message' not in data:
            return jsonify({'error': 'No message provided'}), 400
        
        query_text = data['message']
        
        # Query the RAG system
        response = query_rag(query_text)
        
        return jsonify({
            'response': response,
            'query': query_text
        }), 200
        
    except Exception as e:
        return jsonify({'error': f'Chat failed: {str(e)}'}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'}), 200

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)