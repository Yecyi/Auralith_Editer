# Auralith_Editer macOS handoff

## Automatic checkout

Clone only the root repository. The bootstrap script downloads the three
modified components, verifies their pinned commits, configures both fork and
official remotes, and leaves each component on a local
`codex/ai-native-office-p0`
branch. The initial checkout is shallow, so it does not download the large
upstream histories:

```bash
git clone https://github.com/Yecyi/Auralith_Editer.git
cd Auralith_Editer
bash tools/bootstrap-auralith-macos.sh
```

Codex and other repository-aware agents will read `AGENTS.md`, which instructs
them to run this bootstrap automatically when the submodules are absent or
out of date.

The writable forks may still advertise the legacy `auralith/master` branch as
their remote HEAD. Do not use that as the development target. `.gitmodules`
and the bootstrap script explicitly fetch the pinned
`codex/ai-native-office-p0` branch, so a shallow checkout does not depend on
the forks' default-branch setting.

## Repository map

| Path | Writable origin | Upstream | Branch | Pinned commit |
| --- | --- | --- | --- | --- |
| root | `Yecyi/Auralith_Editer` | `ONLYOFFICE/DesktopEditors` | `codex/ai-native-office-p0` | recorded by root checkout |
| `desktop-sdk` | `Yecyi/desktop-sdk` | `ONLYOFFICE/desktop-sdk` | `codex/ai-native-office-p0` | `4b107d01f955d5d73c8ac5c4c247eb3454071fc3` |
| `web-apps` | `Yecyi/web-apps` | `ONLYOFFICE/web-apps-pro` | `codex/ai-native-office-p0` | `ae954dc3ccd9eab01148bb744c13ee64d5933d65` |
| `sdkjs` | `Yecyi/sdkjs` | `ONLYOFFICE/sdkjs` | `codex/ai-native-office-p0` | `f1946d70cdc4a970e7c17207f8613b448d8afe5f` |

Unmodified submodules remain on their official repositories.

## Current implementation

- `sdkjs` contains the read-only DOCX multimodal snapshot contract,
  structure/object inventory, asset chunking, stale-version checks and source
  navigation, bounded request-local selection reads, plus seven atomic Word write semantics: text and paragraph
  formatting, existing-list level, exact-selection comment add, strict
  single-simple-cell plain-text replacement, and revision-bound main-body
  plain-text replacement, together with bounded selection/exact-match
  replacement and deletion. `document.word-edit-plan@1.0` composes five of
  those kernels into one bounded all-or-nothing native History transaction.
- `web-apps` contains the built-in editor host, header entry, advanced
  settings integration, restricted snapshot bridge, closed write profiles,
  Host-owned document mode/executor and dedicated opaque-receipt write
  transport.
- `desktop-sdk/ChromiumBasedEditors/plugins/ai-agent` contains the Auralith
  Agent UI, general and DOCX harnesses, provider/model configuration, reader
  pipeline, retrieval, citations, storage, typed Office clients, production
  Harness/runtime authorization and tests.
- The `plugins/ai-agent` directory name is historical. The editor loads this
  code as a built-in feature without a plugin GUID or plugin-list entry.
- DOCX Reader conversations use one durable Agent session and execution lane
  per `documentId`. IndexedDB v4 preserves v3 sessions/messages and adds runs,
  deterministic context checkpoints and document progress. One document has
  at most one active and 32 queued runs; initial restore loads the latest 50
  messages and pages older history upward.
- The Reader sidebar renders a compact ChatGPT-style multi-turn thread. Draft
  streaming remains an ephemeral, explicitly unverified plane; Stop creates a
  durable cancelled response and late output is ignored. A completed answer
  atomically replaces its draft only after one terminal V2 result, claim-level
  provenance/quote validation and durable checkpointing. “Work process” shows
  Host-observed source-aware phases, not hidden chain of thought.
- The production composer now exposes only the natural-language textarea,
  document-scoped model selector and Send button. The former text-format,
  paragraph-layout, list and comment button rail is no longer mounted. Closed
  deterministic writes remain usable without a model; generated edits require
  the complete model/document/consent/session dispatch gate.
- Model discovery enriches only live API-returned model IDs with validated
  models.dev metadata. Custom OpenAI-compatible endpoints remain probe-gated,
  configured routes are never overwritten, and Provider secrets do not enter
  the catalog or document session.
