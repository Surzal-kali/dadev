# Framework Knowledge Directory

Version-controlled operational guides loaded into Open Web UI's knowledge
collection (upload the directory contents into an OWUI knowledge collection;
OWUI's RAG pipeline handles chunking, embedding, and context-top injection).

## Why a directory, not an endpoint?

Embeddings need to land inside OWUI (the chat frontend), not behind a
gateway endpoint the model has to know to call. The schema-knowledge gap is
that OWUI's chat has no built-in schema/tool awareness at init — every
other surface (linters, VS Code, nvim, Jupyter) gets it from the runtime,
but the chat frontend only gets what the system prompt + knowledge
collections provide. This directory is the version-controlled source for
that knowledge; OWUI's own RAG is the delivery mechanism.

## File conventions

- One topic per file, sectioned by `##` headings (OWUI's RAG chunks by
  heading/paragraph — descriptive headings improve retrieval).
- Keep headings descriptive — they're what OWUI's semantic matcher scores
  against. `## ids.db schema` matches "database schema" better than `## DB`.
- Cross-reference source docs by name (`AGENTS.md`, the per-lane `README.md`
  files, the `packaging/man/` man pages) so the model can follow up with the
  full doc if the knowledge chunk truncates.
- No engagement data, no target specifics — assistant-ops knowledge only
  (same scope rule as the `repl-bank` knowledge collection).

## Index

| file | topic |
| --- | --- |
| `engagement_lane.md` | engagement/purge/journal posture for lanes |
| `execute_code.md` | the jupyter execute_code lane (one-shot semantics, tool aliases, lane boundaries) |
| `findings.md` | findings + unknown ledger usage |
| `first_run.md` | bootstrap/order-of-operations for a fresh box |
| `lab-dns.md` | workbench DNS/resolver history |
| `lanes.md` | which process/lane executes what, and how to tell from a result |
| `scope_gate.md` | armed scope semantics for every traffic lane |
| `tool_schema.md` | manifest parameter schema conventions for the big tools |
| `utilities.md` | shell/file utilities baked into the jupyter + open-terminal lanes (what to reach for before a framework tool) |

## Syncing

The bind mount keeps the container's view live with the repo — edit a file
and re-sync the OWUI knowledge collection (OWUI's UI has a re-embed action
per collection, or restart the container). The directory IS the index; no
embedding store in the framework, no sync script, no gateway endpoint.