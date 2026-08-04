# Auralith Document Agent

## Product contract

Every DOCX owns one durable Auralith Agent conversation. The conversation is
keyed by the host document identity, survives sidebar reloads, and is separate
from evictable snapshot/index caches. Each request still uses an isolated
Provider and General Agent Harness execution so conversational continuity never
weakens evidence, permission, or revision checks.

The sidebar follows a compact ChatGPT-style flow:

1. persist the user message and a pending assistant checkpoint;
2. start the isolated reader task;
3. stream an explicitly unverified draft;
4. validate the structured answer and citations;
5. durably replace the pending checkpoint with the verified answer;
6. render citations on the answer that owns them.

The request also owns an immutable snapshot lease. Ordinary typed document
changes never cancel that request or release its image handles. They collapse
into one pending refresh, the sidebar marks the answer as based on its send-time
snapshot, and the latest document is read only after the request settles.
Document/editor replacement, context-generation change, permission or mode
change, consent withdrawal, and explicit Stop remain cancellation boundaries.

If the app closes between steps 2 and 5, the pending record is restored as an
explicit interrupted response. It is never relabeled as verified.

## Trust boundaries

Three kinds of context remain separate:

| Context | Purpose | Can support a factual claim? |
| --- | --- | --- |
| Current snapshot evidence | Paragraphs, tables, objects, pixels selected by retrieval | Yes, after current allowlist and citation validation |
| Conversation memory | Resolve “it”, “the earlier table”, user preferences, and prior intent | No |
| Trusted editor context | Document/revision identity, mode, capability versions, protection state | No document claims; may constrain authorization |

Old assistant answers and their source IDs are never copied into the current
evidence catalog. Historical source IDs carried by memory are hints only and
must be found and validated again against the current manifest.

## Conversation window algorithm

The current implementation keeps only the useful, deterministic part of
OpenCode's compaction design:

- allocate a bounded history budget from the selected model context window;
- preserve the most recent two complete turns as an exact tail;
- compact only the older head into user intent, a bounded answer excerpt, and
  historical source IDs;
- exclude pending, failed, and cancelled output;
- never split a source ID or silently promote a summary to evidence;
- include the context digest in result-cache identity;
- fall back to the recent tail when older compaction cannot fit.

This is intentionally not an LLM-generated factual summary. It trades some
compression density for deterministic behavior and eliminates a second model
call that could invent decisions or stale document facts.

## Model catalog

Auralith enriches the live model IDs returned by the configured API with a
bounded, validated models.dev snapshot:

- family, description, release/status;
- input/output modalities;
- context/input/output limits;
- reasoning, temperature, and tool-call declarations;
- provider reference endpoint and catalog provenance.

The configured endpoint remains authoritative. Catalog metadata never changes
the route, never stores credentials, never selects a replacement model, and is
not applied to arbitrary OpenAI-compatible endpoints. Fetching uses a response
size limit, timeout, single-flight refresh, normalized schema, and
last-known-good cache.

Model-specific prompts use a small deterministic Office profile selected from
trusted model/provider metadata. OpenCode's coding-agent prompts are not copied.
All profiles retain Auralith's document-injection boundary, forced output
schema, source-ID preservation, and no-hidden-reasoning policy.

## Durable records

IndexedDB schema v3 adds two non-evictable stores:

- `documentAgentSessions`: one session per `documentId`;
- `documentAgentMessages`: ordered user/assistant records with request,
  snapshot, model target, configuration revision, context digest, citations,
  and durable citation anchors.

Snapshot data, rendered assets, embeddings, and analyses remain in the bounded
reader cache. Cache eviction therefore cannot delete the user's conversation.

No API key, request authorization token, raw image bytes, or complete evidence
payload is written to these session records.

## Runtime and safety direction

The long-lived product session and short-lived execution session are
deliberately different:

- the document conversation is durable and user-visible;
- Provider transport and Harness state are request-scoped;
- streaming deltas are ephemeral;
- verified result checkpoints and bounded audit metadata are durable;
- production document edits remain denied while the dedicated Agent tool
  transport, Harness registration, and non-blocking remote scoped-lock path are
  incomplete; the SDKJS/Host selection-formatting pipeline stays gated.

Useful OpenCode runtime ideas for later phases are durable input admission,
coalesced per-session execution, typed context epochs, and separate live versus
durable event planes. Its filesystem patching, Git snapshot, and process-local
approval mechanisms are not suitable Office mutation primitives and will not
replace native History, tracked revisions, locks, or Undo.

## Next implementation phases

1. Unify SDKJS and host document identity, including untitled documents,
   rename, Save As lineage, and multi-window fencing.
2. Persist a bounded Harness event audit with prompt selection/version,
   evidence IDs, lifecycle state, and redacted errors.
3. Upgrade the reader result contract from citation IDs to claim ranges and
   exact evidence quotes, then run the existing quote validator in production.
4. Bind remote-consent receipts to provider endpoint, document, task, modality,
   and expiry; migrate API keys from localStorage to the OS credential store.
5. Add durable document progress high-water marks and startup reconciliation;
   editor change events remain acceleration hints rather than correctness
   authority.
6. Promote the gated selection-formatting operation through the dedicated
   production Agent tool transport and Harness. Preserve its refined
   strict-intent protocol: plan → resolve → normalize → validate → simulate →
   approve → target-lock → apply → verify before finalize → refresh. One
   approved user intent, including one bounded formatting patch, maps to one
   native LIFO history point. Do not add cross-intent timed coalescing.

## Provenance

The design was informed by the local OpenCode checkout, especially its model
catalog normalization, last-known-good refresh, conversation compaction,
durable input admission, run coordination, typed context epochs, permission
precedence, and dual-plane event publication. OpenCode is MIT licensed. The
Auralith implementation is written for this codebase and does not copy its
coding prompts or filesystem mutation engine.
