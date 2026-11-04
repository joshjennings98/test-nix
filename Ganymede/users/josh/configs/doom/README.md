# Doom Emacs

[Nix configuration](../../nix/doom.nix) installs Doom, Go tools and `codex-acp`.
Agent Shell and its ACP and shell-maker dependencies are pinned to upstream
revisions in `packages.el`. Update those pins together when upgrading.

Apply the configuration with the usual NixOS rebuild and restart Emacs.
Nix manages the packages; a separate `doom sync` is unnecessary.

Nix supplies Aspell's English dictionaries and a British English plain word
list for Ispell completion in text and agent prompt buffers.

Use `SPC a` for sessions and source context, and `SPC m` inside agent buffers
for prompts, settings, permissions, queues and review. `SPC a ?` searches all
Agent Shell commands. In insert state, use `M-SPC` as the leader.
See the [complete keyboard guide](docs/keys.md) for the shell, viewport,
compose and diff-review bindings.
Use `SPC a p` for an inline source discussion or `SPC a m` for a quick message
without displaying the conversation. The separate
[`agent-shell-inline.el`](agent-shell-inline.el) extension is adapted from
gptel-inline; see the [inline workflow guide](docs/inline.md).
`M-x agent-shell` offers the standard agent selector. Codex's ACP adapter is
installed; other agents require their corresponding executables on PATH.
Authentication and permission prompts use the selected agent's normal flow.
See the [upstream setup guide](https://github.com/xenodium/agent-shell#setup).

Emacs launches normally with the user's filesystem and network access.
Existing runtime state and credentials are left untouched by this change.

The Go editing configuration retains Eglot, all seven inlay hints, import
organisation, formatting, tree-sitter text objects and the existing editing
keys. The interactive startup regression check is
[`doom-startup.el`](../../tests/doom-startup.el).
