# Emacs sandbox

The normal `emacs` command and desktop entry run Doom inside Bubblewrap. The
editor and its subprocesses share a private network namespace, with only a
local bridge to the credential broker. This includes gptel-agent shell tools.

All Nix wiring is in `users/josh/nix/doom.nix`, imported by NixOS. It contains
the system broker service and the nested Home Manager Doom configuration.
`users/josh/configs/doom/broker` holds the Go source. The adjacent `scripts`
directory contains `launch.sh`, `bridge.sh` and `login.sh`; Nix supplies their
paths and policy and checks the assembled scripts with ShellCheck.

Nix supplies SCOWL's British English word list read-only at
`/usr/share/dict/words` inside the sandbox. This supports Ispell word completion
in text and gptel prompt buffers; it does not enable a separate spell-checker.

## Activation

Build and activate from a **host terminal**, after reviewing the configuration:

```sh
sudo nixos-rebuild switch --flake path:/home/josh/nix-config#Ganymede
```

Log out and back in so membership of `emacs-broker-clients` takes effect. Then
sign in from a host terminal:

```sh
emacs-broker-login github
emacs-broker-login openai
```

These commands use sudo to run a fresh browser sign-in as the broker's system
user. GitHub uses `gh`'s browser flow; OpenAI prints a fresh sign-in link to open
in your browser. Neither command imports existing credentials. GitHub's
`--insecure-storage` means its credential is stored as a file, inside the
broker's private directory, rather than using your desktop keyring.

Restart Emacs using the normal launcher. Authenticated GitHub operations and
gptel requests use the broker; Emacs receives no account token. This OpenAI route
targets the subscription backend used by gptel OAuth, not the paid API endpoint.
Account eligibility and live requests still need checking after sign-in.

If sign-in stops working, repeat the corresponding host login command. Do not
paste tokens into Emacs or the Nix configuration. Check service health with
`systemctl status emacs-broker`; the broker does not log request bodies or tokens.

## Files and persistence

Writable roots are `~/Documents`, `~/go`, `~/.cache/go-build`, `~/nix-config` and
the new editor state at `~/.local/share/emacs-sandbox`. Downloads and the rest of
your home are absent. Symlinks cannot expose paths that are not mounted.
Go and editor state are persisted. Existing Emacs state is not copied, so old
sessions, histories and Custom settings do not automatically appear.

Broker credentials live under `/var/lib/emacs-broker`, persisted separately,
owned by the broker user with directory mode 0700. Only its runtime directory (containing the client socket) is
mounted into Emacs. Credentials never go in the Nix store. The Nix store itself
is readable inside the sandbox, as needed to run Emacs and tools.

Change `programs.emacs-sandbox.writableDirectories` in
`users/josh/nix/doom.nix` to adjust trusted roots. Those directories
must exist before launch; the launcher creates its Go and editor state folders.

## Network policy

| Operation | Permitted destination |
| --- | --- |
| gptel | Fixed ChatGPT subscription responses endpoint |
| Git clone/fetch/push | GitHub smart HTTP, any repository your broker login can access |
| Public Go dependencies | Go module proxy, checksum service and its signed Google Storage ZIP downloads |
| Agent web search | DuckDuckGo HTML search |
| Agent page fetch | Exact hosts in `services.emacs-broker.pageHosts` |

GitHub HTTPS, `git@github.com:…` and `ssh://git@github.com/…` remotes are rewritten
to the broker. SSH keys and the host SSH agent are not exposed. GitHub API, LFS,
other Git hosts and private Go module workflows are not implemented. Local Git
operations work normally; signing that needs host keys is unavailable.

Page queries and fragments are stripped. Userinfo, non-HTTPS URLs, unknown
hosts, private IP addresses and ordinary redirects are rejected. Some pages
will therefore fail. Change the page host list in `users/josh/nix/doom.nix` and
rebuild to permit another site. There is no one-off approval UI yet.

