# Executed inside the private network namespace.
socat TCP4-LISTEN:8123,bind=127.0.0.1,reuseaddr,fork \
  UNIX-CONNECT:/run/emacs-broker/client.sock &
bridge_pid=$!
trap 'kill "$bridge_pid" 2>/dev/null || true' EXIT

for _ in {1..50}; do
  if curl --silent --output /dev/null http://127.0.0.1:8123/; then
    "$@"
    exit
  fi

  sleep 0.1
done

echo 'The Emacs broker bridge did not become ready.' >&2
exit 1
