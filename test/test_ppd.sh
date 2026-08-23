#!/bin/bash
# Tests for ppd/generate-ppd.sh. No hardware, no root.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$HERE/../ppd/generate-ppd.sh"
TSV="$HERE/../ppd/models.tsv"
# Point at the filter in the working tree, not at the eventual install path:
# cupstestppd verifies that the *cupsFilter file actually exists, and that check
# is worth keeping rather than working around.
FILT="$(cd "$HERE/../filter" && pwd)/rastertobrotherpjl"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test/lib.sh
. "$HERE/lib.sh"

# check <description> <file> <extended-regex>
check() { grep -qE -- "$3" "$2" && ok "$1" || nope "$1" "no line matching: $3"; }
deny()  { grep -qE -- "$3" "$2" && nope "$1" "unexpected line matching: $3" || ok "$1"; }

echo "== verified model: DCP-T220 =="
if "$GEN" DCP-T220 "$FILT" "$TSV" > "$TMP/t220.ppd" 2> "$TMP/t220.err" \
   && [ -s "$TMP/t220.ppd" ]; then
    ok "generates a PPD"
else
    nope "generates a PPD" "$(cat "$TMP/t220.err")"
fi

check "declares the pwg-raster filter" "$TMP/t220.ppd" '^\*cupsFilter:.*image/pwg-raster'
check "references the filter by absolute path" "$TMP/t220.ppd" "$FILT"
deny  "no leftover substitution tokens" "$TMP/t220.ppd" '@[A-Z_]+@'
check "default quality is Normal" "$TMP/t220.ppd" '^\*DefaultBRQuality: Normal'
check "verified model offers Photo" "$TMP/t220.ppd" '^\*BRQuality Photo'
check "verified model offers borderless A4" "$TMP/t220.ppd" '^\*PageSize A4\.Fullbleed'
check "advertises the HBP device id" "$TMP/t220.ppd" '^\*1284DeviceID:.*CMD:HBP'
check "renders full sheet (ImagingBBox null)" "$TMP/t220.ppd" 'ImagingBBox null'

echo "== quality levels carry their own resolution =="
q() { grep "^\*BRQuality $1" "$TMP/t220.ppd" | grep -q "HWResolution\[$2 $2\]"; }
q Draft  300  && ok "Draft is 300 dpi"   || nope "Draft is 300 dpi"   "wrong HWResolution"
q Normal 600  && ok "Normal is 600 dpi"  || nope "Normal is 600 dpi"  "wrong HWResolution"
q Best   600  && ok "Best is 600 dpi"    || nope "Best is 600 dpi"    "wrong HWResolution"
q Photo  1200 && ok "Photo is 1200 dpi"  || nope "Photo is 1200 dpi"  "wrong HWResolution"

echo "== generic fallback =="
"$GEN" DCP-T999-NOSUCH "$FILT" "$TSV" > "$TMP/gen.ppd" 2>/dev/null
check "generic profile still offers A4" "$TMP/gen.ppd" '^\*PageSize A4[:/]'
deny  "generic profile excludes borderless" "$TMP/gen.ppd" '^\*PageSize .*\.Fullbleed'
deny  "generic profile excludes Photo" "$TMP/gen.ppd" '^\*BRQuality Photo'
check "generic profile is labelled unverified" "$TMP/gen.ppd" '^\*NickName:.*unverified'

echo "== every page size is geometrically complete =="
incomplete=""
for f in t220 gen; do
    while read -r kw; do
        [ -n "$kw" ] || continue
        esc="${kw//./\\.}"
        for sect in PageRegion ImageableArea PaperDimension; do
            grep -qE "^\*$sect $esc[:/ ]" "$TMP/$f.ppd" \
                || incomplete="$incomplete $f:$kw/$sect"
        done
    done < <(awk '/^\*PageSize /{split($2,a,"/"); k=a[1]; sub(/:$/,"",k); print k}' "$TMP/$f.ppd")
done
[ -z "$incomplete" ] && ok "all page sizes have region, area and dimension" \
    || nope "all page sizes have region, area and dimension" "missing:$incomplete"

