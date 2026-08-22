#!/bin/bash
# Every hardware-free test. Safe to run on any Mac: no printer, no root, no
# system change.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUITES="test_filter.sh test_ppd.sh test_install.sh test_testpage.sh"
rc=0
declare -a RESULTS=()

for t in $SUITES; do
    if [ ! -f "$HERE/$t" ]; then
        RESULTS+=("SKIP  $t (not present)")
        continue
    fi
    echo
    echo "########## $t ##########"
    if bash "$HERE/$t"; then
        RESULTS+=("PASS  $t")
    else
        RESULTS+=("FAIL  $t")
        rc=1
    fi
done

echo
echo "########## summary ##########"
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo
if [ $rc -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "SOME SUITES FAILED"; fi
exit $rc
