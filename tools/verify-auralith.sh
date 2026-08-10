#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent_root="$workspace_root/desktop-sdk/ChromiumBasedEditors/plugins/ai-agent"
mode="fast"
verify_network=false

usage() {
    cat <<'EOF'
Usage: bash tools/verify-auralith.sh [fast|full] [--network]

  fast       Static cross-module checks, focused Agent/Host/SDKJS tests,
             TypeScript checks, and an isolated Vite production build.
  full       Full Agent unit/E2E checks, all registered Auralith SDKJS QUnit pages,
             and an isolated desktop Word Closure compile.
  --network  Also prove each root gitlink can be fetched by exact commit from
             its configured Yecyi fork. The default only uses local Git data.

The command never runs scripts/build.js and writes build/test output only to a
temporary directory. Tracked and packaged deploy assets are not overwritten.
EOF
}

for argument in "$@"; do
    case "$argument" in
        fast|full)
            mode="$argument"
            ;;
        --network)
            verify_network=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

cd "$workspace_root"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command is unavailable: $1"
}

activate_node20() {
    local candidate
    local -a candidates=()

    if command -v node >/dev/null 2>&1; then
        candidates+=("$(command -v node)")
    fi
    candidates+=(
        "/opt/homebrew/opt/node@20/bin/node"
        "/usr/local/opt/node@20/bin/node"
    )
    shopt -s nullglob
    candidates+=("$HOME"/.nvm/versions/node/v20*/bin/node)
    candidates+=("$HOME"/.local/share/mise/installs/node/20*/bin/node)
    shopt -u nullglob

    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]] &&
            [[ "$($candidate -p 'process.versions.node.split(".")[0]')" == "20" ]]; then
            local node20_bin_dir
            node20_bin_dir="$(dirname "$candidate")"
            [[ -x "$node20_bin_dir/npx" ]] || continue
            export PATH="$node20_bin_dir:$PATH"
            hash -r
            return 0
        fi
    done
    return 1
}

require_command git
activate_node20 || fail \
    "Node.js 20 with its matching npx is required and was not found."
echo "OK Node.js $(node --version) from $(command -v node)"

temp_base="${TMPDIR:-/tmp}"
temp_base="${temp_base%/}"
temp_root="$(mktemp -d "$temp_base/auralith-verify.XXXXXX")"
cleanup() {
    case "$temp_root" in
        "$temp_base"/auralith-verify.*)
            rm -rf -- "$temp_root"
            ;;
        *)
            echo "Refusing to remove unexpected temporary path: $temp_root" >&2
            ;;
    esac
}
trap cleanup EXIT INT TERM

is_yecyi_origin() {
    local module="$1"
    local url="$2"
    case "$url" in
        "https://github.com/Yecyi/$module"|\
        "https://github.com/Yecyi/$module.git"|\
        "git@github.com:Yecyi/$module.git"|\
        "ssh://git@github.com/Yecyi/$module.git")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

verify_submodule() {
    local module="$1"
    local gitlink_line gitlink_sha module_head origin_url gitmodules_url

    [[ -d "$workspace_root/$module" ]] || fail "Missing submodule directory: $module"
    git -C "$module" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
        fail "$module is not an initialized Git worktree."

    gitlink_line="$(git ls-tree HEAD -- "$module")"
    [[ "$gitlink_line" == 160000\ commit\ *$'\t'"$module" ]] || \
        fail "Root HEAD does not contain a valid gitlink for $module."
    gitlink_sha="$(printf '%s\n' "$gitlink_line" | awk '{print $3}')"
    module_head="$(git -C "$module" rev-parse HEAD)"
    [[ "$module_head" == "$gitlink_sha" ]] || \
        fail "$module HEAD $module_head does not match root gitlink $gitlink_sha."
    git -C "$module" cat-file -e "$gitlink_sha^{commit}" 2>/dev/null || \
        fail "$module does not contain root gitlink object $gitlink_sha."

    origin_url="$(git -C "$module" remote get-url origin 2>/dev/null)" || \
        fail "$module has no origin remote."
    is_yecyi_origin "$module" "$origin_url" || \
        fail "$module origin is not the Yecyi fork: $origin_url"
    gitmodules_url="$(git config -f .gitmodules --get "submodule.$module.url")" || \
        fail ".gitmodules has no URL for $module."
    is_yecyi_origin "$module" "$gitmodules_url" || \
        fail ".gitmodules does not point $module at the Yecyi fork: $gitmodules_url"

    local origin_witness
    origin_witness="$(
        git -C "$module" for-each-ref \
            --format='%(refname:short)' \
            --contains "$gitlink_sha" \
            refs/remotes/origin/ | head -n 1
    )"
    [[ -n "$origin_witness" ]] || \
        fail "$module gitlink is not contained in any local origin remote ref."

    if [[ "$verify_network" == true ]]; then
        local probe_dir="$temp_root/git-$module"
        git init --bare --quiet "$probe_dir"
        git -C "$probe_dir" fetch --quiet --depth=1 "$origin_url" "$gitlink_sha" || \
            fail "$module gitlink $gitlink_sha is not fetchable from $origin_url."
    fi
    echo "OK $module gitlink ${gitlink_sha:0:12} origin=$origin_url witness=$origin_witness"
}