Daemon/emacsclient workflows, TRAMP, host browser opening and Nix builds inside
Emacs are not supported by this initial launcher. Use a host terminal for Nix.
Terminal Emacs and the existing local X11 display are supported by the launcher;
Wayland sockets are not currently passed through.

## What this protects

The filesystem and network restrictions apply even if an Emacs package or an
agent shell command ignores the Lisp tool approval settings. Host D-Bus, Docker,
Nix daemon and SSH agent sockets are absent. Broker requests cannot retrieve
credentials or choose arbitrary credential-bearing destinations.

This is not a guarantee against data exfiltration. Anything readable by Emacs
can still be included in model prompts, search queries, permitted URL paths or
GitHub pushes. GitHub is a host allowlist, not a repository allowlist. A token
stolen from the broker would still be a bearer credential, not machine-bound.

X11 access is a weaker desktop boundary: a malicious GUI client may interact
with other desktop clients. Trusted writable projects/configuration can also
affect host tools that later execute them. Do not treat this launcher as full
containment for arbitrary malicious code on the desktop.

## Validation

`go test -race ./...` in `users/josh/configs/doom/broker` covers route restrictions,
header filtering, synthetic credential permissions, streaming and error-body
handling. `users/josh/configs/doom/broker/sandbox-smoke.sh` takes the built broker,
Bubblewrap and socat executable paths and checks a fresh synthetic fixture:
trusted read/write, hidden Downloads and credentials, missing host sockets,
blocked direct networking and reachable broker with denied unauthorised routes.
It leaves the synthetic fixture in `/tmp` for inspection.

The smoke test exercises the isolation boundary without a display; it does not
prove a working GUI session or an authenticated GitHub push/OpenAI response.

## Enterprise Responses proxy

The default remains ChatGPT subscription sign-in. To use an enterprise proxy
instead, configure these NixOS options in your machine configuration:

```nix
services.emacs-broker.model = {
  endpoint = "https://your-proxy.example/v1/responses";
  tokenFile = "/var/lib/emacs-broker/enterprise-token";
  name = "your-enterprise-model";
};
```

Use the full Responses endpoint and the model identifier your proxy accepts.
The proxy must support streaming Responses with `Authorization: Bearer …`.
It must be reachable at a public HTTPS address on port 443; private-network
addresses, HTTP, URL credentials, query parameters and redirects are rejected.
The endpoint is fixed by Nix, not supplied by the editor. No extra web host
allowlist entry is needed for it.

Provision the token file on the host using your normal secret-management
process. Store only the token, optionally followed by a newline. Keep the file
root-owned with mode `0600`, outside Documents, the repository and all other
editor mounts. The example directory is already persisted. Do not put a token
literal or `builtins.readFile` in Nix: that would copy the secret into the store.
The option is a quoted runtime path, not a Nix path literal.

systemd loads the file as the private `model-token` service credential. The
broker reads it at startup; Emacs receives neither the token nor its file.
The token is sent only on the fixed model route, without ChatGPT account or
OAuth headers. Browser sign-in is disabled in this mode, and there is no
fallback to an existing subscription token. Requests force `store: false` and
`stream: true`, and remove `previous_response_id` and `conversation`; gptel
sends the conversation context on each request. This does not control logging
or retention by the enterprise proxy itself.

After provisioning the file, activate your NixOS configuration and restart
Emacs. To rotate the token, replace the host file and restart `emacs-broker`.
Existing editors can make new requests after the restart; requests in flight
may fail and need retrying. The runtime directory is preserved across service
restarts and mounted read-only, so socket replacement remains visible. An
explicit stop followed by start can recreate the directory and requires
restarting Emacs.
Remove both `endpoint` and `tokenFile` to return to subscription sign-in.
Billing and access are determined by the enterprise proxy account.

Nix-managed agent skills are mounted read-only at `~/.agents/skills` directly
from the Nix store, matching the Home Manager source. Other host `.agents`
contents remain outside the sandbox. Restart Emacs after updating those skills.