- Conversation context uses deterministic head/tail compaction: two recent
  turns are preferred verbatim; older complete turns are admitted newest-first
  before prompt order is restored, and only actual message IDs enter the
  checkpoint. Conversation memory is never document evidence. See
  `AURALITH_DOCUMENT_AGENT.md`.
- Every answer receives a frozen Host-owned `ReaderRequestPlanV1`. Explicit
  document/web/hybrid/write rules remain deterministic; only an unresolved
  read request uses one bounded classifier that cannot add sources, tools or
  write permission. Model-only requests neither scan nor lease the document.
  Existing sessions use `explicit-only` external research, so current-time
  heuristics alone never trigger a silent network call; `adaptive` additionally
  requires provider/consent checks and a cancellable countdown. External
  results are untrusted, limited to five HTTP(S) sources/24,000 excerpt
  characters, and final Markdown URLs must match the request allowlist.
- The source production registry enables
  `document.selection-formatting@1.1`,
  `document.selection-paragraph-formatting@1.0`,
  `document.selection-list-formatting@1.0`, `document.comment@1.0`, and
  `document.selection-table-cell-text@1.0`, plus
  `document.body-text-replacement@1.0`, `document.text-replacement@1.0`, and
  the composite `document.word-edit-plan@1.0`.
  The read-only `document.selection-text@1.0` capability captures a bounded
  exact quote for generated selection edits through fixed `GetSelectedText`
  arguments; it is not projected into Host context or durable memory. The Host owns one per-document
  `read/comment/auto` mode: `read` denies writes, `comment` permits only native
  comments, and `auto` permits all registered bounded writes. `comment/auto`
  skip repetitive per-operation confirmation, while every write still uses an
  immutable Host authorization, a one-shot receipt, no automatic retry after
  committed/unknown dispatch, a short target-scoped collaborative lock, and
  one native LIFO Undo point.
- A Word edit plan has at most 12 ordered operations. V1 supports text and
  paragraph formatting, existing-list level, a final comment and an exclusive
  simple-cell replacement. One outer SDKJS action gives the whole plan one
  native Undo point and exact all-or-nothing rollback. It is not a generic SDK
  or script bridge; body/exact replacement and structural operations are not
  advertised in the plan.
- An immediate model-proposed selection plan uses one 8-second/no-retry
  proposer plus a 30-second one-shot selection lease. The Reader sees only an
  `sl-*` Host handle; SDKJS target state remains private. This path requires a
  non-empty real selection, cannot queue or survive restart, and accepts only
  unchanged or proven-disjoint rebase. Caret-only, intersecting, expired and
  replayed targets fail closed.
- Table-cell P0 replaces the complete plain text of exactly one simple,
  unmerged, top-level cell. It is not a rich-text or structural table editor.
  The current table-level change feed conservatively treats an edit to another
  cell in the same table as a conflict.
- Whole-body P0 is available only in `auto` mode and only for explicit
  whole-document clear/replace instructions. Generation is lock-free and binds
  the final write to the snapshot content revision captured before generation;
  any intervening human edit causes a fail-closed stale result. The short final
  mutation replaces only the main body with bounded plain text in one native
  LIFO Undo point. Headers, footers and document settings stay outside the
  target; rich formatting and arbitrary-range generation are not claimed.
- Document-text replacement P0 is also `auto`-only, but remains distinct from
  the whole-body path. Natural language can target the current selected text,
  one unique exact literal, or every exact literal only when the user explicitly
  asks for all/an equivalent whole-document match scope; an empty replacement deletes the resolved target. Selection is
  limited to one non-empty main-body paragraph and an exact expected quote.
  Search/replacement/selection bounds are 1024/4096/4096 UTF-16 code units,
  with at most 256 matches across 128 main-body paragraphs. Track Revisions
  must be off. Headers, footers and other stories are not searched or mutated.
  Generation and intent parsing remain lock-free; inspect and apply revalidate
  the target, the final mutation holds only short target-scoped locks, and a
  proven disjoint revision move may return `targetResolution: "rebased"` as a
  successful Host receipt. Intersecting or ambiguous drift fails closed, and
  one successful intent produces one native LIFO Undo point.

The current Windows test build can exercise the editor-level Agent. A fully
native start-page/title-bar integration still requires rebuilding the Qt
desktop shell (`desktop-apps`) with the appropriate macOS toolchain.

