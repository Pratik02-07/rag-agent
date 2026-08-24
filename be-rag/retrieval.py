from __future__ import annotations

import logging
from typing import List, Tuple

from langchain_chroma import Chroma
from langchain_core.documents import Document

from config import CHROMA_PATH, COLLECTION_NAME
from embeddings_function import get_embedding_function

logger = logging.getLogger(__name__)


class NoRelevantDocumentsError(Exception):
    pass


def retrieve_documents(query: str, k: int = 4) -> List[Tuple[Document, float]]:
    db = Chroma(
        collection_name=COLLECTION_NAME,
        persist_directory=CHROMA_PATH,
        embedding_function=get_embedding_function(),
    )
    results = db.similarity_search_with_score(query, k=k)
    if not results:
        raise NoRelevantDocumentsError("No relevant documents found for the supplied query.")
    return results
