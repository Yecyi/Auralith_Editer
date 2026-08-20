# Auralith Document Agent

## Product contract

Every DOCX owns one durable Auralith Agent conversation. The conversation is
keyed by the host document identity, survives sidebar reloads, and is separate
from evictable snapshot/index caches. Each request still uses an isolated
Provider and General Agent Harness execution so conversational continuity never
weakens evidence, permission, or revision checks.

The sidebar follows a compact ChatGPT-style flow backed by a per-document
durable queue:

1. atomically persist the user message and a `queued` run;
2. admit at most one active run for that document and freeze its Host-owned
   `ReaderRequestPlanV1`;
3. publish source-aware `ReaderActivityV1` phases and stream an explicitly
   unverified draft;
4. accept exactly one terminal `StructuredReaderResultV2` and validate every
   claim against the current document, external request, or model plane;
5. persist the final assistant message before atomically replacing the draft;
6. mark the run complete and start the next still-authorized queue item.

The composer remains editable while a read task runs. A document has at most
one active and 32 queued runs; queued requests can be edited, reordered or
cancelled. Different documents have independent lanes. After restart, an
active run becomes `interrupted` and queued runs become `waiting`; neither is
silently replayed. A queued mutation is not allowed to retain a transient
selection lease.

A request owns an immutable snapshot lease only when its source plan uses the
document. Ordinary typed document changes never cancel that grounded request or
release its image handles. They collapse into one pending refresh, the sidebar
marks the answer as based on its send-time snapshot, and the latest document is
read only after the request settles. Model-only and external-only answers do not
hold the document refresh path. Document/editor replacement,
context-generation change, permission or mode change, consent withdrawal, and
explicit Stop remain cancellation boundaries. Stop aborts only the current
request, immediately publishes and persists one cancelled message, and ignores
late provider chunks or finals. It does not invalidate unrelated queued work.

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

Routing first applies zero-latency hard rules for explicit document, web,
hybrid and write requests. Only a genuinely ambiguous read request may invoke
the currently selected model once as a bounded classifier: it receives the
current question, the most recent user topic and the Host-allowed source
labels, but no document contents or assistant answer; it has a 96-token,
four-second, no-retry contract. The resulting `ReaderRequestPlanV1` freezes
`taskIntent`, source plane, retrieval scope and a Host-built `effectiveQuery`.
The classifier cannot choose an Office capability or increase mode, source,
network or consent permissions.

Each document chooses `off`, `explicit-only` or `adaptive` external research.
Migrated sessions use `explicit-only`: only an explicit request to search or
browse may use the network. Time-sensitive wording alone is blocked with an
actionable message instead of silently searching or falling back to stale
model knowledge. `adaptive` additionally lets the bounded classifier propose
external research, but only after the search provider and consent gates pass
and the two-second cancellable source-plan countdown completes. A short
referential follow-up combines only the previous user topic and current user
text; assistant prose never enters a retrieval or web query.

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

`StructuredReaderResultV2` keeps the streamable top-level `content` plus
closed claim ranges. Every material document claim binds a current evidence
ID, durable anchor and exact quote. Every external claim binds the current
request ID, an allowlisted exact URL and a quote from its sanitized excerpt.
Model claims are explicitly labeled and cannot carry time-sensitive facts.
Range drift, overlap conflict, stale/invalid anchor, quote mismatch, unknown
URL, missing material provenance, absent terminal result, or duplicate
terminal result rejects the formal answer. Draft text never enters this
verified object. Citation display is appended without changing canonical
claim offsets.

## Conversation window algorithm

The current implementation keeps only the useful, deterministic part of
OpenCode's compaction design:

- allocate a bounded history budget from the selected model context window;
- preserve the most recent two complete turns as an exact tail;
- fit older complete turns from newest to oldest, then restore chronological
  prompt order; record only message IDs that actually fit;
- compact an admitted older turn into user intent, a bounded answer excerpt,
  and historical source IDs;
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

IndexedDB schema v4 keeps the original two non-evictable stores and adds three
bounded operational stores:

- `documentAgentSessions`: one session per `documentId`;
- `documentAgentMessages`: ordered user/assistant records with request,
  snapshot, model target, configuration revision, context digest, citations,
  durable citation anchors, selected answer plane, and whether the answer
  actually depends on document evidence; a reverse session/time index loads
  only the latest 50 messages before older-page requests;
- `documentAgentRuns`: queue order, state, frozen request plan, context epoch,
  revision, last safe checkpoint and timing-only milestones;
- `documentAgentContextCheckpoints`: deterministic cursor, digest, actual
  message IDs and budget version, never an LLM-written factual summary;
- `documentAgentProgress`: last reconciled snapshot/revision/content hash,
  section fingerprints, coverage and audit high-water mark.

Snapshot data, rendered assets, embeddings, and analyses remain in the bounded
reader cache. Cache eviction therefore cannot delete the user's conversation.

No API key, request authorization token, raw image bytes, or complete evidence
payload is written to these session records.

## Runtime and safety direction

The long-lived product session and short-lived execution session are
deliberately different:

- the document conversation is durable and user-visible;
- Provider transport and Harness state are request-scoped;
- streaming deltas are ephemeral and `aria-live="off"`;
- verified result checkpoints and bounded audit metadata are durable;
- the visible “work process” is rendered only from persisted or current
  Host-observed activity phases and source planes, never hidden chain of
  thought;
- production Word edits are governed by a Host-owned per-document mode:
  `read` denies writes, `comment` permits only native comments, and `auto`
  permits the bounded production registry. Every permitted write still uses a
  request-scoped runtime, immutable Host authorization, one-shot receipt,
  non-blocking scoped lock, authoritative result, and native LIFO Undo.

OpenCode-inspired durable input admission, per-document execution, typed
context epochs and separate live/durable event planes are now implemented in
the Reader. Its filesystem patching, Git snapshot and process-local approval
mechanisms remain unsuitable Office mutation primitives and do not replace
native History, tracked revisions, locks or Undo.

## Next implementation phases

1. Unify SDKJS and host document identity, including untitled documents,
   rename, Save As lineage, and multi-window fencing.
2. Extend the run ledger with bounded prompt/profile versions, evidence IDs and
   redacted Host errors without persisting model drafts or reasoning.
3. Bind remote-consent receipts to provider endpoint, document, task, modality,
   and expiry; migrate API keys from localStorage to the OS credential store.
4. Generalize the strict external-research adapter beyond the currently
   configured Exa path while retaining the same bounded result contract, URL
   allowlist validation, and Harness network audit.
5. Extend durable addressing beyond the current short-lived, selection-only
   planning lease before allowing queued, restartable or structural model
   plans. Caret-only paragraph/list targets remain unsupported rather than
   guessed.
6. Add paragraph styles/outline, list creation/conversion/renumbering, durable
   cell identity and table structure, comment reply/resolve, and native
   revision-aware review. One authorized intent still maps to one native LIFO
   history point.
7. Add semantic `TableModel` extraction and evaluation-backed global document
   benchmarks before adding further retrieval algorithms.

## Provenance

The design was informed by the local OpenCode checkout, especially its model
catalog normalization, last-known-good refresh, conversation compaction,
durable input admission, run coordination, typed context epochs, permission
precedence, and dual-plane event publication. OpenCode is MIT licensed. The
Auralith implementation is written for this codebase and does not copy its
coding prompts or filesystem mutation engine.