## Continue development safely

Work and commit inside the affected submodule first:

```bash
git -C desktop-sdk status
git -C desktop-sdk add <paths>
git -C desktop-sdk commit -m "<message>"
git -C desktop-sdk push origin codex/ai-native-office-p0
```

Then record the new submodule commit in the root repository:

```bash
git add desktop-sdk
git commit -m "Update desktop-sdk for <change>"
git push origin codex/ai-native-office-p0
```

Use the equivalent commands for `web-apps` and `sdkjs`. Do not push a root
gitlink until its referenced commit is available from the configured fork.

If a later upstream rebase requires complete history, expand only the component
being synchronized:

```bash
git -C desktop-sdk fetch --unshallow origin
git -C desktop-sdk fetch upstream
```

## Verification baseline

Run the root cross-submodule verifier before committing a gitlink and again
before installing a test application:

```bash
# Local gitlink evidence plus focused contracts/tests/build (default)
bash tools/verify-auralith.sh fast

# Also prove each exact gitlink is fetchable from its Yecyi fork
bash tools/verify-auralith.sh fast --network

# Full Agent E2E, Auralith SDKJS QUnit pages and isolated Word Closure compile
bash tools/verify-auralith.sh full --network
```

The verifier requires Node.js 20. Its Vite and Closure outputs, Playwright
artifacts and network-fetch probes live under a temporary directory that is
removed on exit. It never runs the Agent deploy-packaging script and does not
overwrite tracked or packaged deploy assets.

The 2026-08-14 Chinese whole-body-clear repair checkpoint uses the pushed
submodule commits `desktop-sdk@f473911a`, `web-apps@fa600a69c`, and
`sdkjs@4ab23fb5`. The preceding installed bundle parsed both
`删除文章中的内容` and `删除文章中所有的内容` as exact text deletion, then safely
stopped at `NO_MATCH` before Host dispatch. Its recovery DOCX remained
byte-identical to the source fixture. The closed whole-body grammar now accepts
only an explicit `文章中`, `文章里`, or `文章的` container followed by optional
`所有/全部` and `正文/内容`; it also accepts `所有的内容`. Bare phrases such as
`删除文章内容`, quoted literals, negated/questions, narrower paragraph/table/
selection targets, and compound commands do not escalate to whole-body clear.
Composer capability gating has a regression test proving both screenshot
commands remain deterministic and model-independent when only the body-write
capability is available.

Node.js 20 verification passes 150 Agent test files with 1,777/1,777 tests,
Chromium Playwright 278/278, all nine registered Auralith SDKJS QUnit pages,
isolated Word Closure, and the 3,336-module production Vite build. Formal
`--install` produced rollback point
`/Users/openclaw_server/Applications/Auralith_Editer Test.app.rollback/20260814-160619`.
Both the live and nested rollback apps pass strict deep-signature checks; the
live bundle identifier is `com.auralith.editer.test`, its designated CDHash is
`a21feaa27d86c9e6ed45084b345f26efb83ce9e3`, and the independent installed
payload manifest verifies all 320 entries. The installed `reader.js` SHA-256 is
`1c7c3a7e60002ecbfb9acc1844ca976967ffb86a5a7856173347e40f5648f47e`.

Installed-GUI acceptance used two fresh copies of
`01-headings-paragraphs.docx`. In Auto mode, `删除文章中所有的内容` and
`删除文章中的内容` each cleared the visible main body, returned the Host-verified
native-Undo receipt, and one editor-focused `Cmd+Z` restored both the
`Quarterly review` heading and revenue paragraph. Both temporary files and the
repository fixture retained SHA-256
`176e36cf9d0eb830093fe8ea66df42c2f81b486d5ace81f793afef2629037727`.
That historical package had a separate fail-closed policy gap: after native
Undo, SDKJS retained the Redo branch and rejected a later Agent write as
`BUSY`. The 2026-08-21 source checkpoint replaces that blanket rejection with
one shared native checkpoint policy across all atomic writes and the composite
plan. A new explicit Auto edit may create an ordinary new branch only while the
History prefix and every Redo point identity still match; verified success
truncates Redo, while failure, no-op and verification rollback restore the
exact branch metadata. `UndoRedoInProgress` and observer races still fail
closed. Installed-app evidence for the new policy must be recorded separately
from the historical body-clear run.

