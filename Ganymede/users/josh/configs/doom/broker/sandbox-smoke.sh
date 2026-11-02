#!/usr/bin/env bash
# Run on Linux with the built broker, bubblewrap and socat as positional arguments.
set -euo pipefail
broker=$1
bwrap=$2
socat=$3
shell=$(readlink -f "$(command -v bash)")
curl=$(readlink -f "$(command -v curl)")
fixture=$(mktemp -d /tmp/emacs-isolation.XXXXXXXX)
mkdir -p "$fixture/home/Documents" "$fixture/home/Downloads" "$fixture/credentials" "$fixture/runtime" "$fixture/skills/example"
printf 'Synthetic skill\n' > "$fixture/skills/example/SKILL.md"
printf 'project\n' > "$fixture/home/Documents/allowed"
printf 'synthetic-download\n' > "$fixture/home/Downloads/hidden"
printf 'synthetic-credential\n' > "$fixture/credentials/hidden"
printf '{"socket":"%s/client.sock","state":"%s/credentials","pageHosts":["go.dev"]}\n' "$fixture/runtime" "$fixture" > "$fixture/policy.json"
"$broker" --config "$fixture/policy.json" &
broker_pid=$!
trap 'kill "$broker_pid" 2>/dev/null || true' EXIT
for attempt in {1..50}; do
  if [[ -S "$fixture/runtime/client.sock" ]]; then break; fi
  sleep 0.1
done
test -S "$fixture/runtime/client.sock"

"$bwrap" --unshare-all --die-with-parent --new-session --cap-drop ALL --clearenv \
  --ro-bind /nix/store /nix/store --proc /proc --dev /dev --tmpfs /tmp \
  --dir /home/test --dir /run/emacs \
  --bind "$fixture/home/Documents" /home/test/Documents \
  --ro-bind "$fixture/runtime" /run/emacs-broker \
  --ro-bind "$fixture/skills" /home/test/.agents/skills \
  --setenv HOME /home/test --chdir /home/test/Documents \
  "$shell" -euo pipefail -c '
    socat=$1
    curl=$2
    host_fixture=$3
    [[ $(< allowed) == project ]]
    [[ -r /home/test/.agents/skills/example/SKILL.md ]]
    [[ ! -w /home/test/.agents/skills/example/SKILL.md ]]
    printf "write succeeded\n" > written
    [[ ! -e /home/test/Downloads && ! -e "$host_fixture/credentials/hidden" ]]
    [[ ! -e /run/user && ! -e /nix/var/nix/daemon-socket/socket ]]
    [[ ! -e /run/docker.sock && ! -e /run/dbus/system_bus_socket ]]
    "$socat" TCP4-LISTEN:8123,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:/run/emacs-broker/client.sock &
    bridge=$!
    trap '\''kill "$bridge" 2>/dev/null || true'\'' EXIT
    for attempt in {1..100}; do
      status=$("$curl" --silent --max-time 1 --output /dev/null --write-out "%{http_code}" http://127.0.0.1:8123/) && break
    done
    [[ "$status" == 403 ]]
    [[ $("$curl" --silent --output /dev/null --write-out "%{http_code}" "http://127.0.0.1:8123/page?url=https%3A%2F%2Fexample.invalid") == 403 ]]
    [[ $("$curl" --silent --output /dev/null --write-out "%{http_code}" -H "Content-Type: application/json" --data "{}" http://127.0.0.1:8123/openai/responses) == 401 ]]
    if "$curl" --silent --connect-timeout 1 --max-time 2 https://1.1.1.1/ > /dev/null; then
      printf "Direct network access unexpectedly succeeded\n" >&2
      exit 1
    fi
    printf "PASS: trusted file read/write; hidden downloads and credentials; host sockets hidden; direct network blocked; broker reachable and rejects unauthorised routes.\n"
  ' smoke "$socat" "$curl" "$fixture"
test -f "$fixture/home/Documents/written"
printf 'Synthetic fixture retained at %s\n' "$fixture"
