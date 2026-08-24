from __future__ import annotations

import argparse

from config import CHROMA_PATH, DATA_PATH
from ingestion import add_to_chroma, clear_database, load_documents_from_directory, split_documents


def main() -> None:
    parser = argparse.ArgumentParser(description="Populate the local ChromaDB with PDFs in the data directory.")
    parser.add_argument("--reset", action="store_true", help="Delete the existing Chroma data before reindexing.")
    args = parser.parse_args()

    if args.reset:
        clear_database()

    print(f"Using Chroma path: {CHROMA_PATH}")
    print(f"Using data path: {DATA_PATH}")

    documents = load_documents_from_directory(DATA_PATH)
    chunks = split_documents(documents)
    indexed_count = add_to_chroma(chunks)

    print(f"Pages loaded: {len(documents)}")
    print(f"Chunks created: {len(chunks)}")
    print(f"Chunks indexed: {indexed_count}")


if __name__ == "__main__":
    main()