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
| root | `Yecyi/Auralith_Editer` | `ONLYOFFICE/DesktopEditors` | `master` | recorded by root checkout |
| `desktop-sdk` | `Yecyi/desktop-sdk` | `ONLYOFFICE/desktop-sdk` | `auralith/master` | `25934801e6693529d4a05366cda5e5f01b68cfc0` |
| `web-apps` | `Yecyi/web-apps` | `ONLYOFFICE/web-apps-pro` | `auralith/master` | `8c6ba0daf5f1d1916ceee209379ad013be7054e4` |
| `sdkjs` | `Yecyi/sdkjs` | `ONLYOFFICE/sdkjs` | `auralith/master` | `8c99623eccb957118952dbd49abc20b06726443f` |

Unmodified submodules remain on their official repositories.

## Current implementation

- `sdkjs` contains the read-only DOCX multimodal snapshot contract,
  structure/object inventory, asset chunking, stale-version checks and source
  navigation.
- `web-apps` contains the built-in editor host, header entry, advanced
  settings integration and the restricted snapshot bridge.
- `desktop-sdk/ChromiumBasedEditors/plugins/ai-agent` contains the Auralith
  Agent UI, general and DOCX harnesses, provider/model configuration, reader
  pipeline, retrieval, citations, storage and tests.
- The `plugins/ai-agent` directory name is historical. The editor loads this
  code as a built-in feature without a plugin GUID or plugin-list entry.

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

The development launcher is also described in `.claude/launch.json`.