The 2026-08-14 native exact-text-replacement repair checkpoint uses the pushed
submodule commits `desktop-sdk@1fc59ff6`, `web-apps@fa600a69c`, and
`sdkjs@4ab23fb5`. A formal install of the preceding package exposed a real
first-request failure for `Replace all north with northern`: SDKJS returned an
executable exact-match snapshot with `selectedTextLength: 0`, while the Host's
closed contract correctly required `searchText.length * matchCount`. The Host
therefore rejected inspection as `INVALID_RESPONSE` before dispatch, and the
document was not mutated. The SDK snapshot now reports the aggregate
caller-supplied literal length for executable and resolved-but-unavailable
exact targets, while a consumed post-write snapshot remains zero. This does
not return document text or relax authorization.

The SDKJS replacement suite now passes 17 tests/118 assertions, including
executable, ambiguous, review-mode unavailable, changed and verified no-op
snapshots. Its focused Word regression matrix, Host profiles/executor and the
cross-module contract verifier also pass. The desktop Host Chromium spec
passes 45/45 and includes fixed-parameter `GetSelectedText` RPC validation plus
an Auto `exactMatches/all` inspect -> receipt -> apply path for three matches
across two paragraphs.

After the gitlinks were committed and pushed, `full --network` passed exact
fork fetchability, Host contracts, desktop Biome/TypeScript, 150 Agent test
files with 1,741/1,741 tests, Chromium Playwright 278/278, all nine registered
Auralith SDKJS QUnit pages, isolated Word Closure and the 3,336-module Vite
build. Formal `--install` then rebuilt and installed the same source. The live
App passes strict deep-signature and bundle-id checks; both live and rollback
payload manifests independently verify 320 entries. The new rollback point is
`/Users/openclaw_server/Applications/Auralith_Editer Test.app.rollback/20260814-143819`,
containing a directly strict-signature-valid `Auralith_Editer Test.app` and six
sibling receipts. macOS locked before post-install window testing, so natural
language replace/delete, the Host receipt and native Undo are **not yet**
installed-GUI evidence for this package; rerun them on a temporary DOCX after
unlocking.

The 2026-08-11 natural-language composer checkpoint uses the pushed submodule
commits `desktop-sdk@f010aa45`, `web-apps@fa600a69c`, and
`sdkjs@e9b392c12`. The manual text-format/paragraph/list/comment action rail is
removed from the production component tree. Common Chinese and English
formatting, layout, list, comment, table-cell, selection/exact-match and
whole-body commands continue through the closed Host capabilities; automatic
text color and conversational selection/paragraph aliases are included.
Deterministic local writes no longer depend on model configuration, while
generated rewrites use the full model dispatch gate and every submitted write
must match its exact available capability. Node.js 20 local verification passed
desktop Vitest 150 files/1,741 tests, Biome 514 files, Reader TypeScript, a
3,336-module `npx vite build`, focused natural-language tests 4 files/112 tests,
and the updated Chromium composer path 1/1. Root commit `a6bfacb` pins the
gitlink, and `full --network` passed exact fork fetchability, Host contracts,
desktop 150 files/1,741 tests, Chromium 278/278, all nine Auralith SDKJS QUnit
pages, isolated Word Closure and the 3,336-module Vite build without touching
tracked/package deploy assets. `--stage-only` then passed package assembly,
payload, production-entry, deep-signature and designated-requirement checks.
Formal `--install` was intentionally not run because the old Test.app remained
open while macOS was locked; the installed bundle and rollback point therefore
remain the 2026-08-10 versions until the user unlocks and exits the app.

The 2026-08-10 document-text replacement checkpoint used the pushed submodule
commits `desktop-sdk@27f7b107`, `web-apps@fa600a69c`, and
`sdkjs@e9b392c12`:

- desktop full Vitest passed 150 files and 1,714/1,714 tests; all three
  TypeScript configurations, Biome over 514 files, and `npx vite build`
  (3,346 modules) passed;
- Reader Chromium Playwright passed 21/21 and Host focused
  profile/executor/transport/runtime tests passed 96/96; the final
  `targetResolution: "rebased"` acceptance regression passed 4 files/32 tests;
- the new SDKJS document-text replacement suite passed 16 tests/105
  assertions; the focused matrix also passed paragraph 14/67, comment 21/150,
  list 13/85, table-cell 20/160, body 4/19 and remote cowork 24/262;
