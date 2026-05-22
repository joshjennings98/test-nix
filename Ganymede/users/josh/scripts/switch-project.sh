#!/usr/bin/env bash
set -eu

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/Documents}"
HX="${HX:-hx}"

slugify() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed 's/[[:space:]_.:]\+/-/g' |
    sed 's/[^[:alnum:]_-]//g' |
    sed 's/--*/-/g; s/^-//; s/-$//'
}

if [ "$#" -eq 1 ]; then
  selected="$1"
else
  selected="$(
    find "$PROJECT_ROOT" -mindepth 1 -maxdepth 1 -type d |
      fzf
  )"
fi

[ -n "${selected:-}" ] || exit 0

root="$(realpath "$PROJECT_ROOT")"
selected="$(realpath "$selected")"

case "$selected" in
  "$root"/*) ;;
  *)
    printf 'Refusing path outside PROJECT_ROOT: %s\n' "$selected" >&2
    exit 1
    ;;
esac

parent_name="$(basename "$(dirname "$selected")")"
project_name="$(basename "$selected")"

name="$(slugify "${parent_name}-${project_name}")"

session="${name:-project}"

if ! tmux has-session -t "$session" 2>/dev/null; then
  tmux new-session -d \
    -s "$session" \
    -c "$selected" \
    -n "${name:-project}" \
    "$HX" .

  tmux set-option -t "$session" status off
fi

if [ -n "${TMUX:-}" ]; then
  exec tmux switch-client -t "$session"
else
  exec tmux attach-session -t "$session"
fi

