#!/usr/bin/env bash
# lib/lists.sh — iterate a TAB-separated package list file.
[[ -n ${__LIB_LISTS_SOURCED:-} ]] && return 0
__LIB_LISTS_SOURCED=1

__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/log.sh
source "$__LIB_DIR/log.sh"
unset __LIB_DIR

# lists::for_each_row <list_file> <callback> — read <list_file> line by line,
# skip blanks and #-prefixed comments, split each remaining row on TAB into
# name + description, and invoke `<callback> <name> <description>`. Runs the
# callback in the current shell so it can mutate caller state (counters).
# Aborts via log::die on a malformed row (missing TAB or empty name).
lists::for_each_row() {
    local list="$1" cb="$2"
    [[ -f "$list" ]] || log::die "list file not found: $list"
    local line name desc lineno=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == \#* ]] && continue
        IFS=$'\t' read -r name desc <<< "$line"
        [[ -n "$name" && -n "$desc" ]] \
            || log::die "$list:$lineno: malformed row (expected name<TAB>description)"
        "$cb" "$name" "$desc"
    done < "$list"
}