step "Repository and submodule invariants"
for module in desktop-sdk web-apps sdkjs; do
    verify_submodule "$module"
done

step "Canonical capability, Host gate, manifest, and SDK build-list consistency"
node tools/verify-auralith-contracts.mjs

step "Host runtime, selection-formatting executor, and receipt transport"
node --check web-apps/apps/common/main/lib/auralith-agent-write-profiles.js
node --check web-apps/apps/common/main/lib/auralith-agent-host-runtime.js
node --check web-apps/apps/common/main/lib/auralith-agent-write-executor.js
node --check web-apps/apps/common/main/lib/auralith-agent-write-transport.js
node --check web-apps/apps/common/main/lib/auralith-agent-host.js
node web-apps/test/unit-tests/auralith-agent-write-profiles.test.js
node web-apps/test/unit-tests/auralith-agent-host-runtime.test.js
node web-apps/test/unit-tests/auralith-agent-write-executor.test.js
node web-apps/test/unit-tests/auralith-agent-write-transport.test.js

step "SDKJS syntax and suite registration"
for file in \
    sdkjs/common/CollaborativeEditingBase.js \
    sdkjs/word/Editor/CollaborativeEditing.js \
    sdkjs/word/Editor/document/content-change-feed.js \
    sdkjs/word/Editor/document/multimodal-snapshot.js \
    sdkjs/word/Editor/document/selection-text-formatting.js \
    sdkjs/word/Editor/document/selection-paragraph-formatting.js \
    sdkjs/word/Editor/document/selection-comment.js \
    sdkjs/word/Editor/document/selection-list-formatting.js \
    sdkjs/word/Editor/document/selection-table-cell-text.js \
    sdkjs/word/Editor/document/document-text-replacement.js \
    sdkjs/word/api_plugins.js \
    sdkjs/tests/word/plugins/documentTextReplacement.js \
    sdkjs/tests/word/plugins/remoteCollaborativeApply.js; do
    node --check "$file"
done

vitest_bin="$agent_root/node_modules/.bin/vitest"
tsc_bin="$agent_root/node_modules/.bin/tsc"
vite_bin="$agent_root/node_modules/.bin/vite"
biome_bin="$agent_root/node_modules/.bin/biome"
playwright_bin="$agent_root/node_modules/.bin/playwright"
[[ -x "$vitest_bin" && -x "$tsc_bin" && -x "$vite_bin" ]] || \
    fail "Agent dependencies are missing. Install the locked dependencies under $agent_root."

step "Agent TypeScript"
(
    cd "$agent_root"
    "$tsc_bin" --noEmit
    "$tsc_bin" -p tsconfig.app.json --noEmit
    "$tsc_bin" -p tsconfig.reader.json --noEmit
)

