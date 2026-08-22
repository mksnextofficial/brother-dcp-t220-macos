#!/bin/sh
#
# generate-ppd.sh <model> <filter-abs-path> [models.tsv]
#
# Emits a complete PPD on stdout for the named model. Pure function: reads the
# capability table and the template, writes stdout, touches nothing else.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only
#
# Exit codes:
#   0  ok
#   2  no matching row and no "*" fallback in the table
#   3  malformed row
#   4  usage error

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
MODEL="${1:-}"
FILTER="${2:-}"
TSV="${3:-$HERE/models.tsv}"
TEMPLATE="$HERE/template.ppd"

[ -n "$MODEL" ] && [ -n "$FILTER" ] || {
    echo "usage: generate-ppd.sh <model> <filter-abs-path> [models.tsv]" >&2
    exit 4
}
[ -f "$TSV" ]      || { echo "no such table: $TSV" >&2; exit 4; }
[ -f "$TEMPLATE" ] || { echo "no such template: $TEMPLATE" >&2; exit 4; }

# --- find the row: exact model first, then the "*" fallback -----------------
row=$(awk -F'\t' -v m="$MODEL" \
        '/^#/ {next} NF==0 {next} $1==m {print; exit}' "$TSV")
matched_exact=1
if [ -z "$row" ]; then
    matched_exact=0
    row=$(awk -F'\t' '/^#/ {next} NF==0 {next} $1=="*" {print; exit}' "$TSV")
fi
[ -n "$row" ] || {
    echo "no row for '$MODEL' and no '*' fallback in $TSV" >&2
    exit 2
}

ncols=$(printf '%s' "$row" | awk -F'\t' '{print NF}')
[ "$ncols" -eq 8 ] || {
    echo "malformed row ($ncols fields, expected 8): $row" >&2
    exit 3
}

field() { printf '%s' "$row" | cut -f"$1"; }

STATUS=$(field 2)
QUALITIES=$(field 3)
DEFAULT_QUALITY=$(field 4)
COLOUR=$(field 5)
PAPERSIZES=$(field 6)
BORDERLESS=$(field 7)

for f in "$STATUS" "$QUALITIES" "$DEFAULT_QUALITY" "$COLOUR" "$PAPERSIZES"; do
    [ -n "$f" ] || { echo "empty required field in row: $row" >&2; exit 3; }
done

# --- build the keep-list of page-size keywords ------------------------------
keep_sizes=$(printf '%s' "$PAPERSIZES" | tr ',' '\n' | tr -d ' ' | sed '/^$/d')
if [ "$BORDERLESS" != none ] && [ -n "$BORDERLESS" ]; then
    keep_bleed=$(printf '%s' "$BORDERLESS" | tr ',' '\n' | tr -d ' ' \
                 | sed '/^$/d' | sed 's/$/.Fullbleed/')
else
    keep_bleed=""
fi
keep_all=$(printf '%s\n%s\n' "$keep_sizes" "$keep_bleed" | sed '/^$/d')

DEFAULT_PAGESIZE=$(printf '%s\n' "$keep_sizes" | head -1)

# awk cannot take a newline-separated shell variable safely, so pass
# comma-bounded strings it can substring-match against.
keep_csv=",$(printf '%s' "$keep_all" | tr '\n' ',' | sed 's/,$//'),"
qual_csv=",$(printf '%s' "$QUALITIES" | tr -d ' '),"

# An unverified model says so in the name the user sees in the print dialog.
if [ "$STATUS" = verified ] && [ "$matched_exact" -eq 1 ]; then
    NICKNAME="Brother $MODEL PWG"
else
    NICKNAME="Brother $MODEL PWG (unverified)"
fi

# ShortNickName is capped at 31 characters by the PPD spec.
SHORTNICK=$(printf '%s' "Brother $MODEL" | cut -c1-31)

# --- emit -------------------------------------------------------------------
sed -e "s|@MODEL@|$MODEL|g" \
    -e "s|@NICKNAME@|$NICKNAME|g" \
    -e "s|@FILTER@|$FILTER|g" \
    -e "s|@DEFAULT_QUALITY@|$DEFAULT_QUALITY|g" \
    -e "s|@DEFAULT_PAGESIZE@|$DEFAULT_PAGESIZE|g" \
    "$TEMPLATE" \
| sed -e "s|^\*ShortNickName: .*|*ShortNickName: \"$SHORTNICK\"|" \
| awk -v keep="$keep_csv" -v quals="$qual_csv" -v colour="$COLOUR" '
    function kw_of(tok,   a, k) {
        split(tok, a, "/"); k = a[1]; sub(/:$/, "", k); return k
    }

    # Page-geometry lines: keep only the listed keywords.
    /^\*(PageSize|PageRegion|ImageableArea|PaperDimension) / {
        if (index(keep, "," kw_of($2) ",") == 0) next
        print; next
    }
    # Quality choices: keep only the listed levels.
    /^\*BRQuality / {
        if (index(quals, "," kw_of($2) ",") == 0) next
        print; next
    }
    # A mono-only model loses the colour choice entirely.
    /^\*ColorModel RGB/ { if (colour == "mono") next; print; next }
    /^\*DefaultColorModel:/ {
        if (colour == "mono") { print "*DefaultColorModel: Gray"; next }
        print; next
    }
    { print }
'
