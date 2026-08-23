#!/bin/sh
#
# generate-ppd.sh <model> <filter-abs-path> [models.tsv]
#
# Emits a complete PPD on stdout for the named model. Pure function: reads the
# capability table and the template, writes stdout, changes nothing else. The
# result is buffered in a temporary file so it can be checked before any of it
# reaches stdout -- a caller that sees exit 0 must never receive a broken PPD.
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

# "*" is the fallback ROW, not a model. Asking for it by name would emit
# *ModelName: "Brother *", and a "*" inside a PPD string is illegal -- so the
# result would be a quietly invalid PPD. Pass a real model name; unknown ones
# land on the fallback row automatically.
[ "$MODEL" = "*" ] && {
    echo "'*' is the fallback row, not a model name. Pass the real model; an
unrecognised one uses the fallback row's capabilities automatically." >&2
    exit 4
}
# The model name is substituted into the PPD and ends up inside PPD quoted
# strings. It arrives from the printer's own device-id or from install.sh
# --model, so it is not ours to trust. Reject anything outside the character
# set real model names use, rather than trying to escape it: one double quote
# is enough to make the PPD unparsable, and nothing downstream would notice.
if [ -n "$(printf '%s' "$MODEL" | tr -d 'A-Za-z0-9._+ -')" ]; then
    echo "refusing model name '$MODEL'" >&2
    echo "allowed characters: letters, digits, space, and . _ + -" >&2
    exit 4
fi

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
# sed reads "&" in a replacement as "the whole match" and "|" as the end of the
# expression, so every value going into one is escaped first. MODEL is already
# restricted above; FILTER is a path the caller chose, and the rest come from
# models.tsv, which contributors edit.
sed_repl() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }

OUT=$(mktemp) || { echo "cannot create a temporary file" >&2; exit 3; }
trap 'rm -f "$OUT"' EXIT HUP INT TERM

sed -e "s|@MODEL@|$(sed_repl "$MODEL")|g" \
    -e "s|@NICKNAME@|$(sed_repl "$NICKNAME")|g" \
    -e "s|@FILTER@|$(sed_repl "$FILTER")|g" \
    -e "s|@DEFAULT_QUALITY@|$(sed_repl "$DEFAULT_QUALITY")|g" \
    -e "s|@DEFAULT_PAGESIZE@|$(sed_repl "$DEFAULT_PAGESIZE")|g" \
    "$TEMPLATE" \
| sed -e "s|^\*ShortNickName: .*|*ShortNickName: \"$(sed_repl "$SHORTNICK")\"|" \
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
    # A mono-only model loses the colour choice entirely. The three keywords
    # that describe the device itself have to move with it: a PPD offering
    # only Grayscale while still declaring ColorDevice True and an RGB default
    # colour space describes a printer that does not exist, and the print
    # dialog believes the declaration, not the option list.
    /^\*ColorModel RGB/ { if (colour == "mono") next; print; next }
    /^\*DefaultColorModel:/ {
        if (colour == "mono") { print "*DefaultColorModel: Gray"; next }
        print; next
    }
    /^\*ColorDevice:/ {
        if (colour == "mono") { print "*ColorDevice: False"; next }
        print; next
    }
    /^\*DefaultColorSpace:/ {
        if (colour == "mono") { print "*DefaultColorSpace: Gray"; next }
        print; next
    }
    { print }
' > "$OUT"

# Neither sed nor awk aborts this script when it fails, and the pipeline's exit
# status is awk's, so a broken substitution would otherwise leave here as a
# success. These two checks are what makes exit 0 mean something.
if [ ! -s "$OUT" ] || ! head -1 "$OUT" | grep -q '^\*PPD-Adobe'; then
    echo "PPD generation produced no usable output for '$MODEL'" >&2
    exit 3
fi
# A leftover placeholder means a substitution silently did not happen.
if grep -q '@[A-Z_][A-Z_]*@' "$OUT"; then
    echo "unsubstituted placeholder left in the PPD for '$MODEL':" >&2
    grep -n '@[A-Z_][A-Z_]*@' "$OUT" | head -3 >&2
    exit 3
fi

cat "$OUT"
