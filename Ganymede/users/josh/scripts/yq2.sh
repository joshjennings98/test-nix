#!/usr/bin/env bash

# Interactive yq REPL. Prints the selected query to stdout.
# Supports -r flag for raw output mode.
# Intended to be wrapped by a shell function that handles commandline insertion.

set -eu

RAW=0
INPUT=""

if [ $# -eq 0 ] || { [ $# -eq 1 ] && [ "$1" = "-r" ]; }; then
    INPUT="$(mktemp)"
    trap 'rm -f "$INPUT"' EXIT
    cat > "$INPUT"
    [ $# -eq 1 ] && RAW=1
elif [ $# -gt 1 ] && [ "$1" = "-r" ]; then
    RAW=1
    INPUT="$2"
else
    INPUT="$1"
fi

PATHS="$(yq -o=json '.' "$INPUT" | \
    jq -r '
        [ path(..)
          | map(if type=="number" then "[]" else tostring end)
          | join(".")
          | split(".[]")
          | join("[]")
        ]
        | unique
        | map("." + .)
        | .[]
    ')"

QUERY="$(printf '%s\n' "$PATHS" | fzf \
    --preview-window='up:60%' \
    --query . \
    --preview "yq {q} \"$INPUT\"" \
    --bind "tab:replace-query" \
    --bind "enter:print-query+abort")" || exit 0

[ -n "$QUERY" ] || exit 0

if [ "$RAW" -eq 1 ]; then
    printf 'yq -r %s\n' "$QUERY"
else
    printf 'yq %s\n' "$QUERY"
fi
