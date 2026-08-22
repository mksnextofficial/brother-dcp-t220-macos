#!/bin/bash
#
# install.sh -- install the brother-pwg-macos driver and create a print queue.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only
#
# Exit codes:
#   0  ok
#   1  no Brother printer found on USB
#   2  printer found but this driver does not apply to it
#   3  installation failed
#   4  usage error

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/Library/Printers/BrotherPWG"
FILTER_DEST="$INSTALL_DIR/rastertobrotherpjl"
PPD_DEST="$INSTALL_DIR/brother-pwg.ppd"

QUEUE="Brother_PWG"
MODEL=""
DRY_RUN=0
EMIT_PPD=0
ASSUME_YES=0

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; OFF=$'\033[0m'

# Under --emit-ppd, stdout carries the PPD and nothing else, so every
# informational line goes to stderr instead.
msg()  { if [ "$EMIT_PPD" -eq 1 ]; then printf '%s\n' "$*" >&2
         else printf '%s\n' "$*"; fi; }
say()  { msg "$*"; }
ok()   { msg "${GRN}  ok${OFF}   $*"; }
warn() { echo "${YEL}warning:${OFF} $*" >&2; }
die()  { echo "${RED}error:${OFF} $*" >&2; exit "${2:-3}"; }
step() { msg ""; msg "${BLU}==> $*${OFF}"; }

usage() {
    cat <<'EOF'
install.sh -- install the brother-pwg-macos driver and create a print queue

  --dry-run          show what would happen; change nothing, need no root
  --emit-ppd         write the generated PPD to stdout and exit (implies a
                     silent run; useful for inspection and for tests)
  --model MODEL      skip USB detection and use this model name
  --queue NAME       queue name to create (default: Brother_PWG)
  --yes              replace an existing queue of the same name without asking
  --help             this text

Examples:
  ./install.sh --dry-run
  sudo ./install.sh
  ./install.sh --dry-run --model DCP-T220 --emit-ppd > brother.ppd
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)  DRY_RUN=1 ;;
        --emit-ppd) EMIT_PPD=1; DRY_RUN=1 ;;
        --model)    shift; MODEL="${1:-}"; [ -n "$MODEL" ] || { usage >&2; exit 4; } ;;
        --queue)    shift; QUEUE="${1:-}"; [ -n "$QUEUE" ] || { usage >&2; exit 4; } ;;
        --yes|-y)   ASSUME_YES=1 ;;
        --help|-h)  usage; exit 0 ;;
        *)          echo "unknown argument: $1" >&2; usage >&2; exit 4 ;;
    esac
    shift
done

GEN="$HERE/ppd/generate-ppd.sh"
TSV="$HERE/ppd/models.tsv"
FILTER_SRC="$HERE/filter/rastertobrotherpjl"
for f in "$GEN" "$TSV" "$FILTER_SRC"; do
    [ -f "$f" ] || die "missing repository file: $f" 4
done

# ---------------------------------------------------------------- detection
DEVURI=""
DEVID=""

detect_printer() {
    local line uri id
    while IFS= read -r line; do
        case "$line" in
            "Device: uri = "*)
                uri="${line#Device: uri = }"
                ;;
            *"device-id = "*)
                id="${line#*device-id = }"
                case "$uri" in
                    usb://*)
                        case "$id" in
                            *MFG:Brother*|*MANUFACTURER:Brother*)
                                DEVURI="$uri"; DEVID="$id"; return 0 ;;
                        esac ;;
                esac ;;
        esac
    done < <(/usr/sbin/lpinfo -l -v 2>/dev/null)
    return 1
}

# device-id field extractor: id_field MDL -> "DCP-T220"
id_field() {
    printf '%s' "$DEVID" | tr ';' '\n' | awk -F: -v k="$1" \
        'toupper($1)==k {sub(/^[^:]*:/,""); print; exit}'
}

step "1. Identify the printer"
if [ -n "$MODEL" ]; then
    say "  model given on the command line: $MODEL"
    say "  (skipping USB detection)"
else
    if detect_printer; then
        MODEL="$(id_field MDL)"
        [ -n "$MODEL" ] || MODEL="$(id_field MODEL)"
        [ -n "$MODEL" ] || die "found a Brother printer but could not read MDL from: $DEVID" 2
        ok "found $MODEL"
        say "  device URI: $DEVURI"
        say "  device-id : $DEVID"

        CMD="$(id_field CMD)"
        [ -n "$CMD" ] || CMD="$(id_field COMMAND SET)"
        case "$CMD" in
            *HBP*) ok "reports CMD:HBP -- this driver applies" ;;
            *)
                echo >&2
                die "this printer reports CMD:${CMD:-<none>}, which does not include HBP.

