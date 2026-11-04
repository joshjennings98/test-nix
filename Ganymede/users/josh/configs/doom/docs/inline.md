# Inline Agent Shell

`agent-shell-inline.el` is adapted from
[Karthik Chikmagalur's gptel-inline.el](https://github.com/karthink/gptel-inline/blob/master/gptel-inline.el).
It keeps the original GPL licence and attribution. The upstream file's SHA256
is recorded in the source header. The backend uses the pinned Agent Shell
0.91.1 APIs; it does not install or load gptel.

## Everyday use

Select some code and press `SPC a p`. A small prompt window opens below your
source. Enter your question, press `Esc`, then `RET` or `SPC m s` to send.
In insert state, `RET` adds a newline. The prompt closes and the answer streams beside
your source. The conversation stays in the background.

The extension reuses your last conversation for that source buffer, otherwise
an Agent Shell session in the current project. If none exists, it asks you to
choose an agent and starts one without displaying its buffer. Authentication
still follows that agent's normal setup.

`SPC m h` toggles the original-style options table above the prompt, keeping
focus in the composer. Keys are highlighted and show the Doom bindings. The
header links to the active conversation and shows the selected context and
prompt controls. Closing the prompt also closes its options panel.

For a quick message without the prompt window or source context, use `SPC a m`.
Type the message in the minibuffer; its reply also appears inline.

## Prompt controls

| Key | Doom local leader | Action |
| --- | --- | --- |
| `RET` in normal state | `SPC m s` | Send prompt and reference |
| `C-c SPC` | `SPC m c` | Cycle source reference; repeat with `.` |
| `C-c C-a` | `SPC m a` | Append to shell input without submitting |
| `C-c C-b` | `SPC m b` | Select another conversation or create a new one |
| `C-c C-v` | `SPC m v` | Visit the conversation |
| `C-c C-k` | `SPC m q` | Discard the prompt |
| `C-c ?` | `SPC m h` | Help |

Reference cycling offers the selection, no reference, and things such as the
current function, line, paragraph, visible window or buffer. The highlight
shows exactly what will be attached. With a prefix argument, append leaves an
empty prompt open so you can collect another part. Send then submits the
accumulated shell input and the final prompt.

An agent that is busy or waiting for permission leaves your inline draft open.
Visit the conversation if you want Agent Shell's queue or steering controls.
A prompt sent during startup waits for initialisation; clearing its preview
before that completes cancels the pending send.

## Response controls: SPC a e

Press `SPC a e n` once for temporary preview navigation:

- `j/k`: scroll down/up without moving the source cursor.
- `J/K`: next/previous conversation reply, in the same preview.
- `C-d/C-u`: page down/up.
- `g`: return to this preview's live reply.
- `Esc` or `q`: exit navigation. Any other editing command also exits and runs normally.

These keys only take over while navigation is active. Mouse wheel scrolling
continues to work directly over the preview. History comes from Agent Shell,
including replies sent in its conversation window. Browsing does not resend,
rewind or fork the conversation; a new reply still continues the live session.
At the newest reply, `J` stops. While reading history, the live response can
continue streaming separately. Copy copies the reply currently displayed.

| Key | Action |
| --- | --- |
| `n` | Enter temporary navigation |
| `o` | Action menu: reply, review, copy, clear, interrupt, resize |
| `v` | Visit conversation, jumping to pending permission/question controls |
| `j/k` | Scroll by line |
| `J/K` | Next / previous conversation reply |
| `D/U` | Page down / up |
| `y` | Copy the full response, including off-screen lines |
| `c` | Clear preview without stopping the agent |
| `x` | Interrupt the agent (retains its confirmation policy) |

`C-c C-o` also opens response actions. Mouse scrolling and dragging the preview
are retained. Use the action menu's reply, or `C-u SPC a p`, to continue from
an existing preview. `C-g` returns from the conversation to the source layout.
Opening the action menu shows its highlighted choices directly in the response
header. After resizing, repeat with `+`/`-`, or use `0` to reset the height.
Follow-up replies keep the preview's dragged position and height, including
when it was dragged into another buffer. New previews start at the cursor.
The context highlight belongs to the draft and clears after a successful send.
Prompt text wraps automatically. Response previews wrap to the available window
width and scroll by displayed lines, without changing source-buffer truncation
or copied response text. Separate agent messages receive paragraph breaks,
including messages separated by thinking or tool activity.

Permissions and question forms show “Review required” in the preview. They are
handled in Agent Shell's native UI, not automatically accepted. A normal reply
or completed response never opens the conversation window on its own.

## Differences from gptel-inline

The composer is an independent buffer, so widening it cannot expose the backing
conversation. Use visit instead. All requests use the ACP session's history;
selecting text in the prompt does not create a history-free request. Select
“New agent shell” when you want a fresh conversation. Tool activity is shown
as status; detailed tool output, diffs and review controls live in Agent Shell.

No Alt-only shortcut is required: i3 keeps its existing bindings. In particular,
Alt+Return is not used, and repeating reference selection uses `.` rather than
Space so Doom's leader keeps working.

## Testing

`tests/inline.el` uses `tests/mock-acp.py`, a local deterministic ACP server.
Run it with the Nix-built editor's `--batch`, a writable `XDG_CACHE_HOME`, and
`AGENT_SHELL_TEST_PYTHON` pointing to Python 3:

```sh
emacs --batch -l users/josh/configs/doom/tests/inline.el -f ert-run-tests-batch-and-exit
```

These tests do not contact a provider. The interactive Doom startup checks also
cover the inline prompt's effective bindings and source-reference selection.
