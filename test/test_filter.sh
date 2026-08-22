#!/bin/bash
# Unit tests for filter/rastertobrotherpjl. No hardware, no root.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$HERE/../filter/rastertobrotherpjl"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
RED=$'\033[31m'; GRN=$'\033[32m'; OFF=$'\033[0m'

# A stand-in raster payload. The filter never parses it, so real PWG content is
# not needed -- but it must contain no 0x1b, or the ESC-injection test below
# cannot tell a stray UEL from payload data.
{
    printf 'RaS2'
    i=0; while [ $i -lt 32 ]; do
        printf 'PWGRASTERPAYLOAD0123456789abcdef'
        i=$((i+1))
    done
} > "$TMP/raster.bin"

run() {   # run <options>
    "$FILTER" 42 testuser "test job" 1 "$1" < "$TMP/raster.bin" \
        > "$TMP/out.bin" 2> "$TMP/err.txt"
}

ok()   { PASS=$((PASS+1)); printf '  %sok%s   %s\n' "$GRN" "$OFF" "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  %sFAIL%s %s\n        %s\n' "$RED" "$OFF" "$1" "$2"; }

assert_has() {   # <description> <literal>
    if LC_ALL=C grep -aqF -- "$2" "$TMP/out.bin"; then ok "$1"
    else nope "$1" "expected to find: $2"; fi
}
assert_lacks() { # <description> <literal>
    if LC_ALL=C grep -aqF -- "$2" "$TMP/out.bin"; then
        nope "$1" "should NOT contain: $2"
    else ok "$1"; fi
}

# Extract exactly the bytes the filter placed between the language switch and
# the closing UEL. That is the raster it forwarded.
extract_payload() {
    perl -e '
        local $/; open(my $f, "<:raw", $ARGV[0]) or exit 2; my $d = <$f>;
        my $m   = "\@PJL ENTER LANGUAGE=PWGRASTER\r\n";
        my $uel = "\x1b%-12345X";
        my $i = index($d, $m);                exit 3 if $i < 0;
        my $s = $i + length($m);
        my $j = index($d, $uel, $s);          exit 4 if $j < 0;
        print substr($d, $s, $j - $s);
    ' "$1"
}

echo "== structure =="
run "PageSize=A4"
assert_has   "emits the PWGRASTER language switch" "@PJL ENTER LANGUAGE=PWGRASTER"
assert_has   "emits a JOB line"                    "@PJL JOB NAME="
assert_has   "emits an EOJ line"                   "@PJL EOJ NAME="
assert_lacks "never writes NVRAM"                  "@PJL DEFAULT"

if [ "$(head -c 9 "$TMP/out.bin" | od -An -c | tr -d ' \n')" = "033%-12345X" ]; then
    ok "starts with the UEL"
else
    nope "starts with the UEL" "got: $(head -c 9 "$TMP/out.bin" | od -An -c)"
fi

echo "== raster passthrough =="
if extract_payload "$TMP/out.bin" > "$TMP/payload.bin" 2>/dev/null \
   && cmp -s "$TMP/payload.bin" "$TMP/raster.bin"; then
    ok "raster bytes pass through byte for byte"
else
    nope "raster bytes pass through byte for byte" \
         "in=$(wc -c < "$TMP/raster.bin") out=$(wc -c < "$TMP/payload.bin" 2>/dev/null || echo 0)"
fi

echo "== reads from argv[6] as well as stdin =="
"$FILTER" 42 testuser "file mode" 1 "" "$TMP/raster.bin" > "$TMP/out.bin" 2>/dev/null
if extract_payload "$TMP/out.bin" > "$TMP/payload.bin" 2>/dev/null \
   && cmp -s "$TMP/payload.bin" "$TMP/raster.bin"; then
    ok "file argument produces the same stream"
else
    nope "file argument produces the same stream" "payload mismatch"
fi

echo "== paper mapping =="
run "PageSize=A4";        assert_has "A4 -> PAPER=A4"               "@PJL SET PAPER=A4"
run "PageSize=Letter";    assert_has "Letter -> PAPER=LETTER"       "@PJL SET PAPER=LETTER"
run "PageSize=Legal";     assert_has "Legal -> PAPER=LEGAL"         "@PJL SET PAPER=LEGAL"
run "PageSize=Executive"; assert_has "Executive -> PAPER=EXECUTIVE" "@PJL SET PAPER=EXECUTIVE"
run "PageSize=A5";        assert_has "A5 -> PAPER=A5"               "@PJL SET PAPER=A5"
run "PageSize=A6";        assert_has "A6 -> PAPER=A6"               "@PJL SET PAPER=A6"

echo "== quality mapping =="
run "BRQuality=Draft";  assert_has "Draft -> DRAFT"   "@PJL SET PRINTQUALITY=DRAFT"
run "BRQuality=Normal"; assert_has "Normal -> NORMAL" "@PJL SET PRINTQUALITY=NORMAL"
run "BRQuality=Best";   assert_has "Best -> HIGH"     "@PJL SET PRINTQUALITY=HIGH"
run "BRQuality=Photo";  assert_has "Photo -> HIGH"    "@PJL SET PRINTQUALITY=HIGH"

echo "== colour mapping =="
run "ColorModel=RGB";  assert_has "RGB -> COLOR"      "@PJL SET RENDERMODE=COLOR"
run "ColorModel=Gray"; assert_has "Gray -> GRAYSCALE" "@PJL SET RENDERMODE=GRAYSCALE"

echo "== media mapping =="
run "BRMediaType=Plain";  assert_has "Plain"  "@PJL SET MEDIATYPE=PLAIN"
run "BRMediaType=Glossy"; assert_has "Glossy" "@PJL SET MEDIATYPE=GLOSSY"
run "BRMediaType=Inkjet"; assert_has "Inkjet" "@PJL SET MEDIATYPE=INKJET"

echo "== borderless via the .Fullbleed page size =="
run "PageSize=A4.Fullbleed"
assert_has   "Fullbleed turns borderless on"        "@PJL SET BORDERLESS=ON"
assert_has   "Fullbleed strips the suffix"          "@PJL SET PAPER=A4"
assert_lacks "Fullbleed does not invent PAPER=A4_B" "PAPER=A4_B"
assert_has   "Fullbleed zeroes the top margin"      "@PJL SET JTTOPMARGIN=0"
assert_has   "Fullbleed zeroes the bottom margin"   "@PJL SET JTBOTMARGIN=0"
assert_has   "Fullbleed zeroes the left margin"     "@PJL SET JTLEFTMARGIN=0"
assert_has   "Fullbleed zeroes the right margin"    "@PJL SET JTRIGHTMARGIN=0"

# Borderless must win even if a caller also passes a non-zero margin.
run "PageSize=Letter.Fullbleed BRJTMargin=300"
assert_has "Fullbleed overrides an explicit margin" "@PJL SET JTLEFTMARGIN=0"
assert_has "Fullbleed still maps the paper"         "@PJL SET PAPER=LETTER"

run "PageSize=A4"
assert_has "plain A4 keeps borderless off" "@PJL SET BORDERLESS=OFF"

echo "== defaults =="
run ""
assert_has "defaults to A4"     "@PJL SET PAPER=A4"
assert_has "defaults to NORMAL" "@PJL SET PRINTQUALITY=NORMAL"
assert_has "defaults to COLOR"  "@PJL SET RENDERMODE=COLOR"
assert_has "defaults to PLAIN"  "@PJL SET MEDIATYPE=PLAIN"
assert_has "defaults margins 0" "@PJL SET JTTOPMARGIN=0"

echo "== injection resistance =="
run 'BRJTMargin=3;@PJL DEFAULT EVIL=1'
assert_lacks "margin option cannot inject PJL" "@PJL DEFAULT"

"$FILTER" 42 testuser 'evil" @PJL DEFAULT EVIL=1' 1 "" \
    < "$TMP/raster.bin" > "$TMP/out.bin" 2>/dev/null
assert_lacks "job title cannot inject PJL"       "@PJL DEFAULT"
assert_lacks "job title quote is stripped"       'evil"'

"$FILTER" 42 'bad" user' "t" 1 "" \
    < "$TMP/raster.bin" > "$TMP/out.bin" 2>/dev/null
assert_lacks "user name quote is stripped" 'bad"'

# The payload is ESC-free by construction, so the only ESC bytes in a correct
# stream are the three UELs.
"$FILTER" 42 testuser "$(printf 'bad\033title')" 1 "" \
    < "$TMP/raster.bin" > "$TMP/out.bin" 2>/dev/null
esc=$(LC_ALL=C od -An -c "$TMP/out.bin" | tr -s ' ' '\n' | grep -c '^033$')
if [ "$esc" -eq 3 ]; then
    ok "job title cannot inject an ESC (exactly 3 UELs)"
else
    nope "job title cannot inject an ESC (exactly 3 UELs)" "found $esc ESC bytes"
fi

echo "== exit status =="
run "PageSize=A4"
if "$FILTER" 42 u t 1 "" < "$TMP/raster.bin" >/dev/null 2>&1; then
    ok "exits 0 on success"
else
    nope "exits 0 on success" "non-zero exit"
fi
if "$FILTER" 42 u t 1 "" /nonexistent/raster.bin >/dev/null 2>&1; then
    nope "exits non-zero when the input file is missing" "exited 0"
else
    ok "exits non-zero when the input file is missing"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