- root `fast --network` passed exact fork fetchability, focused Agent 50
  files/370 tests, all focused SDKJS pages and the isolated Vite build;
- root `full --network` then passed exact fork fetchability, Host contracts,
  desktop full Vitest 150 files/1,714 tests, Chromium Playwright 278/278, all
  nine Auralith SDKJS QUnit pages, isolated Word Closure and the 3,346-module
  Vite build without writing tracked or packaged deploy assets;
- both `--stage-only` and the final formal `--install` completed; the final
  package passed the 3,346-module Vite build, Word Closure compile, payload,
  strict deep signature and designated-requirement checks. The recoverable
  pre-swap copy is `/Users/openclaw_server/Applications/Auralith_Editer Test.app.rollback/20260810-141832`.

The post-gitlink root `fast --network` and `full --network` gates both passed.
The final `desktop-sdk@27f7b107` follow-up changes only browser E2E fixtures, so
it does not alter the already installed production payload. macOS was locked
after installation, so the current app was **not** GUI-retested. Do not
report the new natural-language selection/unique/all/delete routes, Host
receipt, fail/cancel behavior or native Undo as installed-window evidence until
they are observed on this exact package. Positive GUI observations below belong
to older packages and are historical only.

The 2026-08-09 automatic body-write checkpoint was run with Node.js 20.19.5
against the fetchable gitlinks `desktop-sdk@af427f2b`,
`web-apps@6efd1d50c`, and `sdkjs@05da903a3`:

- Agent Vitest passed 145 files and 1,646/1,646 tests;
- all three Agent TypeScript configurations and Biome over 503 source files
  passed;
- Host write profiles/runtime/executor/transport passed 90/90 Node tests;
- Chromium Playwright passed 278/278, including production Read, Comment and
  Auto mode authorization plus an Auto whole-body authorize/execute path;
- the new SDKJS body suite passed 4 tests/19 assertions, including exact
  mixed-body replacement, revision drift rejection, single-use tokens and one
  native Undo restoring the original paragraph/table object graph;
- installed `Auralith_Editer Test.app` interaction against a temporary table
  fixture observed Auto mode with GPT 5.6 Luna replace the complete table body
  with a generated DOCX/Markdown comparison, display a Host-verified receipt,
  and restore the original table with one ordinary native Undo;
- the same installed build observed the deterministic `Clear the entire
  document body.` path replace the main body with zero UTF-16 code units,
  followed by one native Undo restoring the table. The screenshot's exact
  Chinese command is covered by the intent regression test; the GUI driver used
  an ASCII semantic equivalent because its synthetic typing path drops CJK
  composition text in this embedded surface;
- the screenshot-equivalent GPT introduction request routes to model knowledge
  without document retrieval, remote-document consent, or fabricated document
  citations;
- document, hybrid, model, and external routing; optional/forbidden evidence;
  strict quote validation; bounded search results; and external URL allowlists
  have focused regression coverage;
- the root focused verifier now includes all document-body normalization,
  intent, Harness, transport and SDKJS tests in addition to the existing
  typed-write/cowork matrix and isolated Agent Vite build.

This checkpoint does not convert model knowledge into verified evidence and it
does not claim live external research when no supported search provider is
configured. The guarded `--install` transaction rebuilt the Agent and desktop
Word SDK, passed staged and installed deep-signature/designated-requirement
checks, and atomically replaced the dedicated test app at
`/Users/openclaw_server/Applications/Auralith_Editer Test.app`. That
checkpoint's recoverable pre-swap copy was:

`/Users/openclaw_server/Applications/Auralith_Editer Test.app.rollback/20260809-223554`

The installed run proves the provider-backed whole-body generation/apply and
deterministic clear/Undo paths described above. Configured external web search
remains outside this checkpoint and must not be claimed as live-tested here.

The previous 2026-08-06 checkpoint was run with Node.js 20.19.5 against the
fetchable gitlinks `desktop-sdk@e3c4ca8a01b9`, `web-apps@8cd9ac11b32c`, and
`sdkjs@935170484068`:

