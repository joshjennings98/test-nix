#!/usr/bin/env bash

# Copy a KeePassXC password to clipboard, or if the entry has an "envvar" tag,
# print "ENVVAR\tNAME\tVALUE" to stdout for the shell wrapper to set as an env var.

set -eu

DB="${1:-}"

if [ -z "$DB" ]; then
    DB="$(find ~ -type f -not -path "*/.git/*" -name "*.kdbx" 2>&1 | grep -v "Permission denied" | fzf)"
fi

[ -n "$DB" ] || exit 0

read -r -s -p "Password for $DB: " PASSWORD
echo >&2

ENTRIES="$(printf '%s\n' "$PASSWORD" | keepassxc-cli ls -q "$DB")"
ENTRY="$(printf '%s\n' "$ENTRIES" | fzf)"

[ -n "$ENTRY" ] || exit 0

TAGS="$(printf '%s\n' "$PASSWORD" | keepassxc-cli show -q "$DB" "$ENTRY" -a Tags)"

if printf '%s\n' "$TAGS" | grep -q "envvar"; then
    VALUE="$(printf '%s\n' "$PASSWORD" | keepassxc-cli show -q "$DB" "$ENTRY" -a Password)"
    printf 'ENVVAR\t%s\t%s\n' "$ENTRY" "$VALUE"
else
    echo "Password copied to clipboard for 10 seconds"
    printf '%s\n' "$PASSWORD" | keepassxc-cli clip -q "$DB" "$ENTRY"
    echo "Clipboard cleared"
fi
