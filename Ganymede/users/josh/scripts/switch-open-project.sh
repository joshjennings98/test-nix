#!/usr/bin/env bash
set -eu

if [ -z "${TMUX:-}" ]; then
  echo "switch-open-project must be run inside tmux" >&2
  exit 1
fi

selected="$(
  tmux list-sessions -F '#S' |
    grep -v "^popup-" |
    fzf
)"

[ -n "${selected:-}" ] || exit 0

exec tmux switch-client -t "$selected"