- all three TypeScript configurations and Biome over 492 source files passed;
- Agent Vitest passed 140 files and 1,604/1,604 tests;
- Host mode/write profiles/runtime/executor/transport passed 87/87 Node tests;
- Chromium Playwright passed 278/278, including production Read, Comment, and
  Auto mode authorization without per-operation approval cards, deterministic locale, 280 px
  RTL containment, provider synchronization, Host, Reader, settings, and
  visual gates;
- focused typed-write QUnit passed paragraph 14/67, comment 21/150, list
  13/85, table-cell 20/160, and remote cowork 24/262; the full registered run
  also passed `pluginsApi` 36/383 and multimodal snapshot 28/335;
- the isolated desktop Word Closure compile and isolated Agent Vite build
  passed; the verifier wrote no tracked or packaged deploy assets.

Both `--stage-only` and the explicit `--install` transaction then completed.
The installed bundle at
`/Users/openclaw_server/Applications/Auralith_Editer Test.app` passed payload,
production-entry, bundle-shape, deep ad-hoc signature, and designated-
requirement checks. The recoverable pre-swap copy is:

`/Users/openclaw_server/Applications/Auralith_Editer Test.app.rollback/20260806-214730`

Native interaction on the preceding install observed Read/Comment/Auto mode
switching, an immediate Auto-mode bold write against a real DOCX selection,
and one ordinary native Undo restoring the pre-write appearance. The same run
also exposed that an English comment command containing the IME fullwidth
colon `：` fell through to model chat; `desktop-sdk@e3c4ca8a01b9` fixes that
deterministic parser gap and the current app was reinstalled from it. The
console locked before the repaired Comment path could be re-observed, so this
positive formatting evidence MUST NOT be generalized to the remaining
comment, failure/cancel, conflict, paragraph, list, or table GUI matrix.

The following 2026-08-04 cowork-safety and macOS installation checkpoint is a
historical baseline. It predates the five production selection-write paths and
MUST NOT be reported as the current branch's final verification:

- Node.js 20 Agent Vitest: 105 files, 1,446/1,446 tests
- Agent and Reader TypeScript checks
- Biome: 407 source files clean with warnings treated as errors
- Host write-executor tests: 17/17; typed Office capability tests: 16/16
- production `npx vite build`: 3,290 transformed modules, followed by the
  built-in deploy packaging script
- full Chromium Playwright E2E: 254/254
- SDKJS QUnit: remote collaborative apply 9 tests/145 assertions,
  `pluginsApi` 36/383, and multimodal snapshot 28/315; the remote suite is
  registered in `sdkjs/tests/runAll.js`
- desktop Word Closure compile with the required desktop/whitespace-only shape
- isolated Test app deploy: 308/308 selected files verified before and after
  signing, including an exact 302-file Agent tree, Host JS/CSS/executor, a
  derived production Document Editor index, and both Word SDK bundles
- the production index remained based on the 124 KB packaged page and gained
  exactly one executor script before the Host script; it still loads
  `require(['app'])` and contains no `app_dev`
- strict deep ad-hoc code-sign verification passed; bundle id remains
  `com.auralith.editer.test`

The recoverable pre-install snapshot is:

`/Users/openclaw_server/Applications/Auralith_Editer Test.app.rollback/20260804-221812`

It contains a full APFS clone of the previously signed app, the selected-file
manifest, signing logs, and the one-line production-index diff. The final
308-file installation-manifest SHA-256 is
`8b83fc902ff445879ab644a980fd1359accae0d844e15fb0687dece58b8a2346`.

That historical app was deliberately not launched because the macOS console
remained locked. Its static hash, production entry, bundle metadata and
signature checks do not certify the current source. The 2026-08-10 checkpoint
above supersedes its stage/install status; current-package installed-app GUI
E2E remains pending before release readiness can be claimed.

The 2026-07-28 macOS Agent checkpoint completed:

- TypeScript and Reader TypeScript checks
- Vitest: 1,266/1,266
- document-reader tests: 406/406
- reader coverage: 94.87% statements, 85.57% branches, 95.84% lines
- Biome: 382 source files clean with warnings treated as errors
- production `npx vite build`
- live models.dev catalog parse: 172 providers, including 42 OpenAI and 15
  Anthropic models at the tested revision
- isolated Test app deploy: 302/302 files exact, strict deep code-sign valid,
  bundle id `com.auralith.editer.test`
- CLI launch with `04-inline-image-caption.docx` remained healthy; final
  visual/interaction inspection was deferred because the Mac login session was
  locked

