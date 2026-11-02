# Run on the host, as the broker user, with a fresh environment.
umask 077

case "${1:-}" in
  openai)
    login_args=("$broker" --config "$policy" --login-openai)
    ;;
  github)
    login_args=(
      "$github_cli" auth login
      --hostname github.com
      --git-protocol https
      --web
      --insecure-storage
    )
    ;;
  *)
    echo 'Usage: emacs-broker-login openai|github (run in a host terminal)' >&2
    exit 2
    ;;
esac

exec /run/wrappers/bin/sudo -u emacs-broker \
  "$environment" -i \
  HOME="$credential_directory" \
  GH_CONFIG_DIR="$credential_directory/github" \
  PATH="$login_path" \
  SSL_CERT_FILE="$certificates" \
  "${login_args[@]}"
