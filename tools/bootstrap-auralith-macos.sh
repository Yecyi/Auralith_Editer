#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$workspace_root"

prepare_submodule() {
    local module_path="$1"
    local expected_commit="$2"
    local fork_url="$3"
    local upstream_url="$4"
    local branch_name="auralith/master"

    git submodule sync -- "$module_path"
    git submodule update --init --checkout --depth 1 -- "$module_path"

    if [[ "$(git -C "$module_path" rev-parse HEAD)" != "$expected_commit" ]]; then
        echo "$module_path does not match the commit pinned by Auralith_Editer." >&2
        exit 1
    fi

    if [[ -n "$(git -C "$module_path" status --porcelain)" ]]; then
        echo "Refusing to modify a dirty submodule: $module_path" >&2
        exit 1
    fi

    git -C "$module_path" remote set-url origin "$fork_url"
    if git -C "$module_path" remote get-url upstream >/dev/null 2>&1; then
        git -C "$module_path" remote set-url upstream "$upstream_url"
    else
        git -C "$module_path" remote add upstream "$upstream_url"
    fi

    if ! git -C "$module_path" show-ref --verify --quiet \
        "refs/remotes/origin/$branch_name" ||
        [[ "$(git -C "$module_path" rev-parse "origin/$branch_name")" != "$expected_commit" ]]; then
        git -C "$module_path" fetch --depth 1 origin \
            "refs/heads/$branch_name:refs/remotes/origin/$branch_name"
    fi

    if [[ "$(git -C "$module_path" rev-parse "origin/$branch_name")" != "$expected_commit" ]]; then
        echo "Remote $module_path/$branch_name no longer matches the pinned commit." >&2
        exit 1
    fi

    if git -C "$module_path" show-ref --verify --quiet "refs/heads/$branch_name"; then
        git -C "$module_path" switch "$branch_name"
        if [[ "$(git -C "$module_path" rev-parse HEAD)" != "$expected_commit" ]]; then
            echo "Existing $module_path/$branch_name has local work; it was not reset." >&2
            exit 1
        fi
    else
        git -C "$module_path" switch -c "$branch_name" "$expected_commit"
    fi

    git -C "$module_path" branch \
        --set-upstream-to="origin/$branch_name" "$branch_name" >/dev/null
    echo "Ready: $module_path at $(git -C "$module_path" rev-parse --short HEAD)"
}

prepare_submodule \
    "desktop-sdk" \
    "25934801e6693529d4a05366cda5e5f01b68cfc0" \
    "https://github.com/Yecyi/desktop-sdk.git" \
    "https://github.com/ONLYOFFICE/desktop-sdk.git"

prepare_submodule \
    "web-apps" \
    "8c6ba0daf5f1d1916ceee209379ad013be7054e4" \
    "https://github.com/Yecyi/web-apps.git" \
    "https://github.com/ONLYOFFICE/web-apps-pro.git"

prepare_submodule \
    "sdkjs" \
    "8c99623eccb957118952dbd49abc20b06726443f" \
    "https://github.com/Yecyi/sdkjs.git" \
    "https://github.com/ONLYOFFICE/sdkjs.git"

echo "Auralith_Editer is ready for macOS development."
