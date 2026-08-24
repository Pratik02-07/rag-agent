from __future__ import annotations

import logging
from typing import Any

from flask import Flask, jsonify, request
from flask_cors import CORS
from ollama import Client

from config import CHROMA_PATH, DATA_PATH, EMBEDDING_MODEL, OLLAMA_BASE_URL, OLLAMA_MODEL
from generation import generate_answer
from ingestion import delete_pdf_file, ingest_pdf_file, ensure_storage_paths, list_uploaded_files
from retrieval import NoRelevantDocumentsError, retrieve_documents

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024 * 1024
ensure_storage_paths()


def check_ollama_health() -> bool:
    try:
        client = Client(host=OLLAMA_BASE_URL)
        models = client.list().get("models", [])
        available_models = {model.get("name") for model in models}
        required_models = {OLLAMA_MODEL, EMBEDDING_MODEL}
        missing_models = {
            model
            for model in required_models
            if model not in available_models
            and (":" in model or f"{model}:latest" not in available_models)
        }
        if missing_models:
            logger.error("Ollama models are missing: %s", ", ".join(sorted(missing_models)))
            return False
        return True
    except Exception:
        logger.exception("Ollama health check failed")
        return False


def check_chroma_health() -> bool:
    try:
        from langchain_chroma import Chroma
        from embeddings_function import get_embedding_function

        db = Chroma(
            collection_name="langchain",
            persist_directory=CHROMA_PATH,
            embedding_function=get_embedding_function(),
        )
        db.get(include=[])
        return True
    except Exception:
        logger.exception("Chroma health check failed")
        return False


@app.errorhandler(413)
def request_too_large(_error):
    return jsonify({"error": "File too large. Maximum upload size is 16MB."}), 413


@app.errorhandler(404)
def not_found(_error):
    return jsonify({"error": "Resource not found."}), 404


@app.route("/", methods=["GET"])
def root():
    return jsonify(
        {
            "message": "RAG Backend API",
            "endpoints": {
                "/api/health": "Health check",
                "/api/query": "Ask a question about uploaded PDFs",
                "/api/upload": "Upload a PDF to the knowledge base",
                "/api/documents": "List or delete uploaded PDFs",
            },
        }
    ), 200


@app.route("/api/health", methods=["GET"])
def health_check():
    ollama_ok = check_ollama_health()
    database_ok = check_chroma_health()
    status = "ok" if ollama_ok and database_ok else "degraded"
    code = 200 if status == "ok" else 503
    return jsonify({"status": status, "ollama": ollama_ok, "database": database_ok}), code


@app.route("/health", methods=["GET"])
def legacy_health_check():
    return health_check()


@app.route("/api/query", methods=["POST"])
def query_documents():
    payload = request.get_json(silent=True) or {}
    question = (payload.get("question") or "").strip()

    if not question:
        return jsonify({"error": "Question is required."}), 400

    try:
        documents = retrieve_documents(question, k=4)
        if not documents:
            return jsonify({
                "answer": "The information is not available in the uploaded documents.",
                "sources": [],
            }), 200

        answer = generate_answer(question, [doc for doc, _ in documents])
        sources = [
            {
                "file": doc.metadata.get("source", "unknown.pdf"),
                "page": int(doc.metadata.get("page", 1)),
            }
            for doc, _ in documents
        ]
        return jsonify({"answer": answer, "sources": sources}), 200
    except NoRelevantDocumentsError:
        return jsonify({
            "answer": "The information is not available in the uploaded documents.",
            "sources": [],
        }), 200
    except Exception:
        logger.exception("Query failed")
        return jsonify({"error": "Unable to answer the question right now. Check that Ollama is running and its models are available."}), 500


@app.route("/api/upload", methods=["POST"])
def upload_file():
    if "file" not in request.files:
        return jsonify({"error": "No file provided."}), 400

    uploaded_file = request.files["file"]
    if uploaded_file.filename == "":
        return jsonify({"error": "No file selected."}), 400

    if not uploaded_file.filename.lower().endswith(".pdf"):
        return jsonify({"error": "Only PDF files are allowed."}), 400

    try:
        result = ingest_pdf_file(uploaded_file)
        return jsonify(result), 200
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    except Exception:
        logger.exception("PDF upload and indexing failed")
        return jsonify({"error": "The PDF could not be processed."}), 500


@app.route("/api/documents", methods=["GET"])
def list_documents():
    return jsonify({"documents": list_uploaded_files()}), 200


@app.route("/api/documents/<path:filename>", methods=["DELETE"])
def delete_document(filename: str):
    try:
        deleted_chunks = delete_pdf_file(filename)
        return jsonify({
            "message": "PDF deleted successfully",
            "filename": filename,
            "deleted_chunks": deleted_chunks,
        }), 200
    except FileNotFoundError:
        return jsonify({"error": "PDF not found."}), 404
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    except Exception:
        logger.exception("PDF deletion failed")
        return jsonify({"error": "The PDF could not be deleted."}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)