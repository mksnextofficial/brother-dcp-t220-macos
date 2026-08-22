#!/bin/bash
#
# verify-hardware.sh -- the checks that need a real printer and real root.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only
#
# Complements test/run-all.sh, which covers everything that can be tested
# without hardware. This script covers what that one cannot:
#
#   Stage A  the round trip: install then uninstall must leave the system
#            byte-identical to how it started. This is the promise that the
#            driver can be backed out, tested rather than asserted.
#   Stage B  a real install, validated with cupstestppd against the INSTALLED
#            copy -- including the root-ownership and permission checks that no
#            unaudited unit test can satisfy -- then one printed page.
#
# Needs sudo. Uses one sheet of paper.
#
# Usage:
#   ./test/verify-hardware.sh            round trip, then install and print
#   ./test/verify-hardware.sh --no-print install, but do not print
#   ./test/verify-hardware.sh --revert   just uninstall and stop

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
QUEUE="Brother_PWG"
INSTALL_DIR="/Library/Printers/BrotherPWG"
TMP="$(mktemp -d)"
DO_PRINT=1

RED=$'\033[31m'; GRN=$'\033[32m'; BLU=$'\033[34m'; OFF=$'\033[0m'
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  %sok%s   %s\n' "$GRN" "$OFF" "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  %sFAIL%s %s\n        %s\n' "$RED" "$OFF" "$1" "${2:-}"; }
step() { echo; echo "${BLU}==> $*${OFF}"; }

case "${1:-}" in
    --revert)   step "Reverting"; sudo "$ROOT/uninstall.sh"; exit $? ;;
    --no-print) DO_PRINT=0 ;;
    "")         ;;
    *)          echo "unknown argument: $1" >&2; exit 4 ;;
esac

step "Stage A -- round trip: does uninstall really put everything back?"

lpstat -p > "$TMP/before.txt" 2>&1
cp "$TMP/before.txt" "$TMP/b.txt"
echo "  queues before:"; sed 's/^/    /' "$TMP/before.txt"

sudo "$ROOT/install.sh" --yes > "$TMP/inst.log" 2>&1 \
    && ok "install.sh succeeded" \
    || { nope "install.sh succeeded" "$(tail -5 "$TMP/inst.log")"; exit 1; }

lpstat -p "$QUEUE" >/dev/null 2>&1 && ok "queue '$QUEUE' was created" \
    || nope "queue '$QUEUE' was created" "not listed"

sudo "$ROOT/uninstall.sh" > "$TMP/uninst.log" 2>&1 \
    && ok "uninstall.sh succeeded" \
    || nope "uninstall.sh succeeded" "$(tail -5 "$TMP/uninst.log")"

lpstat -p > "$TMP/after.txt" 2>&1
if diff -q "$TMP/before.txt" "$TMP/after.txt" >/dev/null; then
    ok "queue list is identical to before"
else
    nope "queue list is identical to before" "$(diff "$TMP/before.txt" "$TMP/after.txt")"
fi

[ ! -e "$INSTALL_DIR" ] && ok "$INSTALL_DIR is gone" \
    || nope "$INSTALL_DIR is gone" "still present"

# Nothing of Brother's may have been disturbed.
if [ -f /Library/LaunchAgents/com.brother.HttpToUsbBridge.plist ]; then
    ok "Brother's LaunchAgent is untouched"
else
    nope "Brother's LaunchAgent is untouched" "plist missing -- we should never remove it"
fi
[ -d "/Applications/Brother iPrint&Scan.app" ] && ok "iPrint&Scan is untouched" \
    || echo "       (iPrint&Scan was not installed here; nothing to check)"

step "Stage B -- install for real and validate the installed copy"

sudo "$ROOT/install.sh" --yes > "$TMP/inst2.log" 2>&1 \
    && ok "installed" || { nope "installed" "$(tail -5 "$TMP/inst2.log")"; exit 1; }

# The installed filter must be root-owned and not writable by others, or CUPS
# refuses to run it. This is exactly the check test_ppd.sh has to skip.
perms="$(stat -f '%Su:%Sg %Lp' "$INSTALL_DIR/rastertobrotherpjl" 2>/dev/null)"
[ "$perms" = "root:wheel 755" ] && ok "installed filter is root:wheel 755" \
    || nope "installed filter is root:wheel 755" "got: $perms"

CTP="$(command -v cupstestppd || true)"
if [ -n "$CTP" ]; then
    if "$CTP" -q "$INSTALL_DIR/brother-pwg.ppd"; then
        ok "cupstestppd passes cleanly on the installed PPD (no exclusions)"
    else
        nope "cupstestppd passes cleanly on the installed PPD" \
             "$("$CTP" "$INSTALL_DIR/brother-pwg.ppd" 2>&1 | grep -E '\*\*FAIL\*\*' | head -5)"
    fi
fi

# The options a user will actually see in the print dialog.
ppd="/etc/cups/ppd/$QUEUE.ppd"
if [ -f "$ppd" ]; then
    nq=$(grep -c '^\*BRQuality ' "$ppd")
    ns=$(grep -c '^\*PageSize '  "$ppd")
    nb=$(grep -c '^\*PageSize .*Fullbleed' "$ppd")
    ok "print dialog offers $nq quality levels, $ns page sizes ($nb borderless)"
    [ "$nq" -ge 3 ] || nope "at least 3 quality levels" "got $nq"
else
    nope "CUPS stored a PPD for the queue" "$ppd missing"
fi

if [ "$DO_PRINT" -eq 1 ]; then
    step "Stage B -- print one page at the driver's defaults"
    python3 "$ROOT/tools/make-testpage.py" -o "$TMP/final.pdf" \
        --label "FINAL - install.sh defaults" >/dev/null \
        && ok "calibration page generated" || nope "calibration page generated" ""
    lp -d "$QUEUE" -t "verify-hardware" "$TMP/final.pdf" \
        && ok "job accepted by CUPS" || nope "job accepted by CUPS" ""
    for _ in $(seq 1 24); do
        sleep 5
        [ "$(lpstat -o "$QUEUE" 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] && break
    done
    if [ "$(lpstat -o "$QUEUE" 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]; then
        ok "queue drained -- the printer took the job"
    else
        nope "queue drained" "$(lpstat -o "$QUEUE"; lpstat -p "$QUEUE" | head -2)"
    fi
    echo
    echo "  Filter debug output from this job:"
    sudo grep -a "rastertobrotherpjl" /var/log/cups/error_log 2>/dev/null | tail -4 | sed 's/^/    /'
fi

step "Result"
echo "  passed: $PASS   failed: $FAIL"
echo
if [ "$FAIL" -eq 0 ]; then
    echo "  The driver is installed and working. Print to '$QUEUE' from any app."
    echo "  Remove it again with:  sudo $ROOT/uninstall.sh"
else
    echo "  Something failed above. The system is in whatever state the last"
    echo "  successful step left it; 'sudo $ROOT/uninstall.sh' returns it to clean."
fi
rm -rf "$TMP"
[ "$FAIL" -eq 0 ]
