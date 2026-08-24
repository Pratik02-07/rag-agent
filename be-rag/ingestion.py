from __future__ import annotations

import logging
import shutil
from pathlib import Path

from langchain_chroma import Chroma
from langchain_community.document_loaders import PyPDFDirectoryLoader, PyPDFLoader
from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter
from werkzeug.datastructures import FileStorage
from werkzeug.utils import secure_filename

from config import CHROMA_PATH, COLLECTION_NAME, DATA_PATH
from embeddings_function import get_embedding_function

logger = logging.getLogger(__name__)


def ensure_storage_paths() -> None:
    Path(CHROMA_PATH).mkdir(parents=True, exist_ok=True)
    Path(DATA_PATH).mkdir(parents=True, exist_ok=True)


def load_documents_from_directory(directory: str = DATA_PATH) -> list[Document]:
    directory_path = Path(directory)
    if not directory_path.exists():
        return []
    loader = PyPDFDirectoryLoader(str(directory_path))
    documents = loader.load()
    for document in documents:
        source = document.metadata.get("source", "unknown.pdf")
        document.metadata["source"] = Path(source).name
        document.metadata["page"] = int(document.metadata.get("page", 1))
    return documents


def split_documents(documents: list[Document]) -> list[Document]:
    if not documents:
        return []

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=500,
        chunk_overlap=80,
        length_function=len,
        is_separator_regex=False,
    )
    chunks = splitter.split_documents(documents)
    for chunk in chunks:
        source = chunk.metadata.get("source", "unknown.pdf")
        chunk.metadata["source"] = Path(source).name
        chunk.metadata["page"] = int(chunk.metadata.get("page", 1))
    return chunks


def calculate_chunk_ids(chunks: list[Document]) -> list[Document]:
    for chunk_index, chunk in enumerate(chunks):
        source = Path(chunk.metadata.get("source", "unknown.pdf")).name
        page = int(chunk.metadata.get("page", 1))
        chunk.metadata["id"] = f"{source}:{page}:{chunk_index}"
    return chunks


def add_to_chroma(chunks: list[Document], collection_name: str = COLLECTION_NAME) -> int:
    if not chunks:
        return 0

    db = Chroma(
        collection_name=collection_name,
        persist_directory=CHROMA_PATH,
        embedding_function=get_embedding_function(),
    )
    chunks_with_ids = calculate_chunk_ids(chunks)
    existing_items = db.get(include=[])
    existing_ids = set(existing_items.get("ids", []))

    new_chunks = [chunk for chunk in chunks_with_ids if chunk.metadata.get("id") not in existing_ids]
    if not new_chunks:
        logger.info("No new chunks to index.")
        return 0

    chunk_ids = [chunk.metadata["id"] for chunk in new_chunks]
    db.add_documents(new_chunks, ids=chunk_ids)
    logger.info("Indexed %s new chunks into Chroma.", len(new_chunks))
    return len(new_chunks)


def list_uploaded_files() -> list[str]:
    ensure_storage_paths()
    return sorted(
        path.name
        for path in Path(DATA_PATH).iterdir()
        if path.is_file() and path.suffix.lower() == ".pdf"
    )


def delete_pdf_file(filename: str, collection_name: str = COLLECTION_NAME) -> int:
    safe_filename = secure_filename(filename)
    if not safe_filename or safe_filename != filename or not safe_filename.lower().endswith(".pdf"):
        raise ValueError("Invalid PDF filename.")

    target_path = Path(DATA_PATH) / safe_filename
    if not target_path.is_file():
        raise FileNotFoundError(safe_filename)

    db = Chroma(
        collection_name=collection_name,
        persist_directory=CHROMA_PATH,
        embedding_function=get_embedding_function(),
    )
    matching_chunks = db.get(where={"source": safe_filename}, include=[])
    chunk_ids = matching_chunks.get("ids", [])
    if chunk_ids:
        db.delete(ids=chunk_ids)

    target_path.unlink()
    logger.info("Deleted %s and %s indexed chunks.", safe_filename, len(chunk_ids))
    return len(chunk_ids)


def clear_database() -> None:
    if not Path(CHROMA_PATH).exists():
        return
    for child in Path(CHROMA_PATH).iterdir():
        if child.is_dir():
            shutil.rmtree(child, ignore_errors=True)
        else:
            child.unlink(missing_ok=True)


def ingest_pdf_file(uploaded_file: FileStorage) -> dict:
    filename = secure_filename(uploaded_file.filename or "")
    if not filename.lower().endswith(".pdf"):
        raise ValueError("Only PDF files are allowed.")

    ensure_storage_paths()
    target_path = Path(DATA_PATH) / filename

    uploaded_file.save(str(target_path))
    try:
        documents = PyPDFLoader(str(target_path)).load()
    except Exception as exc:  # pragma: no cover - defensive validation
        raise ValueError("The uploaded PDF is corrupted or unreadable.") from exc

    if not documents:
        raise ValueError("The uploaded PDF does not contain readable pages.")

    chunks = split_documents(documents)
    indexed_count = add_to_chroma(chunks)

    return {
        "message": "PDF uploaded and indexed successfully",
        "filename": filename,
        "pages": len(documents),
        "chunks": len(chunks),
        "indexed": indexed_count,
    }