echo "== defaults name real options =="
for f in t220 gen; do
    dps=$(awk -F': ' '/^\*DefaultPageSize:/{print $2}' "$TMP/$f.ppd")
    esc="${dps//./\\.}"
    grep -qE "^\*PageSize $esc[:/ ]" "$TMP/$f.ppd" \
        && ok "$f: DefaultPageSize '$dps' exists" \
        || nope "$f: DefaultPageSize '$dps' exists" "not among the PageSize options"
    dq=$(awk -F': ' '/^\*DefaultBRQuality:/{print $2}' "$TMP/$f.ppd")
    grep -qE "^\*BRQuality $dq[:/ ]" "$TMP/$f.ppd" \
        && ok "$f: DefaultBRQuality '$dq' exists" \
        || nope "$f: DefaultBRQuality '$dq' exists" "not among the BRQuality options"
done

echo "== cupstestppd =="
# cupstestppd also checks that the *cupsFilter program is owned by root and not
# writable by others. That is a property of the INSTALLED copy, and no test
# running as an ordinary user can create it -- so those two findings are
# excluded here and verified against the real installation in Task 8 instead.
# Every other finding must be clean.
CTP="$(command -v cupstestppd || true)"
if [ -n "$CTP" ]; then
    for f in t220 gen; do
        "$CTP" "$TMP/$f.ppd" 2>&1 \
            | grep -E '\*\*FAIL\*\*' \
            | grep -vE 'cupsFilter file' > "$TMP/$f.ctp" || true
        if [ ! -s "$TMP/$f.ctp" ]; then
            ok "cupstestppd accepts the $f PPD (install-time file checks aside)"
        else
            nope "cupstestppd accepts the $f PPD" "$(head -10 "$TMP/$f.ctp")"
        fi
    done
else
    skip "cupstestppd not on PATH -- PPD validation not run here"
fi

echo "== a mono model describes itself as mono throughout =="
# No row in models.tsv is mono, but docs/contributing-a-model.md tells
# contributors to write it, so the path has to hold up before one arrives.
printf 'MONO-TEST\tverified\tDraft,Normal,Best\tNormal\tmono\tA4,Letter\tnone\t1\n' \
    > "$TMP/mono.tsv"
"$GEN" MONO-TEST "$FILT" "$TMP/mono.tsv" > "$TMP/mono.ppd" 2>/dev/null
check "mono keeps Grayscale"        "$TMP/mono.ppd" '^\*ColorModel Gray'
deny  "mono drops the RGB choice"   "$TMP/mono.ppd" '^\*ColorModel RGB'
check "mono defaults to Gray"       "$TMP/mono.ppd" '^\*DefaultColorModel: Gray'
check "mono is not a ColorDevice"   "$TMP/mono.ppd" '^\*ColorDevice: False'
check "mono colour space is Gray"   "$TMP/mono.ppd" '^\*DefaultColorSpace: Gray'
if [ -n "$(command -v cupstestppd || true)" ]; then
    cupstestppd "$TMP/mono.ppd" 2>&1 | grep -E '\*\*FAIL\*\*' \
        | grep -vE 'cupsFilter file' > "$TMP/mono.ctp" || true
    [ ! -s "$TMP/mono.ctp" ] && ok "cupstestppd accepts the mono PPD" \
        || nope "cupstestppd accepts the mono PPD" "$(head -5 "$TMP/mono.ctp")"
fi

echo "== malformed input =="
printf 'BAD\tROW\n' > "$TMP/bad.tsv"
assert_status 3 "malformed row exits 3" "$GEN" BAD "$FILT" "$TMP/bad.tsv"

printf '# only a comment\n' > "$TMP/empty.tsv"
assert_status 2 "no match and no fallback exits 2" "$GEN" ANYTHING "$FILT" "$TMP/empty.tsv"

assert_status 4 "missing arguments exits 4" "$GEN"
assert_status 4 "the '*' fallback row is refused as a model name" \
    "$GEN" '*' "$FILT" "$TSV"

# A model name is substituted into PPD quoted strings and into sed replacement
# text, and it comes from the printer's device-id. Anything outside the plain
# model-name character set has to be refused rather than escaped, because a
# corrupt PPD here would be installed without complaint.
for bad in 'X"Y' 'A&B' 'DCP|EVIL' 'back\slash'; do
    assert_status 4 "hostile model name is refused: $bad" "$GEN" "$bad" "$FILT" "$TSV"
done

# A filter path may legitimately contain sed metacharacters; those must survive
# substitution rather than be rejected.
odd="$TMP/a&b|c/rastertobrotherpjl"
"$GEN" DCP-T220 "$odd" "$TSV" > "$TMP/odd.ppd" 2>/dev/null
check "sed metacharacters in the filter path survive" "$TMP/odd.ppd" \
    "$(printf '%s' "$odd" | sed 's/[][\\.*^$|&]/\\\\&/g')"

summary