The last Windows validation completed:

- TypeScript compilation
- Vitest: 978/978
- document-reader tests: 157/157
- reader coverage: 96.93% statements and 87.74% branches
- targeted host and DOCX Playwright: 17/17
- Vite build and deploy packaging
- installed Agent bundle: 302/302 files with no hash differences

Use Node.js 20. For the Agent package:

```bash
cd desktop-sdk/ChromiumBasedEditors/plugins/ai-agent
npm install
npx vitest run
npx vite build
```

When rebuilding the Word SDK for the macOS desktop application, preserve the
desktop, whitespace-only bundle shape expected by the embedded editor:

```bash
cd sdkjs/build
npx grunt compile-word --desktop --level=WHITESPACE_ONLY --formatting=PRETTY_PRINT
```

Do not install the default `npx grunt compile-word` output into a desktop app.
That command produces a substantially smaller advanced-compiled bundle for a
different deployment profile and the macOS editor will fail to open DOCX files
when it replaces the desktop bundle.

## Repeatable macOS test installation

Use the guarded installer for the dedicated user-local test bundle. Its target
is fixed at `~/Applications/Auralith_Editer Test.app`; there is no option that
can redirect writes to a production application, the workspace, or another
directory.

```bash
# Read-only source, target, production-entry, bundle-id and signature preflight.
bash tools/install-auralith-test-macos.sh --dry-run

# Full isolated Agent/Word SDK build, staging, ad-hoc signing and hash checks,
# but no backup or installed-app change.
bash tools/install-auralith-test-macos.sh --stage-only

# Explicit installation transaction after closing Auralith_Editer Test.
bash tools/install-auralith-test-macos.sh --install
```

The script automatically selects a discoverable Node.js 20 runtime. It runs
`npx vite build --outDir ...` in a temporary Agent output directory and uses a
temporary SDKJS build root whose inputs link to the current source working tree
before running the required desktop/whitespace-only Word compile. It never
invokes the Agent deploy-packaging command or writes SDK build output into the
source submodule.

Before installation, the complete current app is copied into a timestamped
rollback **container** under
`~/Applications/Auralith_Editer Test.app.rollback`:

```text
<timestamp>/
├── Auralith_Editer Test.app/
└── receipts/
    ├── before-payload.sha256
    ├── codesign-verify-before.txt
    ├── install-payload.sha256
    ├── codesign-stage.txt
    ├── installed-payload.sha256
    └── codesign-verify-after.txt
```

The `.app` contains only signed bundle content, so it remains a directly
restorable application that must itself pass
`codesign --verify --deep --strict` after the container rename. Hash manifests and signing evidence are
siblings under `receipts/`; they must never be written into the signed bundle
root. The last two receipts appear only after the installed candidate passes
post-swap verification. The transaction remains active until the installed
payload receipts and rollback container are reverified.

The staged app must pass source-to-target comparisons, payload SHA-256
verification, production `require(['app'])`/no-`app_dev` checks, exact write
profiles → executor → transport → Host ordering, desktop Word bundle-shape
checks, bundle identity validation, and strict deep ad-hoc signature
validation. The final replacement uses same-volume renames; if any post-swap
check fails, the script restores the original app and retains the failed
candidate at
`Auralith_Editer Test.app.rollback/failed-<kind>-<timestamp>/Auralith_Editer Test.app`.
The failed-candidate wrapper is also kept separate from diagnostic container
files.

Rollback points through `20260814-140435` use the legacy flat layout: their
application `Contents/` and receipt files share the timestamp directory. The
payload and saved verification evidence remain useful, but the extra root
receipts make those directories fail direct strict code-sign verification with
`unsealed contents present in the bundle root`. Do not rename a legacy
timestamp directory directly to `.app`; recover only its `Contents/` into a
clean `Auralith_Editer Test.app` wrapper and run strict deep-signature and
bundle-id checks before replacement. New rollback containers do not rewrite or
depend on these historical points.

Run the focused, non-installing rollback regression harness after installer
changes:

```bash
bash tools/test-install-auralith-test-macos.sh
```

It uses an internal test-only Applications root and minimal ad-hoc-signed
fixture apps to exercise the real backup and automatic-recovery functions. It
never overrides `HOME`, nor opens, stops or replaces the installed Test app.

The development launcher is also described in `.claude/launch.json`.
