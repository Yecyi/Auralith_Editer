#!/usr/bin/env bash

# Build and install the Auralith Agent into the dedicated macOS test bundle.
#
# Safety model:
#   * the only writable application target is
#       $HOME/Applications/Auralith_Editer Test.app
#   * the default mode is a read-only preflight
#   * all build and signing work happens in a same-volume staging directory
#   * --install makes a verified timestamped backup before an atomic rename
#   * a failed post-swap verification restores the original application

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly USER_APPLICATIONS="${HOME:?HOME is required}/Applications"
readonly TARGET_APP="$USER_APPLICATIONS/Auralith_Editer Test.app"
readonly ROLLBACK_ROOT="$USER_APPLICATIONS/Auralith_Editer Test.app.rollback"
readonly EXPECTED_BUNDLE_ID="com.auralith.editer.test"

MODE="dry-run"
MODE_ARGUMENT=""
TEMP_ROOT=""
STAGED_APP=""
ORIGINAL_SWAP_APP=""
TRANSACTION_ACTIVE=0
PRESERVE_TEMP=0

usage() {
    cat <<'EOF'
Usage: tools/install-auralith-test-macos.sh [--dry-run|--stage-only|--install]

  --dry-run    Read-only preflight (default). Does not build or modify the app.
  --stage-only Build, assemble, sign, and verify a temporary app, then remove it.
  --install    Build and verify a staged app, make a timestamped rollback copy,
               and atomically replace the dedicated test app.

The install target is intentionally fixed and cannot be overridden:
  $HOME/Applications/Auralith_Editer Test.app
EOF
}

log() {
    printf '[auralith-macos-install] %s\n' "$*"
}

warn() {
    printf '[auralith-macos-install] WARNING: %s\n' "$*" >&2
}

die() {
    printf '[auralith-macos-install] ERROR: %s\n' "$*" >&2
    exit 1
}

for argument in "$@"; do
    case "$argument" in
        --dry-run|--stage-only|--install)
            if [[ -n "$MODE_ARGUMENT" && "$MODE_ARGUMENT" != "$argument" ]]; then
                usage >&2
                die "Choose exactly one execution mode."
            fi
            MODE_ARGUMENT="$argument"
            MODE="${argument#--}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "Unknown argument: $argument"
            ;;
    esac
done

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"
}

require_file() {
    [[ -f "$1" ]] || die "Required file is missing: $1"
}

require_directory() {
    [[ -d "$1" ]] || die "Required directory is missing: $1"
}

assert_fixed_paths() {
    require_directory "$USER_APPLICATIONS"
    [[ ! -L "$USER_APPLICATIONS" ]] ||
        die "The user Applications directory must not be a symlink: $USER_APPLICATIONS"
    [[ "$TARGET_APP" == "$USER_APPLICATIONS/Auralith_Editer Test.app" ]] ||
        die "Internal target-path invariant failed."
    [[ "$ROLLBACK_ROOT" == "$USER_APPLICATIONS/Auralith_Editer Test.app.rollback" ]] ||
        die "Internal rollback-path invariant failed."
    [[ ! -L "$TARGET_APP" ]] ||
        die "Refusing to use a symlink as the application target: $TARGET_APP"
    if [[ -e "$ROLLBACK_ROOT" && -L "$ROLLBACK_ROOT" ]]; then
        die "Refusing to use a symlink as the rollback root: $ROLLBACK_ROOT"
    fi
}

find_node20() {
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
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

configure_node20() {
    local node20
    node20="$(find_node20)" ||
        die "Node.js 20 is required. Install it or make an existing Node 20 runtime discoverable."
    local node_bin_dir
    node_bin_dir="$(dirname "$node20")"
    [[ -x "$node_bin_dir/npx" ]] ||
        die "The selected Node.js 20 runtime has no matching npx: $node_bin_dir"
    export PATH="$node_bin_dir:$PATH"
    hash -r
    [[ "$(node -p 'process.versions.node.split(".")[0]')" == "20" ]] ||
        die "Failed to activate Node.js 20."
    log "Using $(node --version) from $(command -v node)"
}

bundle_executable() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
        "$TARGET_APP/Contents/Info.plist" 2>/dev/null
}