if [[ "$mode" == "fast" ]]; then
    step "Focused Agent unit tests"
    (
        cd "$agent_root"
        "$vitest_bin" run \
            src/agent-harness/harness.test.ts \
            src/office-tools/office-capability-manifest.test.ts \
            src/office-tools/office-capability-registry.test.ts \
            src/office-tools/selection-text-formatting.test.ts \
            src/office-tools/selection-write-profile.test.ts \
            src/office-tools/selection-paragraph-formatting.test.ts \
            src/office-tools/selection-comment.test.ts \
            src/office-tools/selection-list-formatting.test.ts \
            src/office-tools/selection-table-cell-text.test.ts \
            src/office-tools/document-body-text.test.ts \
            src/office-tools/document-text-replacement.test.ts \
            src/document-reader/integration/builtin-document-rpc.test.ts \
            src/document-reader/integration/document-agent-mode.test.ts \
            src/document-reader/integration/document-bridge.test.ts \
            src/document-reader/integration/document-body-text-agent.test.ts \
            src/document-reader/integration/document-body-text-command.test.ts \
            src/document-reader/integration/document-body-write-intent.test.ts \
            src/document-reader/integration/document-text-replacement-agent.test.ts \
            src/document-reader/integration/document-text-replacement-command.test.ts \
            src/document-reader/integration/document-text-replacement-generation.test.ts \
            src/document-reader/integration/immediate-selection-write-intent.test.ts \
            src/document-reader/integration/natural-language-document-edit-intent.test.ts \
            src/document-reader/integration/selection-formatting-agent.test.ts \
            src/document-reader/integration/selection-formatting-command.test.ts \
            src/document-reader/integration/selection-paragraph-formatting-agent.test.ts \
            src/document-reader/integration/selection-paragraph-formatting-command.test.ts \
            src/document-reader/integration/selection-comment-agent.test.ts \
            src/document-reader/integration/selection-comment-command.test.ts \
            src/document-reader/integration/selection-list-formatting-agent.test.ts \
            src/document-reader/integration/selection-list-formatting-command.test.ts \
            src/document-reader/integration/selection-table-cell-text-agent.test.ts \
            src/document-reader/integration/selection-table-cell-text-command.test.ts \
            src/document-reader/session/document-agent.test.ts \
            src/document-reader/ui/ReaderSelectionFormattingAction.test.tsx \
            src/document-reader/ui/ReaderParagraphFormattingAction.test.tsx \
            src/document-reader/ui/ReaderParagraphFormattingControl.test.tsx \
            src/document-reader/ui/ReaderSelectionCommentAction.test.tsx \
            src/document-reader/ui/ReaderSelectionCommentControl.test.tsx \
            src/document-reader/ui/ReaderListFormattingAction.test.tsx \
            src/document-reader/ui/ReaderListFormattingControl.test.tsx \
            src/document-reader/ui/ReaderTableCellTextAction.test.tsx \
            src/document-reader/ui/ReaderTableCellTextControl.test.tsx \
            src/document-reader/ui/ReaderSelectionActionCloseButton.test.tsx \
            src/document-reader/ui/ReaderConversationThread.test.tsx \
            src/document-reader/ui/ReaderSelectionWriteActions.test.tsx \
            src/document-reader/ui/ReaderSidebar.test.tsx \
            src/document-reader/ui/useReaderSelectionActionPanel.test.ts \
            src/document-reader/ui/useSelectionWriteAction.test.ts \
            src/document-reader/ui/host-bridge.test.ts \
            src/document-reader/ui/host-tool-transport.test.ts
    )

    step "Focused SDKJS typed-write and remote-cowork QUnit"
    node tools/run-sdkjs-qunit.mjs word/plugins/selectionParagraphFormatting.html
    node tools/run-sdkjs-qunit.mjs word/plugins/selectionComment.html
    node tools/run-sdkjs-qunit.mjs word/plugins/selectionListFormatting.html
    node tools/run-sdkjs-qunit.mjs word/plugins/selectionTableCellText.html
    node tools/run-sdkjs-qunit.mjs word/plugins/documentBodyText.html
    node tools/run-sdkjs-qunit.mjs word/plugins/documentTextReplacement.html
    node tools/run-sdkjs-qunit.mjs word/plugins/remoteCollaborativeApply.html
else
    step "Full Agent source and unit checks"
    [[ -x "$biome_bin" && -x "$playwright_bin" ]] || \
        fail "Full Agent verification dependencies are missing under $agent_root."
    (
        cd "$agent_root"
        "$biome_bin" check --error-on-warnings ./src
        "$vitest_bin" run
    )

    step "Full Agent Chromium E2E"
    (
        cd "$agent_root"
        "$playwright_bin" test --reporter=line --output="$temp_root/playwright"
    )

    step "Auralith SDKJS QUnit pages"
    node tools/run-sdkjs-qunit.mjs

    step "Isolated desktop Word Closure compile"
    isolated_sdkjs="$temp_root/sdkjs"
    mkdir -p "$isolated_sdkjs/build"
    for source_dir in configs common vendor word cell slide visio pdf; do
        ln -s "$workspace_root/sdkjs/$source_dir" "$isolated_sdkjs/$source_dir"
    done
    cp sdkjs/build/Gruntfile.js sdkjs/build/license.header "$isolated_sdkjs/build/"
    ln -s "$workspace_root/sdkjs/build/node_modules" "$isolated_sdkjs/build/node_modules"
    (
        cd "$isolated_sdkjs/build"
        ./node_modules/.bin/grunt compile-word \
            --desktop \
            --level=WHITESPACE_ONLY \
            --formatting=PRETTY_PRINT
    )
    [[ -s "$isolated_sdkjs/deploy/sdkjs/word/sdk-all.js" ]] || \
        fail "Isolated Closure compile did not produce sdk-all.js."
    [[ -s "$isolated_sdkjs/deploy/sdkjs/word/sdk-all-min.js" ]] || \
        fail "Isolated Closure compile did not produce sdk-all-min.js."
fi

step "Isolated Agent production Vite build"
(
    cd "$agent_root"
    "$vite_bin" build --outDir "$temp_root/agent-dist" --emptyOutDir
)
[[ -s "$temp_root/agent-dist/reader.html" ]] || \
    fail "Vite build did not produce reader.html."

step "Result"
echo "PASS Auralith cross-submodule verification ($mode)"
echo "No tracked or packaged deploy assets were written."
