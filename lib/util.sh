#!/usr/bin/env bash
# lib/util.sh — small shell utilities. No deps.
[[ -n ${__LIB_UTIL_SOURCED:-} ]] && return 0
__LIB_UTIL_SOURCED=1

# util::has_command <name> — return 0 if <name> is on PATH.
util::has_command() {
    command -v "$1" &> /dev/null
}
