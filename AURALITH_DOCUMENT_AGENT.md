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

A request owns an immutable snapshot lease only when its source plan uses the
document. Ordinary typed document changes never cancel that grounded request or
release its image handles. They collapse into one pending refresh, the sidebar
marks the answer as based on its send-time snapshot, and the latest document is
read only after the request settles. Model-only and external-only answers do not
hold the document refresh path. Document/editor replacement,
context-generation change, permission or mode change, consent withdrawal, and
explicit Stop remain cancellation boundaries.

If the app closes between steps 2 and 5, the pending record is restored as an
explicit interrupted response. It is never relabeled as verified.

## Trust boundaries

Five kinds of context remain separate:

| Context | Purpose | Can support a factual claim? |
| --- | --- | --- |
| Current snapshot evidence | Paragraphs, tables, objects, pixels selected by retrieval | Yes, after current allowlist and citation validation |
| Model knowledge | General creation, explanation, and stable background knowledge | Yes, but it is labeled as model knowledge and is neither document-verified nor live-verified |
| Host-fetched external research | Bounded excerpts from the configured search provider | Yes, after URL/protocol/size validation; current claims must link to this request's URL allowlist |
| Conversation memory | Resolve “it”, “the earlier table”, user preferences, and prior intent | No |
| Trusted editor context | Document/revision identity, mode, capability versions, protection state | No document claims; may constrain authorization |

Old assistant answers and their source IDs are never copied into the current
evidence catalog. Historical source IDs carried by memory are hints only and
must be found and validated again against the current manifest.

## Per-request source planning

The sidebar is an editor agent, not a document-only search box. Before
retrieval or provider transport, a deterministic Host router produces one
immutable source plan:

| Plane | Document evidence | Model knowledge | External research |
| --- | --- | --- | --- |
| `document` | required | forbidden | forbidden |
| `model` | forbidden | allowed | forbidden |
| `hybrid` | required | allowed | forbidden |
| `external` | required only for an explicit document comparison | allowed | required |

Routing uses a small precedence order rather than a second model call:

1. explicit browsing or time-sensitive wording such as “latest”, “today”, or
   “official source” requires external research;
2. an explicit request to combine the document with background knowledge uses
   the hybrid plane;
3. explicit document, selection, table, image, page, quote, or transform
   wording remains document-only;
4. a short referential follow-up inherits the previous completed answer plane;
5. an otherwise standalone creation or explanation request uses model
   knowledge.

The plan can narrow access but the model cannot broaden it. A model-only call
does not walk the manifest, does not request remote-document consent, emits no
document source markers, and remains valid when the document changes. A
document-only call retains the existing current-revision catalog, exact-quote
verification, and minimum-one-reference Harness gate. Hybrid calls cite only
claims derived from the document and distinguish uncited background knowledge.

External search is a Host-selected Harness network operation, not a free-form
model tool call. The current adapter accepts at most five unique HTTP(S)
results, at most 6,000 excerpt characters per result and 24,000 total. Search
content remains untrusted data. The final answer must contain a Markdown link
from the exact request URL allowlist; an invented URL fails validation. If no
supported search provider is configured or no usable result is returned, the
request fails explicitly instead of silently falling back to possibly stale
model knowledge.

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
  durable citation anchors, selected answer plane, and whether the answer
  actually depends on document evidence.

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
- production Word edits are governed by a Host-owned per-document mode:
  `read` denies writes, `comment` permits only native comments, and `auto`
  permits the bounded production registry. Every permitted write still uses a
  request-scoped runtime, immutable Host authorization, one-shot receipt,
  non-blocking scoped lock, authoritative result, and native LIFO Undo.

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
3. Complete claim-range coverage for every material statement; exact evidence
   quote validation is already active in production.
4. Bind remote-consent receipts to provider endpoint, document, task, modality,
   and expiry; migrate API keys from localStorage to the OS credential store.
5. Add durable document progress high-water marks and startup reconciliation;
   editor change events remain acceleration hints rather than correctness
   authority.
6. Extend the same mode-authorized strict-intent protocol to the next Word
   semantics: body-text replacement with a frozen target, paragraph
   styles/outline, list creation/conversion, durable cell identity and table
   structure, comment reply/resolve, and revision-aware review. One authorized
   intent maps to one native LIFO history point; do not add cross-intent timed
   coalescing.
7. Add a submit-time opaque selection lease before enabling model-generated
   rewrites from chat. The current deterministic chat router intentionally
   handles only complete-message, single-match commands; a delayed model result
   must never attach itself to whatever selection happens to be live later.
8. Generalize the strict external-research adapter beyond the currently
   configured Exa path while retaining the same bounded result contract, URL
   allowlist validation, and Harness network audit.

## Provenance

The design was informed by the local OpenCode checkout, especially its model
catalog normalization, last-known-good refresh, conversation compaction,
durable input admission, run coordination, typed context epochs, permission
precedence, and dual-plane event publication. OpenCode is MIT licensed. The
Auralith implementation is written for this codebase and does not copy its
coding prompts or filesystem mutation engine.
