from __future__ import annotations

import re
from typing import Iterable

from langchain_core.documents import Document
from langchain_ollama import ChatOllama

from config import OLLAMA_BASE_URL, OLLAMA_MODEL

SYSTEM_PROMPT = (
    "You are a document question-answering assistant.\n\n"
    "Answer the user's question using ONLY the supplied context.\n"
    "If the answer cannot be found in the supplied context, clearly say that the information is not available in the uploaded documents.\n"
    "Do not invent facts.\n"
    "Keep the answer clear and concise.\n"
    "Return plain text."
)


def clean_response_text(text: str) -> str:
    cleaned = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    cleaned = re.sub(r"\*([^*]+)\*", r"\1", cleaned)
    cleaned = cleaned.replace("```", "").strip()
    return cleaned


def generate_answer(question: str, context_documents: Iterable[Document]) -> str:
    context_documents = list(context_documents)
    if not context_documents:
        return "The information is not available in the uploaded documents."

    context = "\n\n---\n\n".join(doc.page_content for doc in context_documents)
    prompt = (
        f"{SYSTEM_PROMPT}\n\n"
        f"Context:\n{context}\n\n"
        f"Question:\n{question}\n\n"
        "Answer:"
    )

    llm = ChatOllama(model=OLLAMA_MODEL, base_url=OLLAMA_BASE_URL)
    response = llm.invoke(prompt)
    answer = response.content if hasattr(response, "content") else str(response)
    return clean_response_text(answer)
