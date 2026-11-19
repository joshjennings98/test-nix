
#!/usr/bin/env bash

set -eu

usage() {
  echo "usage: tmux-popup [--new] [--cwd DIR] [--stdin] -- command [args...]" >&2
  echo "  --stdin  read stdin and send it as literal keystrokes into the session" >&2
}

if [ -z "${TMUX:-}" ]; then
  echo "tmux-popup must be run from inside tmux" >&2
  exit 1
fi

DIR="$PWD"
NEW=0
SEND_STDIN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --new)
      NEW=1
      shift
      ;;
    --stdin)
      SEND_STDIN=1
      shift
      ;;
    --cwd)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      DIR="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

CMD_NAME_RAW="$(basename "$1")"
CMD_NAME="$(printf "%s" "$CMD_NAME_RAW" | tr -cd '[:alnum:]_.-')"
CMD_NAME="${CMD_NAME:-cmd}"

if [ "$NEW" -eq 1 ]; then
  HASH="$(printf "%s\0%s\0%s\0%s" "$DIR" "$*" "$$" "$(date +%s%N)" | md5sum | cut -c1-8)"
else
  HASH="$(printf "%s\0%s" "$DIR" "$*" | md5sum | cut -c1-8)"
fi

SESSION="popup-$CMD_NAME-$HASH"

tmux has-session -t "$SESSION" 2>/dev/null || {
  tmux new-session -d -s "$SESSION" -c "$DIR" "$@"
  tmux set-option -t "$SESSION" status off
  tmux set-option -s -t "$SESSION" extended-keys always
  tmux set-option -s -t "$SESSION" extended-keys-format csi-u
}

if [ "$SEND_STDIN" -eq 1 ]; then
  # Strip trailing newlines so the command isn't auto-submitted
  cat | perl -pe 'chomp if eof' | tmux load-buffer -
  tmux paste-buffer -t "$SESSION" -p
fi

tmux bind-key -n C-q if-shell -F '#{m/r:^popup-,#S}' \
  'detach-client' \
  'send-prefix; send-keys C-q'

if [ "$NEW" -eq 1 ]; then
  tmux display-popup -w80% -h80% -E \
    "tmux attach-session -t '$SESSION'; tmux kill-session -t '$SESSION' 2>/dev/null || true"
else
  tmux display-popup -w80% -h80% -E \
    "tmux attach-session -t '$SESSION'"
fi

