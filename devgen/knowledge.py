"""
Retrieval over the incident corpus.

Splits markdown into sections, embeds each one, and stores the vectors in S3.
At query time we embed the question and return the closest sections.

No vector database. At a few hundred sections, comparing numbers in memory is
faster than a network call to one.
"""

import json
import re
from pathlib import Path

import boto3

EMBED_MODEL = "amazon.titan-embed-text-v2:0"
INDEX_KEY = "index.json"

bedrock = boto3.client("bedrock-runtime")
s3 = boto3.client("s3")


def embed(text):
    """Turn text into a list of 1024 numbers representing its meaning."""
    resp = bedrock.invoke_model(
        modelId=EMBED_MODEL,
        body=json.dumps({"inputText": text}),
    )
    return json.loads(resp["body"].read())["embedding"]


def split_sections(path):
    """Split a markdown file at its headings. One chunk per section."""
    text = path.read_text()
    parts = re.split(r"\n(?=#{1,3} )", text)
    return [p.strip() for p in parts if len(p.strip()) > 100]


def cosine(a, b):
    """How similar two lists of numbers are. 1.0 is identical, 0.0 unrelated."""
    dot = sum(x * y for x, y in zip(a, b))
    size_a = sum(x * x for x in a) ** 0.5
    size_b = sum(y * y for y in b) ** 0.5
    return dot / (size_a * size_b)


def build_index(docs_dir, bucket):
    """Embed every section of every markdown file and store the result in S3."""
    chunks = []
    for path in sorted(Path(docs_dir).glob("*.md")):
        for section in split_sections(path):
            chunks.append({
                "source": path.name,
                "text": section,
                "vector": embed(section),
            })

    s3.put_object(Bucket=bucket, Key=INDEX_KEY, Body=json.dumps(chunks))
    return len(chunks)


def search(question, bucket, top_k=3, min_score=0.3):
    """Return the (source, text, score) of the closest sections."""
    obj = s3.get_object(Bucket=bucket, Key=INDEX_KEY)
    chunks = json.loads(obj["Body"].read())

    question_vector = embed(question)
    scored = [
        (c["source"], c["text"], cosine(question_vector, c["vector"]))
        for c in chunks
    ]
    scored.sort(key=lambda item: item[2], reverse=True)
    return [hit for hit in scored[:top_k] if hit[2] >= min_score]

def with_context(text, bucket, max_query_chars=2000):
    """
    Prepend relevant past incidents to a failure log.

    Returns the text unchanged if nothing relevant is found, or if retrieval
    fails - a missing index must not stop a diagnosis.
    """
    try:
        hits = search(text[:max_query_chars], bucket)
    except Exception:
        return text

    if not hits:
        return text

    past = "\n\n---\n\n".join(chunk for _, chunk, _ in hits)
    return (
        f"PAST INCIDENTS THAT MAY BE RELEVANT:\n\n{past}\n\n"
        f"=====\n\n"
        f"CURRENT FAILURE LOG:\n\n{text}"
    )