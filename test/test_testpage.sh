#!/bin/bash
# Tests for tools/make-testpage.py. No hardware, no root.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/../tools/make-testpage.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PY="$(command -v python3 || true)"
PASS=0; FAIL=0
RED=$'\033[31m'; GRN=$'\033[32m'; OFF=$'\033[0m'
ok()   { PASS=$((PASS+1)); printf '  %sok%s   %s\n' "$GRN" "$OFF" "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  %sFAIL%s %s\n        %s\n' "$RED" "$OFF" "$1" "$2"; }

[ -n "$PY" ] || { nope "python3 present" "not on PATH"; echo "passed: 0 failed: 1"; exit 1; }

echo "== licence header =="
grep -q 'SPDX-License-Identifier: GPL-2.0-only' "$TOOL" \
    && ok "carries an SPDX header" || nope "carries an SPDX header" "missing"

echo "== each focus mode produces a well-formed PDF =="
for focus in margin quality bleed; do
    out="$TMP/$focus.pdf"
    if ! "$PY" "$TOOL" -o "$out" --focus "$focus" --label "test $focus" >/dev/null 2>&1; then
        nope "--focus $focus runs" "non-zero exit"
        continue
    fi
    [ "$(head -c 5 "$out")" = "%PDF-" ] \
        && ok "--focus $focus emits a PDF" || nope "--focus $focus emits a PDF" "bad magic"
    LC_ALL=C grep -qa '%%EOF' "$out" \
        && ok "--focus $focus is terminated" || nope "--focus $focus is terminated" "no %%EOF"

    # startxref must point at the byte where "xref" actually begins. A wrong
    # offset is the classic hand-rolled-PDF bug and readers hide it by silently
    # rebuilding the table, so nothing else would catch it.
    off=$(LC_ALL=C tail -c 60 "$out" | grep -a -A1 startxref | tail -1 | tr -cd '0-9')
    if [ -n "$off" ] && [ "$(dd if="$out" bs=1 skip="$off" count=4 2>/dev/null)" = "xref" ]; then
        ok "--focus $focus has a correct xref offset"
    else
        nope "--focus $focus has a correct xref offset" "startxref=${off:-none}"
    fi
done

echo "== page sizes =="
for size in A4 Letter A6; do
    "$PY" "$TOOL" -o "$TMP/$size.pdf" --size "$size" >/dev/null 2>&1 \
        && ok "--size $size works" || nope "--size $size works" "non-zero exit"
done
LC_ALL=C grep -qa 'MediaBox \[0 0 595' "$TMP/A4.pdf" \
    && ok "A4 MediaBox is 595 pt wide" \
    || nope "A4 MediaBox is 595 pt wide" "$(LC_ALL=C grep -ao 'MediaBox[^]]*]' "$TMP/A4.pdf" | head -1)"
LC_ALL=C grep -qa 'MediaBox \[0 0 612' "$TMP/Letter.pdf" \
    && ok "Letter MediaBox is 612 pt wide" \
    || nope "Letter MediaBox is 612 pt wide" "wrong MediaBox"

echo "== the label reaches the page =="
"$PY" "$TOOL" -o "$TMP/lbl.pdf" --label "UNIQUE-MARKER-123" >/dev/null 2>&1
LC_ALL=C grep -qa 'UNIQUE-MARKER-123' "$TMP/lbl.pdf" \
    && ok "--label is printed on the sheet" \
    || nope "--label is printed on the sheet" "marker not in the content stream"

echo "== bad input is rejected =="
"$PY" "$TOOL" -o "$TMP/x.pdf" --size NOPE >/dev/null 2>&1 \
    && nope "unknown --size is rejected" "exited 0" || ok "unknown --size is rejected"
"$PY" "$TOOL" -o "$TMP/x.pdf" --focus NOPE >/dev/null 2>&1 \
    && nope "unknown --focus is rejected" "exited 0" || ok "unknown --focus is rejected"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
