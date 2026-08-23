# shellcheck shell=bash
#
# Shared harness for the test scripts. Source it; do not run it.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only
#
# Every suite counts with ok/nope, may skip with skip, and ends with summary,
# whose exit status is the suite's.

PASS=0
FAIL=0

# Colour only when stdout is a terminal, so redirected logs and CI transcripts
# are plain text. NO_COLOR is honoured as well: https://no-color.org
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; OFF=$'\033[0m'
else
    RED=''; GRN=''; YEL=''; BLU=''; OFF=''
fi

ok()   { PASS=$((PASS+1)); printf '  %sok%s   %s\n' "$GRN" "$OFF" "$1"; }
skip() {                   printf '  %sskip%s %s\n' "$YEL" "$OFF" "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  %sFAIL%s %s\n        %s\n' "$RED" "$OFF" "$1" "${2:-}"; }
step() { echo; echo "${BLU}==> $*${OFF}"; }

# assert_status <expected> <description> <command...>
#
# Runs the command with its output discarded and compares the exit status.
# Capturing the status into a variable first is the point: "$?" read inside the
# branches of `[ $? -eq N ] && ok || nope "got $?"` reports the status of the
# test itself, which is always 1, never the command's.
assert_status() {
    local _want="$1" _what="$2" _got
    shift 2
    "$@" >/dev/null 2>&1
    _got=$?
    if [ "$_got" -eq "$_want" ]; then ok "$_what"
    else nope "$_what" "expected exit $_want, got $_got"; fi
}

summary() {
    echo
    echo "passed: $PASS   failed: $FAIL"
    [ "$FAIL" -eq 0 ]
}
