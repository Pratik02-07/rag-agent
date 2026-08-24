from __future__ import annotations

import os
from pathlib import Path

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "gemma2:2b")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "nomic-embed-text")
COLLECTION_NAME = os.getenv("COLLECTION_NAME", "langchain")
CHROMA_PATH = os.getenv("CHROMA_PATH", str(Path(__file__).resolve().parent / "chroma"))
DATA_PATH = os.getenv("DATA_PATH", str(Path(__file__).resolve().parent / "data"))
MAX_UPLOAD_SIZE = int(os.getenv("MAX_UPLOAD_SIZE", "16777216"))
