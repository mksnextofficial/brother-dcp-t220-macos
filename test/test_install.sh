#!/bin/bash
# Dry-run tests for install.sh. No hardware, no root, no system change.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$HERE/../install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test/lib.sh
. "$HERE/lib.sh"

# Fingerprint the install directory BEFORE anything runs. Asserting the
# directory is simply absent would only be valid on a machine where the driver
# has never been installed, and would then fail for the wrong reason on one
# where it is legitimately in use. What matters is that a dry run changes
# nothing, either way.
INSTALL_DIR="/Library/Printers/BrotherPWG"
fingerprint() {
    if [ -e "$INSTALL_DIR" ]; then ls -laR "$INSTALL_DIR" 2>&1
    else echo "absent"; fi
}
fingerprint > "$TMP/dir.before"

echo "== dry run with an explicit model needs no printer and no root =="
"$INSTALL" --dry-run --model DCP-T220 > "$TMP/out.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && ok "exits 0" || nope "exits 0" "rc=$rc: $(tail -5 "$TMP/out.txt")"
grep -q 'DCP-T220' "$TMP/out.txt" && ok "names the model" \
    || nope "names the model" "$(cat "$TMP/out.txt")"
grep -qi 'verified' "$TMP/out.txt" && ok "reports the model's status" \
    || nope "reports the model's status" "no status line"
grep -q '/Library/Printers/BrotherPWG' "$TMP/out.txt" && ok "names the install path" \
    || nope "names the install path" "install path not shown"

echo "== dry run makes no system change =="
fingerprint > "$TMP/dir.after"
if diff -q "$TMP/dir.before" "$TMP/dir.after" >/dev/null; then
    if [ "$(cat "$TMP/dir.before")" = "absent" ]; then
        ok "install dir still absent"
    else
        ok "install dir unchanged (driver is installed on this machine)"
    fi
else
    nope "install dir unchanged" "$(diff "$TMP/dir.before" "$TMP/dir.after" | head -5)"
fi

echo "== an unknown model warns loudly =="
"$INSTALL" --dry-run --model DCP-T999-NOSUCH > "$TMP/unk.txt" 2>&1
grep -qi 'unverified' "$TMP/unk.txt" && ok "warns that the model is unverified" \
    || nope "warns that the model is unverified" "$(cat "$TMP/unk.txt")"
grep -qi 'borderless' "$TMP/unk.txt" && ok "explains what is withheld and why" \
    || nope "explains what is withheld and why" "no mention of borderless"
grep -qi 'contributing-a-model' "$TMP/unk.txt" && ok "points at the contribution guide" \
    || nope "points at the contribution guide" "no pointer"

echo "== --emit-ppd writes only a PPD to stdout =="
"$INSTALL" --dry-run --model DCP-T220 --emit-ppd > "$TMP/dry.ppd" 2>/dev/null
head -1 "$TMP/dry.ppd" | grep -q '^\*PPD-Adobe' && ok "stdout starts with the PPD header" \
    || nope "stdout starts with the PPD header" "got: $(head -1 "$TMP/dry.ppd")"
grep -q '/Library/Printers/BrotherPWG/rastertobrotherpjl' "$TMP/dry.ppd" \
    && ok "PPD points at the install path, not the repo" \
    || nope "PPD points at the install path, not the repo" "wrong cupsFilter path"

CTP="$(command -v cupstestppd || true)"
if [ -n "$CTP" ]; then
    "$CTP" "$TMP/dry.ppd" 2>&1 | grep -E '\*\*FAIL\*\*' | grep -vE 'cupsFilter file' \
        > "$TMP/ctp.txt" || true
    [ ! -s "$TMP/ctp.txt" ] && ok "cupstestppd accepts the PPD install.sh would write" \
        || nope "cupstestppd accepts the PPD install.sh would write" "$(head -5 "$TMP/ctp.txt")"
else
    skip "cupstestppd not on PATH -- PPD validation not run here"
fi

echo "== usage errors =="
assert_status 4 "unknown flag exits 4" "$INSTALL" --nonsense
"$INSTALL" --help 2>&1 | grep -qi 'dry-run' && ok "--help documents --dry-run" \
    || nope "--help documents --dry-run" "not mentioned"

echo "== queue name is configurable =="
"$INSTALL" --dry-run --model DCP-T220 --queue MyPrinter > "$TMP/q.txt" 2>&1
grep -q 'MyPrinter' "$TMP/q.txt" && ok "--queue is honoured" \
    || nope "--queue is honoured" "queue name not shown"

summary
