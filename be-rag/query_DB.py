import argparse

from generation import generate_answer
from retrieval import retrieve_documents


def main() -> None:
    parser = argparse.ArgumentParser(description="Query the indexed PDF corpus via the RAG pipeline.")
    parser.add_argument("question", help="Question to ask the RAG system.")
    args = parser.parse_args()

    documents = retrieve_documents(args.question, k=4)
    answer = generate_answer(args.question, [doc for doc, _ in documents])
    print(answer)


if __name__ == "__main__":
    main()