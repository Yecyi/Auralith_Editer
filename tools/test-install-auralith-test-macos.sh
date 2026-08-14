#!/usr/bin/env bash

# Focused, non-installing regression harness for the macOS rollback layout.
# It sources the installer's real backup/recovery functions with an internal,
# test-only Applications root and minimal ad-hoc-signed fixture apps. The fixed
# user application is never read, stopped, replaced, or launched.

set -Eeuo pipefail
IFS=$'\n\t'

readonly HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly INSTALLER_PATH="$HARNESS_DIR/install-auralith-test-macos.sh"
readonly TEST_PARENT="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
TEST_ROOT="$(mktemp -d "$TEST_PARENT/auralith-rollback-layout.XXXXXX")"

cleanup_fixture() {
    case "$TEST_ROOT" in
        "$TEST_PARENT"/auralith-rollback-layout.*)
            [[ ! -e "$TEST_ROOT" || -d "$TEST_ROOT" ]] || return 1
            rm -rf -- "$TEST_ROOT"
            ;;
        *)
            printf 'Refusing unsafe fixture cleanup path: %s\n' "$TEST_ROOT" >&2
            return 1
            ;;
    esac
}
trap cleanup_fixture EXIT

fail() {
    printf '[rollback-layout-test] ERROR: %s\n' "$*" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || fail "Expected file: $1"
}

assert_directory() {
    [[ -d "$1" ]] || fail "Expected directory: $1"
}

create_fixture_app() {
    local app_path="$1"
    local marker="$2"

    mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
    cp /usr/bin/true "$app_path/Contents/MacOS/AuralithFixture"
    printf '%s\n' "$marker" >"$app_path/Contents/Resources/fixture-marker.txt"
    python3 - "$app_path/Contents/Info.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as stream:
    plistlib.dump(
        {
            "CFBundleExecutable": "AuralithFixture",
            "CFBundleIdentifier": "com.auralith.editer.test",
            "CFBundleName": "Auralith_Editer Test",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        },
        stream,
    )
PY
    codesign --force --deep --sign - --timestamp=none "$app_path" >/dev/null 2>&1
    codesign --verify --deep --strict --verbose=2 "$app_path" >/dev/null 2>&1
}

(( $# == 0 )) || fail "This harness does not accept arguments."
readonly FIXTURE_USER_APPLICATIONS="$TEST_ROOT/user-applications"
mkdir -p "$FIXTURE_USER_APPLICATIONS"
create_fixture_app "$FIXTURE_USER_APPLICATIONS/Auralith_Editer Test.app" original

export AURALITH_INSTALL_LIBRARY_ONLY=1
export AURALITH_INSTALL_TEST_USER_APPLICATIONS="$FIXTURE_USER_APPLICATIONS"
# shellcheck source=install-auralith-test-macos.sh
source "$INSTALLER_PATH"
unset AURALITH_INSTALL_LIBRARY_ONLY
unset AURALITH_INSTALL_TEST_USER_APPLICATIONS

TEMP_ROOT="$TEST_ROOT/transaction"
mkdir "$TEMP_ROOT"
readonly FIXTURE_INSTALL_MANIFEST="$TEMP_ROOT/install-payload.sha256"
readonly FIXTURE_STAGE_LOG="$TEMP_ROOT/codesign-stage.log"
readonly FIXTURE_BACKUP_MANIFEST="$TEMP_ROOT/before-payload.sha256"
readonly FIXTURE_BACKUP_LOG="$TEMP_ROOT/codesign-before.log"
readonly FIXTURE_TIMESTAMP="20990101-000000"
readonly FIXTURE_CONTAINER="$ROLLBACK_ROOT/$FIXTURE_TIMESTAMP"
readonly FIXTURE_BACKUP_APP="$FIXTURE_CONTAINER/$ROLLBACK_APP_NAME"
readonly FIXTURE_RECEIPTS="$FIXTURE_CONTAINER/$ROLLBACK_RECEIPTS_NAME"

generate_payload_manifest "$TARGET_APP" "$FIXTURE_INSTALL_MANIFEST"
printf 'fixture staged application passed strict deep-signature verification\n' \
    >"$FIXTURE_STAGE_LOG"
prepare_backup \
    "$FIXTURE_CONTAINER" \
    "$FIXTURE_BACKUP_MANIFEST" \
    "$FIXTURE_BACKUP_LOG" \
    "$FIXTURE_INSTALL_MANIFEST" \
    "$FIXTURE_STAGE_LOG"

assert_directory "$FIXTURE_CONTAINER"
assert_directory "$FIXTURE_BACKUP_APP"
assert_directory "$FIXTURE_RECEIPTS"
for receipt in \
    before-payload.sha256 \
    codesign-verify-before.txt \
    install-payload.sha256 \
    codesign-stage.txt; do
    assert_file "$FIXTURE_RECEIPTS/$receipt"
    [[ ! -e "$FIXTURE_BACKUP_APP/$receipt" ]] ||
        fail "Receipt leaked into the signed application root: $receipt"
done
codesign --verify --deep --strict --verbose=2 "$FIXTURE_BACKUP_APP" \
    >/dev/null 2>&1
verify_rollback_container "$FIXTURE_CONTAINER" prepared

cp "$FIXTURE_INSTALL_MANIFEST" \
    "$FIXTURE_RECEIPTS/installed-payload.sha256"
codesign --verify --deep --strict --verbose=2 "$TARGET_APP" \
    >"$FIXTURE_RECEIPTS/codesign-verify-after.txt" 2>&1
verify_rollback_container "$FIXTURE_CONTAINER" complete

ORIGINAL_SWAP_APP="$TEMP_ROOT/original.app"
mv "$TARGET_APP" "$ORIGINAL_SWAP_APP"
create_fixture_app "$TARGET_APP" failed
TRANSACTION_ACTIVE=1
readonly FAILED_CONTAINER="$ROLLBACK_ROOT/failed-install-$FIXTURE_TIMESTAMP"
restore_after_failed_swap "$FAILED_CONTAINER"

[[ "$TRANSACTION_ACTIVE" == "0" ]] ||
    fail "Recovery did not close the transaction."
assert_file "$TARGET_APP/Contents/Resources/fixture-marker.txt"
grep -Fxq original "$TARGET_APP/Contents/Resources/fixture-marker.txt" ||
    fail "Recovery did not restore the original application."
assert_directory "$FAILED_CONTAINER/$ROLLBACK_APP_NAME"
grep -Fxq failed \
    "$FAILED_CONTAINER/$ROLLBACK_APP_NAME/Contents/Resources/fixture-marker.txt" ||
    fail "Failed candidate was not preserved in its application wrapper."
[[ ! -e "$FAILED_CONTAINER/Contents" ]] ||
    fail "Failed candidate leaked its Contents directory into the container root."
codesign --verify --deep --strict --verbose=2 "$TARGET_APP" >/dev/null 2>&1
codesign --verify --deep --strict --verbose=2 \
    "$FAILED_CONTAINER/$ROLLBACK_APP_NAME" >/dev/null 2>&1

printf '[rollback-layout-test] PASS: signed backup, sibling receipts, and automatic recovery layout verified.\n'
