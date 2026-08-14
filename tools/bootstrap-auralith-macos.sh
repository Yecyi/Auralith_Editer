#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$workspace_root"

prepare_submodule() {
    local module_path="$1"
    local expected_commit="$2"
    local fork_url="$3"
    local upstream_url="$4"
    local branch_name="codex/ai-native-office-p0"

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

    local branch_refspec="+refs/heads/$branch_name:refs/remotes/origin/$branch_name"
    if ! git -C "$module_path" config --get-all remote.origin.fetch |
        grep -Fqx "$branch_refspec"; then
        git -C "$module_path" config --add remote.origin.fetch "$branch_refspec"
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
    "1fc59ff61cc3e6dde6d8de9e6cea93951830eba6" \
    "https://github.com/Yecyi/desktop-sdk.git" \
    "https://github.com/ONLYOFFICE/desktop-sdk.git"

prepare_submodule \
    "web-apps" \
    "fa600a69cabc868efd4e28a3fb502ee89a82bfcc" \
    "https://github.com/Yecyi/web-apps.git" \
    "https://github.com/ONLYOFFICE/web-apps-pro.git"

prepare_submodule \
    "sdkjs" \
    "4ab23fb5ea6d5a10806615959d4dc26b3b4db2b3" \
    "https://github.com/Yecyi/sdkjs.git" \
    "https://github.com/ONLYOFFICE/sdkjs.git"

echo "Auralith_Editer is ready for macOS development."