bundle_identifier() {
    local app_path="$1"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$app_path/Contents/Info.plist" 2>/dev/null
}

running_target_pids() {
    local executable_name
    local executable_path
    executable_name="$(bundle_executable)" || return 0
    executable_path="$TARGET_APP/Contents/MacOS/$executable_name"
    export AURALITH_INSTALL_RUNNING_TARGET="$TARGET_APP/Contents/"
    {
        if [[ -f "$executable_path" ]]; then
            lsof -t -- "$executable_path" 2>/dev/null || true
        fi
        ps -axo pid=,command= | awk \
            'index($0, ENVIRON["AURALITH_INSTALL_RUNNING_TARGET"]) { print $1 }'
    } | awk 'NF' | sort -nu
    unset AURALITH_INSTALL_RUNNING_TARGET
}

assert_target_app() {
    require_directory "$TARGET_APP"
    require_file "$TARGET_APP/Contents/Info.plist"
    local actual_bundle_id
    actual_bundle_id="$(bundle_identifier "$TARGET_APP")" ||
        die "Unable to read the installed test bundle identifier."
    [[ "$actual_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] ||
        die "Refusing unexpected bundle id '$actual_bundle_id' at $TARGET_APP"
}

assert_not_running_for_install() {
    local pids
    pids="$(running_target_pids)"
    if [[ -n "$pids" ]]; then
        if [[ "$MODE" == "install" ]]; then
            die "Close Auralith_Editer Test before installing (running PIDs: ${pids//$'\n'/, })."
        fi
        warn "Auralith_Editer Test is running (PIDs: ${pids//$'\n'/, }); --install would refuse to continue."
    else
        log "The installed test application is not running."
    fi
}

readonly AGENT_ROOT="$WORKSPACE_ROOT/desktop-sdk/ChromiumBasedEditors/plugins/ai-agent"
readonly AGENT_BUILD_SCRIPT="$AGENT_ROOT/scripts/build.js"
readonly AGENT_REGISTRY="$AGENT_ROOT/src/office-tools/office-capabilities.json"
readonly SDKJS_ROOT="$WORKSPACE_ROOT/sdkjs"
readonly SDKJS_GRUNTFILE="$SDKJS_ROOT/build/Gruntfile.js"
readonly WEB_APPS_COMMON="$WORKSPACE_ROOT/web-apps/apps/common/main/lib"
readonly HOST_RUNTIME_JS="$WEB_APPS_COMMON/auralith-agent-host-runtime.js"
readonly HOST_JS="$WEB_APPS_COMMON/auralith-agent-host.js"
readonly HOST_CSS="$WEB_APPS_COMMON/auralith-agent-host.css"
readonly HOST_TOKENS_CSS="$WEB_APPS_COMMON/auralith-agent-host-tokens.css"
readonly HOST_BASE_LAYOUT_CSS="$WEB_APPS_COMMON/auralith-agent-host-base-layout.css"
readonly HOST_WRITE_APPROVAL_CSS="$WEB_APPS_COMMON/auralith-agent-host-write-approval.css"
readonly WRITE_PROFILES_JS="$WEB_APPS_COMMON/auralith-agent-write-profiles.js"
readonly WRITE_EXECUTOR_JS="$WEB_APPS_COMMON/auralith-agent-write-executor.js"
readonly WRITE_TRANSPORT_JS="$WEB_APPS_COMMON/auralith-agent-write-transport.js"

assert_source_inputs() {
    require_file "$AGENT_ROOT/vite.config.ts"
    require_file "$AGENT_ROOT/reader.html"
    require_file "$AGENT_BUILD_SCRIPT"
    require_file "$AGENT_REGISTRY"
    require_file "$SDKJS_GRUNTFILE"
    require_file "$SDKJS_ROOT/build/license.header"
    require_file "$SDKJS_ROOT/build/node_modules/.bin/grunt"
    require_file "$HOST_RUNTIME_JS"
    require_file "$HOST_JS"
    require_file "$HOST_CSS"
    require_file "$HOST_TOKENS_CSS"
    require_file "$HOST_BASE_LAYOUT_CSS"
    require_file "$HOST_WRITE_APPROVAL_CSS"
    require_file "$WRITE_PROFILES_JS"
    require_file "$WRITE_EXECUTOR_JS"
    require_file "$WRITE_TRANSPORT_JS"
    require_file "$AGENT_ROOT/node_modules/.bin/vite"

    node --check "$HOST_RUNTIME_JS"
    node --check "$HOST_JS"
    node --check "$WRITE_PROFILES_JS"
    node --check "$WRITE_EXECUTOR_JS"
    node --check "$WRITE_TRANSPORT_JS"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
        "$AGENT_REGISTRY"
}

verify_production_entry() {
    local app_path="$1"
    local document_index="$app_path/Contents/Resources/editors/web-apps/apps/documenteditor/main/index.html"
    require_file "$document_index"
    grep -Fq "require(['app'])" "$document_index" ||
        die "Document Editor index is not a production require(['app']) page: $document_index"
    if grep -Fq "app_dev" "$document_index"; then
        die "Document Editor index contains app_dev: $document_index"
    fi
}

readonly_python_hash_tool() {
    python3 - "$@" <<'PY'
import hashlib
import pathlib
import sys

mode = sys.argv[1]
root = pathlib.Path(sys.argv[2])
manifest = pathlib.Path(sys.argv[3])

def digest(path: pathlib.Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()

if mode == "generate-payload":
    paths = []
    fixed = [
        "Contents/Info.plist",
        "Contents/Resources/editors/sdkjs/word/sdk-all-min.js",
        "Contents/Resources/editors/sdkjs/word/sdk-all.js",
        "Contents/Resources/editors/web-apps/apps/common/main/lib/auralith-agent-host-runtime.js",
        "Contents/Resources/editors/web-apps/apps/common/main/lib/auralith-agent-host.js",
        "Contents/Resources/editors/web-apps/apps/common/main/lib/auralith-agent-host.css",
        "Contents/Resources/editors/web-apps/apps/common/main/lib/auralith-agent-host-tokens.css",
        "Contents/Resources/editors/web-apps/apps/common/main/lib/auralith-agent-host-base-layout.css",
        "Contents/Resources/editors/web-apps/apps/common/main/lib/auralith-agent-host-write-approval.css",
        "Contents/Resources/editors/web-apps/apps/common/main/lib/auralith-agent-write-profiles.js",
        "Contents/Resources/editors/web-apps/apps/common/main/lib/auralith-agent-write-executor.js",
        "Contents/Resources/editors/web-apps/apps/common/main/lib/auralith-agent-write-transport.js",
    ]
    for relative in fixed:
        path = root / relative
        if path.is_file():
            paths.append(path)
    for editor in (
        "documenteditor",
        "spreadsheeteditor",
        "presentationeditor",
        "pdfeditor",
        "visioeditor",
    ):
        path = root / f"Contents/Resources/editors/web-apps/apps/{editor}/main/index.html"
        if path.is_file():
            paths.append(path)
    agent = root / "Contents/Resources/editors/web-apps/apps/common/main/auralith-agent"
    if agent.is_dir():
        paths.extend(path for path in agent.rglob("*") if path.is_file())
    paths = sorted(set(paths), key=lambda path: path.relative_to(root).as_posix())
    if not paths:
        raise SystemExit("No payload files found")
    manifest.write_text(
        "".join(
            f"{digest(path)}  {path.relative_to(root).as_posix()}\n"
            for path in paths
        ),
        encoding="utf-8",
    )
elif mode == "verify":
    failures = []
    for line in manifest.read_text(encoding="utf-8").splitlines():
        expected, separator, relative = line.partition("  ")
        if not separator or len(expected) != 64:
            failures.append(f"malformed manifest line: {line}")
            continue
        path = root / relative
        if not path.is_file():
            failures.append(f"missing: {relative}")
        elif digest(path) != expected:
            failures.append(f"hash mismatch: {relative}")
    if failures:
        raise SystemExit("\n".join(failures))
else:
    raise SystemExit(f"Unknown hash mode: {mode}")
PY
}

generate_payload_manifest() {
    readonly_python_hash_tool generate-payload "$1" "$2"
}

verify_payload_manifest() {
    readonly_python_hash_tool verify "$1" "$2"
}

create_agent_manifest() {
    local agent_build="$1"
    node --input-type=module - "$AGENT_BUILD_SCRIPT" "$agent_build/manifest.json" <<'NODE'
import fs from "node:fs";
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
const outputPath = process.argv[3];
const buildModule = await import(`${pathToFileURL(modulePath).href}?installer=${Date.now()}`);
const registry = buildModule.loadOfficeCapabilityRegistry();
const manifest = buildModule.createBuiltInAgentManifest(registry);
fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
}

validate_agent_build() {
    local agent_build="$1"
    for required in reader.html reader.js reader.css manifest.json; do
        require_file "$agent_build/$required"
    done
    [[ ! -e "$agent_build/index.html" ]] ||
        die "The built-in Agent staging directory must not contain index.html."
    node - "$agent_build" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const root = process.argv[2];
const html = fs.readFileSync(path.join(root, "reader.html"), "utf8");
for (const match of html.matchAll(/(?:src|href)=["']\.\/([^"'?]+)/g)) {
  const dependency = path.join(root, match[1]);
  if (!fs.statSync(dependency, { throwIfNoEntry: false })?.isFile()) {
    throw new Error(`Agent bundle dependency is missing: ${match[1]}`);
  }
}
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
if (manifest.name !== "Auralith Agent" || manifest.kind !== "builtin-editor-surface" ||
    manifest.entry !== "reader.html" || !Array.isArray(manifest.capabilityStatus)) {
  throw new Error("Generated Auralith Agent manifest is invalid.");
}
NODE
}

prepare_isolated_sdkjs_build() {
    local destination="$1"
    local source_directory
    log "Creating an isolated SDKJS build root with source-only links."
    mkdir -p "$destination/build"
    for source_directory in configs common vendor word cell slide visio pdf; do
        require_directory "$SDKJS_ROOT/$source_directory"
        ln -s "$SDKJS_ROOT/$source_directory" "$destination/$source_directory"
    done
    cp "$SDKJS_ROOT/build/Gruntfile.js" "$SDKJS_ROOT/build/license.header" \
        "$destination/build/"
    ln -s "$SDKJS_ROOT/build/node_modules" "$destination/build/node_modules"
    require_file "$destination/build/Gruntfile.js"
    require_file "$destination/build/node_modules/.bin/grunt"
}

build_inputs() {
    local agent_build="$1"
    local sdkjs_isolated="$2"

    log "Building the Agent into a temporary output directory."
    (
        cd "$AGENT_ROOT"
        npx vite build --outDir "$agent_build" --emptyOutDir
    )
    rm -f "$agent_build/index.html"
    create_agent_manifest "$agent_build"
    validate_agent_build "$agent_build"

    prepare_isolated_sdkjs_build "$sdkjs_isolated"
    log "Compiling the isolated desktop Word SDK bundle."
    (
        cd "$sdkjs_isolated/build"
        ./node_modules/.bin/grunt compile-word \
            --desktop \
            --level=WHITESPACE_ONLY \
            --formatting=PRETTY_PRINT
    )
    require_file "$sdkjs_isolated/deploy/sdkjs/word/sdk-all-min.js"
    require_file "$sdkjs_isolated/deploy/sdkjs/word/sdk-all.js"
}

inject_host_assets() {
    local staged_app="$1"
    python3 - "$staged_app" <<'PY'
import pathlib
import re
import sys

app = pathlib.Path(sys.argv[1])
web_apps = app / "Contents/Resources/editors/web-apps"
hosts = {
    "documenteditor": "document",
    "spreadsheeteditor": "spreadsheet",
    "presentationeditor": "presentation",
    "pdfeditor": "pdf",
    "visioeditor": "visio",
}
asset_patterns = (
    r"\s*<!--\s*Auralith Agent built-in host\s*-->\s*",
    r"\s*<link\b[^>]*auralith-agent-host\.css[^>]*>\s*",
    r"\s*<script\b[^>]*auralith-agent-host-runtime\.js[^>]*>\s*</script>\s*",
    r"\s*<script\b[^>]*auralith-agent-write-profiles\.js[^>]*>\s*</script>\s*",
    r"\s*<script\b[^>]*auralith-agent-write-executor\.js[^>]*>\s*</script>\s*",
    r"\s*<script\b[^>]*auralith-agent-write-transport\.js[^>]*>\s*</script>\s*",
    r"\s*<script\b[^>]*auralith-agent-host\.js[^>]*>\s*</script>\s*",
)

for editor, kind in hosts.items():
    index = web_apps / f"apps/{editor}/main/index.html"
    if not index.is_file():
        raise SystemExit(f"Missing editor index: {index}")
    html = index.read_text(encoding="utf-8")
    if "app_dev" in html or (kind == "document" and "require(['app'])" not in html):
        raise SystemExit(f"Refusing non-production editor index: {index}")
    for pattern in asset_patterns:
        html = re.sub(pattern, "\n", html, flags=re.IGNORECASE)

    scripts = []
    if kind == "document":
        scripts.append(
            '    <script src="../../common/main/lib/auralith-agent-write-profiles.js"></script>'
        )
    scripts.append(
        '    <script src="../../common/main/lib/auralith-agent-host-runtime.js"></script>'
    )
    if kind == "document":
        scripts.extend(
            [
                '    <script src="../../common/main/lib/auralith-agent-write-executor.js"></script>',
                '    <script src="../../common/main/lib/auralith-agent-write-transport.js"></script>',
            ]
        )
    scripts.append(
        f'    <script src="../../common/main/lib/auralith-agent-host.js" data-auralith-editor="{kind}"></script>'
    )
    injection = "\n".join(
        [
            "    <!-- Auralith Agent built-in host -->",
            '    <link rel="stylesheet" type="text/css" href="../../common/main/lib/auralith-agent-host.css">',
            *scripts,
        ]
    )
    closing_body = html.lower().rfind("</body>")
    if closing_body < 0:
        raise SystemExit(f"Cannot find </body> in {index}")
    html = f"{html[:closing_body].rstrip()}\n{injection}\n{html[closing_body:]}"
    index.write_text(html, encoding="utf-8")
PY
}

assemble_staged_app() {
    local staged_app="$1"
    local agent_build="$2"
    local sdkjs_isolated="$3"
    local common_main="$staged_app/Contents/Resources/editors/web-apps/apps/common/main"
    local agent_target="$common_main/auralith-agent"
    local word_target="$staged_app/Contents/Resources/editors/sdkjs/word"

    log "Cloning the installed test bundle into staging."
    ditto "$TARGET_APP" "$staged_app"
    rm -rf "$agent_target"
    ditto "$agent_build" "$agent_target"
    cp "$HOST_RUNTIME_JS" "$common_main/lib/auralith-agent-host-runtime.js"
    cp "$HOST_JS" "$common_main/lib/auralith-agent-host.js"
    cp "$HOST_CSS" "$common_main/lib/auralith-agent-host.css"
    cp "$HOST_TOKENS_CSS" "$common_main/lib/auralith-agent-host-tokens.css"
    cp "$HOST_BASE_LAYOUT_CSS" "$common_main/lib/auralith-agent-host-base-layout.css"
    cp "$HOST_WRITE_APPROVAL_CSS" "$common_main/lib/auralith-agent-host-write-approval.css"
    cp "$WRITE_PROFILES_JS" "$common_main/lib/auralith-agent-write-profiles.js"
    cp "$WRITE_EXECUTOR_JS" "$common_main/lib/auralith-agent-write-executor.js"
    cp "$WRITE_TRANSPORT_JS" "$common_main/lib/auralith-agent-write-transport.js"
    cp "$sdkjs_isolated/deploy/sdkjs/word/sdk-all-min.js" "$word_target/sdk-all-min.js"
    cp "$sdkjs_isolated/deploy/sdkjs/word/sdk-all.js" "$word_target/sdk-all.js"
    inject_host_assets "$staged_app"
}

verify_index_order() {
    local app_path="$1"
    python3 - "$app_path" <<'PY'
import pathlib
import sys

app = pathlib.Path(sys.argv[1])
web_apps = app / "Contents/Resources/editors/web-apps/apps"
editors = {
    "documenteditor": "document",
    "spreadsheeteditor": "spreadsheet",
    "presentationeditor": "presentation",
    "pdfeditor": "pdf",
    "visioeditor": "visio",
}

for editor, kind in editors.items():
    index = web_apps / f"{editor}/main/index.html"
    html = index.read_text(encoding="utf-8")
    if "app_dev" in html or (kind == "document" and "require(['app'])" not in html):
        raise SystemExit(f"Non-production entry detected: {index}")
    counts = {
        "style": html.count("auralith-agent-host.css"),
        "runtime": html.count("auralith-agent-host-runtime.js"),
        "profiles": html.count("auralith-agent-write-profiles.js"),
        "executor": html.count("auralith-agent-write-executor.js"),
        "transport": html.count("auralith-agent-write-transport.js"),
        "host": html.count("auralith-agent-host.js"),
    }
    if counts["style"] != 1 or counts["runtime"] != 1 or counts["host"] != 1:
        raise SystemExit(f"Host injection is not unique in {index}: {counts}")
    runtime = html.index("auralith-agent-host-runtime.js")
    if kind == "document":
        if counts["profiles"] != 1 or counts["executor"] != 1 or counts["transport"] != 1:
            raise SystemExit(f"Document write transport injection is invalid in {index}: {counts}")
        profiles = html.index("auralith-agent-write-profiles.js")
        executor = html.index("auralith-agent-write-executor.js")
        transport = html.index("auralith-agent-write-transport.js")
        host = html.index("auralith-agent-host.js")
        if not profiles < runtime < executor < transport < host:
            raise SystemExit(
                f"Expected profiles < runtime < executor < transport < host in {index}"
            )
    elif counts["profiles"] or counts["executor"] or counts["transport"]:
        raise SystemExit(f"Write transport leaked into non-DOCX editor index: {index}")
    elif not runtime < html.index("auralith-agent-host.js"):
        raise SystemExit(f"Expected runtime < host in {index}")
PY
}

verify_bundle_shape() {
    local min_bundle="$1"
    local full_bundle="$2"
    local min_size
    local full_size
    min_size="$(stat -f '%z' "$min_bundle")"
    full_size="$(stat -f '%z' "$full_bundle")"
    (( min_size >= 2500000 )) ||
        die "Word sdk-all-min.js is too small for the required desktop whitespace-only build ($min_size bytes)."
    (( full_size >= 15000000 )) ||
        die "Word sdk-all.js is too small for the required desktop whitespace-only build ($full_size bytes)."
    (( min_size < full_size )) ||
        die "Word SDK bundle sizes are inconsistent."
}

verify_staged_app() {
    local app_path="$1"
    local agent_build="$2"
    local sdkjs_isolated="$3"
    local common_main="$app_path/Contents/Resources/editors/web-apps/apps/common/main"
    local word_target="$app_path/Contents/Resources/editors/sdkjs/word"
    local actual_bundle_id

    actual_bundle_id="$(bundle_identifier "$app_path")" ||
        die "Unable to read staged bundle identifier."
    [[ "$actual_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] ||
        die "Staged bundle id changed unexpectedly: $actual_bundle_id"
    verify_production_entry "$app_path"
    verify_index_order "$app_path"
    validate_agent_build "$common_main/auralith-agent"
    diff -qr "$agent_build" "$common_main/auralith-agent" >/dev/null ||
        die "Installed Agent tree differs from the temporary Vite build."
    cmp -s "$HOST_RUNTIME_JS" "$common_main/lib/auralith-agent-host-runtime.js" ||
        die "Host runtime JS copy verification failed."
    cmp -s "$HOST_JS" "$common_main/lib/auralith-agent-host.js" ||
        die "Host JS copy verification failed."
    cmp -s "$HOST_CSS" "$common_main/lib/auralith-agent-host.css" ||
        die "Host CSS copy verification failed."
    cmp -s "$HOST_TOKENS_CSS" "$common_main/lib/auralith-agent-host-tokens.css" ||
        die "Host token CSS copy verification failed."
    cmp -s "$HOST_BASE_LAYOUT_CSS" "$common_main/lib/auralith-agent-host-base-layout.css" ||
        die "Host base layout CSS copy verification failed."
    cmp -s "$HOST_WRITE_APPROVAL_CSS" "$common_main/lib/auralith-agent-host-write-approval.css" ||
        die "Host write approval CSS copy verification failed."
    cmp -s "$WRITE_PROFILES_JS" "$common_main/lib/auralith-agent-write-profiles.js" ||
        die "Write profiles copy verification failed."
    cmp -s "$WRITE_EXECUTOR_JS" "$common_main/lib/auralith-agent-write-executor.js" ||
        die "Write executor copy verification failed."
    cmp -s "$WRITE_TRANSPORT_JS" "$common_main/lib/auralith-agent-write-transport.js" ||
        die "Write transport copy verification failed."
    cmp -s "$sdkjs_isolated/deploy/sdkjs/word/sdk-all-min.js" "$word_target/sdk-all-min.js" ||
        die "Word sdk-all-min.js copy verification failed."
    cmp -s "$sdkjs_isolated/deploy/sdkjs/word/sdk-all.js" "$word_target/sdk-all.js" ||
        die "Word sdk-all.js copy verification failed."
    verify_bundle_shape "$word_target/sdk-all-min.js" "$word_target/sdk-all.js"
}

sign_and_verify_stage() {
    local app_path="$1"
    local payload_manifest="$2"
    local sign_log="$3"
    log "Applying a deep ad-hoc signature to the staged bundle."
    codesign --force --deep --sign - --timestamp=none "$app_path" \
        >"$sign_log" 2>&1
    codesign --verify --deep --strict --verbose=2 "$app_path" \
        >>"$sign_log" 2>&1
    verify_payload_manifest "$app_path" "$payload_manifest"
}

prepare_backup() {
    local backup_destination="$1"
    local backup_manifest="$2"
    local backup_log="$3"
    local backup_staging="$TEMP_ROOT/backup.app"

    log "Creating the verified timestamped rollback copy."
    generate_payload_manifest "$TARGET_APP" "$backup_manifest"
    ditto "$TARGET_APP" "$backup_staging"
    verify_payload_manifest "$backup_staging" "$backup_manifest"
    codesign --verify --deep --strict --verbose=2 "$backup_staging" \
        >"$backup_log" 2>&1
    mkdir -p "$ROLLBACK_ROOT"
    [[ ! -e "$backup_destination" ]] ||
        die "Rollback destination already exists: $backup_destination"
    mv "$backup_staging" "$backup_destination"
}

restore_after_failed_swap() {
    local failed_destination="$1"
    warn "Post-install verification failed; restoring the original test app."
    TRANSACTION_ACTIVE=0
    if [[ ! -e "$ORIGINAL_SWAP_APP" ]]; then
        if [[ -e "$TARGET_APP" ]]; then
            log "The original app was never moved; no rollback rename is needed."
            return 0
        fi
        PRESERVE_TEMP=1
        warn "Neither the target nor the transaction copy is present. Restore from the timestamped backup."
        return 1
    fi
    if [[ -e "$TARGET_APP" ]]; then
        if [[ -e "$failed_destination" ]]; then
            failed_destination="${failed_destination%.app}-$$.app"
        fi
        if ! mv "$TARGET_APP" "$failed_destination"; then
            PRESERVE_TEMP=1
            warn "Could not evacuate the failed staged app; the original remains at $ORIGINAL_SWAP_APP"
            return 1
        fi
    fi
    if ! mv "$ORIGINAL_SWAP_APP" "$TARGET_APP"; then
        PRESERVE_TEMP=1
        warn "Automatic rollback rename failed. Restore from the timestamped rollback copy immediately."
        return 1
    fi
    return 0
}

cleanup() {
    local exit_code=$?
    if (( TRANSACTION_ACTIVE == 1 )); then
        if ! restore_after_failed_swap "$ROLLBACK_ROOT/failed-transaction-$(date +%Y%m%d-%H%M%S).app"; then
            exit_code=2
        fi
    fi
    if (( PRESERVE_TEMP == 1 )); then
        warn "Preserving transaction files for manual recovery: $TEMP_ROOT"
    elif [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
        rm -rf "$TEMP_ROOT"
    fi
    trap - EXIT
    exit "$exit_code"
}
trap cleanup EXIT

run_preflight() {
    require_command awk
    require_command cmp
    require_command codesign
    require_command cp
    require_command diff
    require_command ditto
    require_command grep
    require_command ln
    require_command lsof
    require_command mkdir
    require_command mktemp
    require_command mv
    require_command ps
    require_command python3
    require_command rm
    require_command sort
    require_command stat
    assert_fixed_paths
    configure_node20
    require_command node
    require_command npx
    assert_target_app
    assert_not_running_for_install
    assert_source_inputs
    verify_production_entry "$TARGET_APP"
    codesign --verify --deep --strict --verbose=2 "$TARGET_APP" >/dev/null 2>&1 ||
        die "The existing test application has an invalid signature."
    log "Source inputs, production entry, bundle identity, and current signature are valid."
}

run_preflight

if [[ "$MODE" == "dry-run" ]]; then
    log "Dry run complete. No build output, backup, or application file was written."
    log "Use --stage-only for a full isolated build/sign verification or --install for the explicit install transaction."
    exit 0
fi

TEMP_ROOT="$(mktemp -d "$USER_APPLICATIONS/.auralith-test-install.XXXXXX")"
STAGED_APP="$TEMP_ROOT/Auralith_Editer Test.app"
ORIGINAL_SWAP_APP="$TEMP_ROOT/original.app"
readonly AGENT_BUILD="$TEMP_ROOT/agent-build"
readonly SDKJS_ISOLATED="$TEMP_ROOT/sdkjs"
readonly PAYLOAD_MANIFEST="$TEMP_ROOT/install-payload.sha256"
readonly SIGN_LOG="$TEMP_ROOT/codesign-stage.log"

build_inputs "$AGENT_BUILD" "$SDKJS_ISOLATED"
assemble_staged_app "$STAGED_APP" "$AGENT_BUILD" "$SDKJS_ISOLATED"
verify_staged_app "$STAGED_APP" "$AGENT_BUILD" "$SDKJS_ISOLATED"
generate_payload_manifest "$STAGED_APP" "$PAYLOAD_MANIFEST"
sign_and_verify_stage "$STAGED_APP" "$PAYLOAD_MANIFEST" "$SIGN_LOG"
verify_staged_app "$STAGED_APP" "$AGENT_BUILD" "$SDKJS_ISOLATED"

if [[ "$MODE" == "stage-only" ]]; then
    log "Stage-only verification complete. The installed application was not modified."
    exit 0
fi

readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DESTINATION="$ROLLBACK_ROOT/$TIMESTAMP"
readonly BACKUP_MANIFEST="$TEMP_ROOT/before-payload.sha256"
readonly BACKUP_SIGN_LOG="$TEMP_ROOT/codesign-before.log"
prepare_backup "$BACKUP_DESTINATION" "$BACKUP_MANIFEST" "$BACKUP_SIGN_LOG"
cp "$BACKUP_MANIFEST" "$BACKUP_DESTINATION/before-payload.sha256"
cp "$BACKUP_SIGN_LOG" "$BACKUP_DESTINATION/codesign-verify-before.txt"
cp "$PAYLOAD_MANIFEST" "$BACKUP_DESTINATION/install-payload.sha256"
cp "$SIGN_LOG" "$BACKUP_DESTINATION/codesign-stage.txt"

log "Replacing the dedicated test app with same-volume atomic renames."
TRANSACTION_ACTIVE=1
mv "$TARGET_APP" "$ORIGINAL_SWAP_APP"
if ! mv "$STAGED_APP" "$TARGET_APP"; then
    restore_after_failed_swap "$ROLLBACK_ROOT/failed-swap-$TIMESTAMP.app" ||
        die "The staged-app move and automatic rollback both failed; transaction files were preserved."
    die "Unable to move the verified staged app into place."
fi

if ! (
    verify_payload_manifest "$TARGET_APP" "$PAYLOAD_MANIFEST" &&
    verify_staged_app "$TARGET_APP" "$AGENT_BUILD" "$SDKJS_ISOLATED" &&
    codesign --verify --deep --strict --verbose=2 "$TARGET_APP"
); then
    restore_after_failed_swap "$ROLLBACK_ROOT/failed-install-$TIMESTAMP.app" ||
        die "Post-install verification and automatic rollback both failed; transaction files were preserved."
    die "The installed app failed post-swap verification; the original app was restored."
fi
TRANSACTION_ACTIVE=0
cp "$PAYLOAD_MANIFEST" "$BACKUP_DESTINATION/installed-payload.sha256"
codesign --verify --deep --strict --verbose=2 "$TARGET_APP" \
    >"$BACKUP_DESTINATION/codesign-verify-after.txt" 2>&1
log "Installation complete: $TARGET_APP"
log "Rollback copy: $BACKUP_DESTINATION"
