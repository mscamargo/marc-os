#!/usr/bin/env bash
# lib/log.sh — colored logging primitives and root-guard. No deps.
[[ -n ${__LIB_LOG_SOURCED:-} ]] && return 0
__LIB_LOG_SOURCED=1

readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'

# log::info <msg> — print arrow-prefixed message to stdout.
log::info() {
    printf "${C_BLUE}==>${C_RESET} %s\n" "$1"
}

# log::warn <msg> — print WARN-prefixed message to stdout.
log::warn() {
    printf "${C_YELLOW}WARN:${C_RESET} %s\n" "$1"
}

# log::error <msg> — print ERROR-prefixed message to stderr.
log::error() {
    printf "${C_RED}ERROR:${C_RESET} %s\n" "$1" >&2
}

# log::success <msg> — print green arrow-prefixed message to stdout.
log::success() {
    printf "${C_GREEN}==>${C_RESET} %s\n" "$1"
}

# log::die <msg> — print error to stderr and exit 1.
log::die() {
    log::error "$1"
    exit 1
}

# log::assert_non_root — exit 1 if running as root.
log::assert_non_root() {
    [[ "$EUID" -ne 0 ]] || log::die "Do not run this script as root. It will use sudo when needed."
}
