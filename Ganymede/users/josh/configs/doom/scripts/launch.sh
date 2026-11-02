# Paths and static sandbox arguments are supplied by doom.nix.
for argument in "$@"; do
  case "$argument" in
    --daemon*|--bg-daemon*|--fg-daemon*)
      echo 'Daemon mode is not supported by this sandbox launcher yet.' >&2
      exit 2
      ;;
  esac
done

if [[ ! -S /run/emacs-broker/client.sock ]]; then
  echo 'The emacs-broker service is unavailable. Activate the NixOS configuration first.' >&2
  exit 1
fi

mkdir -p "${state_directories[@]}"

# Preserve the working directory only when it is inside a trusted root.
workdir="$editor_home/Documents"
for directory in "${writable_directories[@]}"; do
  case "$PWD/" in
    "$directory/"*) workdir="$PWD" ;;
  esac
done

# X11 is optional, so terminal sessions do not need a display socket.
display_args=()
if [[ -n "${DISPLAY:-}" ]]; then
  if [[ ! "$DISPLAY" =~ ^:[0-9]+(\.[0-9]+)?$ ]]; then
    echo 'Only local X11 displays are supported.' >&2
    exit 2
  fi

  display_args+=(
    --ro-bind /tmp/.X11-unix /tmp/.X11-unix
    --setenv DISPLAY "$DISPLAY"
  )

  authority="${XAUTHORITY:-$editor_home/.Xauthority}"
  if [[ -f "$authority" ]]; then
    display_args+=(
      --ro-bind "$authority" /run/emacs/Xauthority
      --setenv XAUTHORITY /run/emacs/Xauthority
    )
  fi
fi

# Start with empty namespaces, then mount only the configured paths.
sandbox_args=(
  --unshare-all
  --die-with-parent
  --new-session
  --cap-drop ALL
  --clearenv
  --proc /proc
  --dev /dev
  --tmpfs /tmp
  --dir /run/emacs
  --dir "$editor_home"
)

for directory in "${read_only_paths[@]}"; do
  sandbox_args+=(--ro-bind "$directory" "$directory")
done

sandbox_args+=(
  --ro-bind "$agent_skills" "$editor_home/.agents/skills"
  --ro-bind "$git_config" /etc/emacs-gitconfig
  # Ispell's text completion discovers this standard path when Emacs starts.
  --ro-bind "$word_list" /usr/share/dict/words
  --bind "$editor_state" "$editor_state"
)

for directory in "${writable_directories[@]}"; do
  sandbox_args+=(--bind "$directory" "$directory")
done

exec "$bubblewrap" \
  "${sandbox_args[@]}" \
  "${environment_args[@]}" \
  "${display_args[@]}" \
  --setenv TERM "${TERM:-xterm-256color}" \
  --chdir "$workdir" \
  "$bridge_script" "$emacs" "$@"
