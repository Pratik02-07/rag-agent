from __future__ import annotations

from typing import List

from langchain_core.embeddings import Embeddings
from ollama import Client

from config import EMBEDDING_MODEL, OLLAMA_BASE_URL


class OllamaEmbeddingFunction(Embeddings):
    def __init__(self, base_url: str = OLLAMA_BASE_URL, model: str = EMBEDDING_MODEL):
        self.client = Client(host=base_url)
        self.model = model

    def embed_documents(self, texts: List[str]) -> List[List[float]]:
        response = self.client.embed(model=self.model, input=texts)
        return response["embeddings"]

    def embed_query(self, text: str) -> List[float]:
        response = self.client.embed(model=self.model, input=text)
        return response["embeddings"][0]


def get_embedding_function() -> OllamaEmbeddingFunction:
    return OllamaEmbeddingFunction(base_url=OLLAMA_BASE_URL, model=EMBEDDING_MODEL)