brother-pwg-macos drives Brother inkjets that accept PWG Raster inside a PJL
envelope; those advertise HBP. Yours speaks something else, so installing this
driver would only produce failed jobs. Nothing has been changed." 2
                ;;
        esac
    else
        die "no Brother printer found on USB.

Check that it is powered on and connected, then look at:
    /usr/sbin/lpinfo -v

If the printer is there but this still fails, run with --model <MDL> to skip
detection." 1
    fi
fi

# ------------------------------------------------------------------- profile
step "2. Match the capability profile"
PPD_TMP="$(mktemp)"
trap 'rm -f "$PPD_TMP"' EXIT

if ! "$GEN" "$MODEL" "$FILTER_DEST" "$TSV" > "$PPD_TMP" 2>/dev/null; then
    die "could not generate a PPD for '$MODEL' (generate-ppd.sh exit $?)" 3
fi

if grep -q '^\*NickName:.*unverified' "$PPD_TMP"; then
    STATUS="generic (unverified)"
    echo
    warn "'$MODEL' is not in the verified list."
    cat >&2 <<EOF

  It will be installed on the GENERIC profile, which claims only what is safe
  to assume for any Brother inkjet that speaks HBP:

      quality      Draft, Normal, Best     (no Photo/1200 dpi)
      paper        A4, Letter, Legal, A5, A6, Executive
      borderless   withheld

  Borderless is withheld deliberately. It is the one option whose failure mode
  reaches outside the sheet: on a printer that does not support it, ink lands
  on the platen roller and marks the back of the pages that follow.

  Printing should work. If it does, please qualify your model so the next
  person gets the full profile -- see docs/contributing-a-model.md.

EOF
else
    STATUS="verified"
    ok "'$MODEL' is verified on hardware"
fi

if [ "$EMIT_PPD" -eq 1 ]; then
    cat "$PPD_TMP"
    exit 0
fi

say "  status      : $STATUS"
say "  queue name  : $QUEUE"
say "  install dir : $INSTALL_DIR"
say "  filter      : $FILTER_DEST"
say "  ppd         : $PPD_DEST"
[ -n "$DEVURI" ] && say "  device URI  : $DEVURI"

if [ "$DRY_RUN" -eq 1 ]; then
    echo
    say "Dry run: nothing was changed."
    exit 0
fi

[ -n "$DEVURI" ] || die "no device URI -- --model alone cannot create a queue.
Connect the printer and run without --model." 1

# ------------------------------------------------------------------- install
step "3. Install the driver"
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

$SUDO mkdir -p "$INSTALL_DIR"           || die "could not create $INSTALL_DIR"
$SUDO cp "$FILTER_SRC" "$FILTER_DEST"   || die "could not install the filter"
$SUDO cp "$PPD_TMP"    "$PPD_DEST"      || die "could not install the PPD"
$SUDO chown -R root:wheel "$INSTALL_DIR" || die "could not set ownership"
$SUDO chmod 755 "$INSTALL_DIR" "$FILTER_DEST" || die "could not set permissions"
$SUDO chmod 644 "$PPD_DEST"             || die "could not set permissions"
ok "installed to $INSTALL_DIR"

# ------------------------------------------------------------------- queue
step "4. Create the print queue"
if lpstat -p "$QUEUE" >/dev/null 2>&1; then
    EXISTING_URI="$(lpstat -v "$QUEUE" 2>/dev/null | sed 's/.*device for [^:]*: //')"
    if [ "$ASSUME_YES" -ne 1 ]; then
        die "a queue named '$QUEUE' already exists (device: ${EXISTING_URI:-unknown}).

Re-run with --yes to replace it, or with --queue <name> to use a different
name. Nothing has been changed apart from the files in $INSTALL_DIR." 3
    fi
    warn "replacing the existing queue '$QUEUE'"
    $SUDO lpadmin -x "$QUEUE" 2>/dev/null
fi

$SUDO lpadmin -p "$QUEUE" -v "$DEVURI" -P "$PPD_DEST" -E \
    || die "lpadmin failed to create the queue"
$SUDO cupsenable "$QUEUE" 2>/dev/null
$SUDO cupsaccept "$QUEUE" 2>/dev/null
ok "created queue '$QUEUE' -> $DEVURI"

# ------------------------------------------------------------------- done
step "Done"
cat <<EOF
  Print to '$QUEUE' from any application. In the print dialog you should see
  Print Quality with Draft / Normal / Best$([ "$STATUS" = verified ] && echo " / Photo"), and Media Type with three choices.

  Nothing belonging to Brother was modified or removed. iPrint&Scan and any
  queue you already had still work exactly as before.

  Print a calibration page:
      python3 "$HERE/tools/make-testpage.py" -o /tmp/cal.pdf && lp -d $QUEUE /tmp/cal.pdf

  Remove this driver again:
      sudo "$HERE/uninstall.sh"
EOF
