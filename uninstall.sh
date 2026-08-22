#!/bin/bash
#
# uninstall.sh -- remove the brother-pwg-macos driver.
#
# Copyright (C) 2026  brother-pwg-macos contributors
# SPDX-License-Identifier: GPL-2.0-only
#
# Removes exactly two things: the queue this driver created, and its own
# install directory. It never touches Brother's software, other print queues,
# or /etc/cups directly. Running it on an already-clean system is not an error.
#
# Exit codes:
#   0  ok, including "there was nothing to remove"
#   3  removal failed, or the named queue belongs to something else
#   4  usage error

set -uo pipefail

INSTALL_DIR="/Library/Printers/BrotherPWG"
FILTER_MARK="$INSTALL_DIR/rastertobrotherpjl"
QUEUE="Brother_PWG"
ALL=0

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; OFF=$'\033[0m'
ok()   { echo "${GRN}  ok${OFF}   $*"; }
info() { echo "       $*"; }
warn() { echo "${YEL}warning:${OFF} $*" >&2; }
die()  { echo "${RED}error:${OFF} $*" >&2; exit "${2:-3}"; }
step() { echo; echo "${BLU}==> $*${OFF}"; }

usage() {
    cat <<'EOF'
uninstall.sh -- remove the brother-pwg-macos driver

  --queue NAME   queue to remove (default: Brother_PWG)
  --all          remove every queue that uses this driver, whatever its name
  --help         this text
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --queue) shift; QUEUE="${1:-}"; [ -n "$QUEUE" ] || { usage >&2; exit 4; } ;;
        --all)   ALL=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 4 ;;
    esac
    shift
done

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

# A queue is ours if the PPD CUPS made for it points at our filter.
queue_is_ours() {
    local q="$1" ppd="/etc/cups/ppd/$1.ppd"
    [ -f "$ppd" ] || return 1
    grep -q "$FILTER_MARK" "$ppd"
}

removed_any=0

step "1. Print queues"
if [ "$ALL" -eq 1 ]; then
    targets=""
    for q in $(lpstat -p 2>/dev/null | awk '/^printer /{print $2}'); do
        queue_is_ours "$q" && targets="$targets $q"
    done
    if [ -z "$targets" ]; then
        info "no queue on this system uses this driver"
    else
        for q in $targets; do
            $SUDO lpadmin -x "$q" && { ok "removed queue '$q'"; removed_any=1; } \
                || die "could not remove queue '$q'"
        done
    fi
else
    if lpstat -p "$QUEUE" >/dev/null 2>&1; then
        if queue_is_ours "$QUEUE"; then
            $SUDO lpadmin -x "$QUEUE" && { ok "removed queue '$QUEUE'"; removed_any=1; } \
                || die "could not remove queue '$QUEUE'"
        else
            die "a queue named '$QUEUE' exists but does not use this driver.

It belongs to something else, so it has been left alone. If you meant a
different queue, pass --queue <name>; to remove every queue that does use this
driver, pass --all." 3
        fi
    else
        info "no queue named '$QUEUE'"
    fi
fi

step "2. Driver files"
if [ -e "$INSTALL_DIR" ]; then
    $SUDO rm -rf "$INSTALL_DIR" && { ok "removed $INSTALL_DIR"; removed_any=1; } \
        || die "could not remove $INSTALL_DIR"
else
    info "$INSTALL_DIR is not present"
fi

step "Done"
if [ "$removed_any" -eq 1 ]; then
    echo "  The driver is gone. Nothing belonging to Brother was touched, and any"
    echo "  other print queue you had is exactly as it was."
else
    echo "  Nothing to remove -- this driver was not installed."
fi
echo
echo "  Queues now on this system:"
lpstat -p 2>&1 | sed 's/^/    /'
