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
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
DO_PRINT=1

# shellcheck source=test/lib.sh
. "$HERE/lib.sh"

case "${1:-}" in
    --revert)   step "Reverting"; sudo "$ROOT/uninstall.sh"; exit $? ;;
    --no-print) DO_PRINT=0 ;;
    "")         ;;
    *)          echo "unknown argument: $1" >&2; exit 4 ;;
esac

step "Stage A -- round trip: does uninstall really put everything back?"

lpstat -p > "$TMP/before.txt" 2>&1
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

step "Stage A2 -- a second queue must not be orphaned by the first uninstall"

# install.sh can create several queues (--queue NAME) and they all share
# /Library/Printers/BrotherPWG. Removing one queue must leave those files
# alone while another still points at them, or the survivor keeps accepting
# jobs that can never run.
SECOND="Brother_PWG_2"
sudo "$ROOT/install.sh" --yes > "$TMP/a2a.log" 2>&1 \
    && sudo "$ROOT/install.sh" --yes --queue "$SECOND" > "$TMP/a2b.log" 2>&1 \
    && ok "two queues installed" \
    || { nope "two queues installed" "$(tail -5 "$TMP/a2b.log")"; exit 1; }

sudo "$ROOT/uninstall.sh" --queue "$QUEUE" > "$TMP/a2c.log" 2>&1
[ -e "$INSTALL_DIR/rastertobrotherpjl" ] \
    && ok "driver files survive while '$SECOND' still uses them" \
    || nope "driver files survive while '$SECOND' still uses them" \
            "$INSTALL_DIR was removed out from under a live queue"
lpstat -p "$SECOND" >/dev/null 2>&1 && ok "'$SECOND' is still installed" \
    || nope "'$SECOND' is still installed" "it disappeared"

sudo "$ROOT/uninstall.sh" --all > "$TMP/a2d.log" 2>&1
[ ! -e "$INSTALL_DIR" ] && ok "--all removes the files once nothing uses them" \
    || nope "--all removes the files once nothing uses them" "$INSTALL_DIR remains"
lpstat -p "$SECOND" >/dev/null 2>&1 \
    && nope "--all removed '$SECOND'" "still listed" \
    || ok "--all removed '$SECOND'"

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
[ "$FAIL" -eq 0 ]
