# Doom Emacs

[Nix configuration](../../nix/doom.nix) owns the editor, sandbox and broker
service. Lisp configuration lives here, Go broker source is in [broker](broker/),
and the launcher, bridge and login scripts are in [scripts](scripts/).

- [Sandbox setup and activation](docs/sandbox.md)
- [Doom/gptel data disclosure review](docs/data-review.md) — dated source review

Use the sandbox guide for the current setup; the dated security review records
the configuration as it stood when it was written.

## Keys alongside i3

See the [complete keyboard inventory](docs/keys.md) for every prompt, preview,
tool, rewrite, context, inspection and transient action in the pinned packages.

i3 keeps its Alt bindings. [keys.el](keys.el) puts the AI workflow under Doom's
leader instead, with no global Meta translation.

| Keys | Action |
| --- | --- |
| `SPC a p` | Discuss the visual selection or start an inline prompt |
| `SPC a g` | Open the agent |
| `SPC a v` | Visit the associated conversation in Evil normal state |
| `SPC a o` | Inline response actions: reply, copy, clear, resize |
| `SPC a s` | Send; uses inline send when editing an inline prompt |
| `SPC a m` | Request options |
| `SPC a c` | Cycle inline source reference (`.` repeats) |
| `SPC a a` / `b` / `h` | Append without sending / switch conversation / help |
| `SPC a RET` / `q` / `i` | Confirm / cancel / inspect in the current gptel interface |
| `SPC a r` / `R` | Rewrite / per-rewrite actions prefix |
| `SPC a t` | Tool selection, navigation and approval prefix |
| `SPC a d` / `@` / `C` | Instructions / presets / context list |
| `SPC a f` / `u` | Fold tool or code block / return from visited conversation |
| `SPC a y` | Copy curl command from query inspection |
| `SPC a j` / `SPC a k` | Scroll the preview down/up one line |
| `SPC a J` / `SPC a K` | Scroll the preview down/up one page |

The preview is display-only. Use `SPC a v` for normal Evil movement,
`C-d`/`C-u` scrolling, visual selection and `y` copying in the conversation.
Plain `j/k` in the source buffer still move through your code.

In the inline prompt, `C-c RET` sends, `C-c SPC` cycles the highlighted source
reference, and `C-c C-k` cancels. `C-c C-o` opens response actions while an
inline preview is active. gptel's former `M-RET` menu/minibuffer actions also
use `C-c RET`; their displayed hints are changed by the Nix package override.

Context lists use normal-state `j/k` to navigate, `RET` to visit, `d` to flag
removal and `q` to quit. Agent tool previews use normal-state `j/k` to move
between tools and `TAB` to fold. These bindings do not replace insert-mode
typing. Tool approval remains `C-c C-c`, rejection `C-c C-k`, and inspection
`C-c C-i`; moving or scrolling never approves a tool call.

[Offline interactive checks](tests/keys.el) exercise these bindings using
synthetic buffers and a fresh HOME, without sending model requests.
