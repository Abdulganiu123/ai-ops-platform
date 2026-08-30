# Retrieval

How `devgen ask` finds relevant past incidents, why it is built this way, and
what would change at scale.

## What runs today

    devgen index                       devgen ask "question"
        |                                     |
    read docs/incidents/*.md            download index.json
        |                                     |
    split at markdown headings          embed the question
        |                                     |
    embed each section (Titan v2)       compare against every chunk
        |                                     |
    write index.json to S3              take top 3 above 0.3
                                              |
                                        prompt the model with those chunks

Three components, all in `devgen/knowledge.py`:

- **`split_sections`** — one chunk per markdown heading. Embedding a whole
  document averages its meaning into something useless; a section carries one
  idea.
- **`embed`** — Amazon Titan Text Embeddings V2 turns text into 1024 numbers
  representing its meaning. Text with similar meaning produces similar numbers,
  which is why "authentication failed" retrieves a postmortem titled "Tearing
  down the infrastructure broke CI".
- **`search`** — embeds the question and compares it against every stored chunk
  using cosine similarity, then returns the closest.

The index lives as a single JSON object in S3. The bucket name is written to
SSM by Terraform and read at runtime, so no identifier is hardcoded.

## This is not a vector database

S3 stores a file. All search happens in Python memory after downloading it.

A vector database uses an index (HNSW, IVF) to examine perhaps 1% of stored
vectors and still find the closest. This implementation compares against 100%
of them. That is correct, and it is linear: twenty chunks means twenty
comparisons, ten thousand chunks means ten thousand.

At the current corpus size that distinction does not matter. The whole index is
under half a megabyte and searches in milliseconds. Introducing a vector
database here would add operational surface to solve a problem that does not
exist yet.

## Where it stops working

A 1024-dimension vector serialised as JSON is roughly 20 KB.

| Documents | Chunks | index.json | Per query |
|---|---|---|---|
| 3 | 20 | 0.4 MB | instant |
| 100 | ~700 | 15 MB | 1-2 s |
| 1,000 | ~7,000 | 140 MB | 10-20 s, memory pressure |
| 10,000 | ~70,000 | 1.4 GB | not viable |

The failure order is worth noting, because it is not what you would guess:

1. **Download** — the whole index is fetched on every question
2. **JSON parsing** — 140 MB of text into Python objects is slow, and each
   Python float costs roughly 24 bytes of memory
3. **Memory** — a 512 MB Lambda exhausts well before the laptop does
4. **The arithmetic** — millions of multiply-adds, still fast

I/O and memory break first. The similarity calculation is the last thing to
become a bottleneck.

## Three changes that extend it

None require a vector database.

**Cache the index in memory.** In a Lambda, load it into a module-level
variable so warm invocations skip the download entirely. The largest single
win, and it costs one line.

**Reduce dimensions.** Titan v2 accepts a `dimensions` parameter of 1024, 512,
or 256. The shorter vectors are the leading numbers of the longer one, arranged
so the most significant information comes first. Reducing 1024 to 512 retains
approximately 99% of retrieval accuracy; 1024 to 256 retains approximately 97%,
at a quarter of the storage.

**Store binary rather than JSON.** The same vectors as a NumPy array are around
4 KB instead of 20 KB, and load far faster than parsing text.

Together these comfortably reach a few thousand documents. Past that, the
answer is a real vector store, not more optimisation.

## Constraints worth knowing

**Embedding models are not interchangeable.** Switching from Titan to Cohere
requires re-embedding the entire corpus, because query vectors and document
vectors must occupy the same coordinate space. This is a decision with
switching costs, not a configuration flag.

**Titan v2 is optimised for English.** Cross-language retrieval is weaker. If
questions and documents use different languages, Cohere Embed Multilingual is
the safer choice.

**Chunk size is bounded by the model.** Titan accepts about 8,000 tokens, so
whole postmortem sections fit. Cohere Embed v3 accepts 512, which would force
finer splitting.

## The managed alternative, and when to switch

Amazon Bedrock Managed Knowledge Base provides six native connectors — S3,
SharePoint, Confluence, Google Drive, OneDrive, and Web Crawler — plus a direct
ingestion API for sources without one. It handles chunking, embedding, vector
storage, and retrieval as a single service.

Two capabilities matter more than the convenience.

**Incremental sync.** Subsequent syncs process only new or modified documents.
`devgen index` re-embeds everything on every run, which is fine for three files
and expensive for five thousand.

**Document-level access control.** This is the reason to switch, and it is not
a nice-to-have.

The current index has no permissions model. Any principal with `s3:GetObject`
on the bucket can retrieve every chunk of every document. That is acceptable
when the corpus is postmortems the whole team can already read. It stops being
acceptable the moment the corpus contains anything with restricted access —
because retrieval would then become a route to read documents you are not
entitled to.

Managed Knowledge Base performs real-time ACL checks in addition to
pre-retrieval filtering, and the filtered documents are transient for the life
of the request, never visible to the model or the user. Note that this applies
to the enterprise connectors; the Web Crawler has no authenticated identity to
map permissions from, so treat it as suitable for public content only.

### The decision

Switch when either becomes true:

- the corpus exceeds roughly a few thousand chunks, or
- the corpus contains anything not everyone with access to the tool should read

Until then, a managed service adds connectors, a vector store, and a
permissions layer for a corpus that needs none of them.

### Sources without a connector

Jira, PagerDuty, incident.io, and Slack have no native connector. Those go
through the direct ingestion API, or a scheduled job:

    scheduled Lambda -> API pull -> normalise to text -> S3 -> sync

The ingestion pattern is the same regardless; only the source client changes.
