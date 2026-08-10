# Auralith_Editer macOS handoff

## Automatic checkout

Clone only the root repository. The bootstrap script downloads the three
modified components, verifies their pinned commits, configures both fork and
official remotes, and leaves each component on a local `auralith/master`
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

Each writable fork uses `auralith/master` as its GitHub default branch. This
ensures a shallow submodule clone downloads the Auralith tree directly instead
of downloading the upstream `master` tree first.

## Repository map

| Path | Writable origin | Upstream | Branch | Pinned commit |
| --- | --- | --- | --- | --- |
| root | `Yecyi/Auralith_Editer` | `ONLYOFFICE/DesktopEditors` | `codex/ai-native-office-p0` | recorded by root checkout |
| `desktop-sdk` | `Yecyi/desktop-sdk` | `ONLYOFFICE/desktop-sdk` | `codex/ai-native-office-p0` | `27f7b10745baeefe4f0e16b6b9d9e0b197f7e938` |
| `web-apps` | `Yecyi/web-apps` | `ONLYOFFICE/web-apps-pro` | `codex/ai-native-office-p0` | `fa600a69cabc868efd4e28a3fb502ee89a82bfcc` |
| `sdkjs` | `Yecyi/sdkjs` | `ONLYOFFICE/sdkjs` | `codex/ai-native-office-p0` | `e9b392c1275eb3ad01560a1c46d725133e2a3eeb` |

Unmodified submodules remain on their official repositories.

## Current implementation

- `sdkjs` contains the read-only DOCX multimodal snapshot contract,
  structure/object inventory, asset chunking, stale-version checks and source
  navigation, a bounded request-local selection-text read, plus seven bounded Word write semantics: text and paragraph
  formatting, existing-list level, exact-selection comment add, strict
  single-simple-cell plain-text replacement, and revision-bound main-body
  plain-text replacement, together with bounded selection/exact-match
  replacement and deletion.
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
- DOCX Reader conversations now use one durable Agent session per
  `documentId`. IndexedDB v3 stores ordered user/assistant messages, request
  and model provenance, per-answer citations and durable citation anchors
  outside the evictable reader cache.
- The Reader sidebar renders a compact ChatGPT-style multi-turn thread. Draft
  streaming remains an ephemeral, explicitly unverified plane; a completed
  answer becomes visible only after citation validation and durable
  checkpointing.
- Model discovery enriches only live API-returned model IDs with validated
  models.dev metadata. Custom OpenAI-compatible endpoints remain probe-gated,
  configured routes are never overwritten, and Provider secrets do not enter
  the catalog or document session.
- Conversation context uses deterministic head/tail compaction: two recent
  turns are preferred verbatim, older turns reduce to intent, bounded answer
  excerpts and source IDs that must be revalidated. Conversation memory is
  never document evidence. See `AURALITH_DOCUMENT_AGENT.md`.
- Every answer now receives a deterministic Host-owned source plan. Explicit
  document questions remain current-snapshot grounded; standalone creation and
  explanation can use model knowledge; explicit combinations use document plus
  model knowledge; current or browsing requests use the configured bounded web
  search. Model-only requests neither scan nor lease the document. External
  results are untrusted, limited to five HTTP(S) sources/24,000 excerpt
  characters, and final Markdown URLs must match the request allowlist.
- The source production registry enables
  `document.selection-formatting@1.1`,
  `document.selection-paragraph-formatting@1.0`,
  `document.selection-list-formatting@1.0`, `document.comment@1.0`, and
  `document.selection-table-cell-text@1.0`, plus
  `document.body-text-replacement@1.0` and `document.text-replacement@1.0`.
  The read-only `document.selection-text@1.0` capability captures a bounded
  exact quote for generated selection edits through fixed `GetSelectedText`
  arguments; it is not projected into Host context or durable memory. The Host owns one per-document
  `read/comment/auto` mode: `read` denies writes, `comment` permits only native
  comments, and `auto` permits all registered bounded writes. `comment/auto`
  skip repetitive per-operation confirmation, while every write still uses an
  immutable Host authorization, a one-shot receipt, no automatic retry after
  committed/unknown dispatch, a short target-scoped collaborative lock, and
  one native LIFO Undo point.
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
git -C desktop-sdk push origin auralith/master
```

Then record the new submodule commit in the root repository:

```bash
git add desktop-sdk
git commit -m "Update desktop-sdk for <change>"
git push origin master
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

The 2026-08-10 document-text replacement checkpoint uses the pushed submodule
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

Before installation, the complete current app is copied to a timestamped
directory under `~/Applications/Auralith_Editer Test.app.rollback`. The staged
app must pass source-to-target comparisons, payload SHA-256 verification,
production `require(['app'])`/no-`app_dev` checks, exact
write profiles → executor → transport → Host ordering, desktop Word
bundle-shape checks, bundle
identity validation, and strict deep ad-hoc signature validation. The final
replacement uses same-volume renames; if any post-swap check fails, the script
restores the original app and retains the failed candidate for diagnosis.

The development launcher is also described in `.claude/launch.json`.
