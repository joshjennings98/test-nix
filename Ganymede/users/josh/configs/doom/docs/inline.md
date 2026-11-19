# Inline Agent Shell

`agent-shell-inline.el` is adapted from
[Karthik Chikmagalur's gptel-inline.el](https://github.com/karthink/gptel-inline/blob/master/gptel-inline.el).
It keeps the original GPL licence and attribution. The upstream file's SHA256
is recorded in the source header. The backend uses the pinned Agent Shell
0.91.1 APIs; it does not install or load gptel.

## Everyday use

In minimal Emacs (`emacs2`), `SPC a L` picks a conversation and opens a fresh
inline preview and draft at point. `SPC a S` changes the selected preview or
draft's session, just like clicking the highlighted shortcut beside its name. `SPC a c` selects the next
preview in the current buffer; `SPC a C` cycles across buffers. Cycling does not
send a prompt or open a draft. Reply and quick-message commands use the selected
preview, even when several share a source line. Region sending is `SPC a i r`.
These bindings are defined separately from Doom's bindings below.

Use `SPC a P` to select an existing preview, bringing it into view if necessary. Repeated presses cycle
through previews across open buffers. It does not create a new preview.

Completed turns show a persistent Dunst notification when you are elsewhere.
Notification requests and dismissal do not wait for Dunst. Clicking an alert
opens the reply after the D-Bus callback returns. Agent Shell does not inhibit
system sleep.

On i3, clicking also requests focus for the specific Emacs window, including
when it is on another workspace. This request does not block Emacs.

Pixel scrolling remains enabled. Wheel input over an inline reply scrolls only
the reply and stops at either end. Move the pointer outside the reply to scroll
the document past it. Document scrolling uses Emacs' pixel scrolling with two
corrections at the preview anchor: upward measurement excludes virtual rows
already traversed, and downward movement retains the offset into the anchor's
text row. Both use the current layout, including wrapped lines and resized
previews. The cursor can remain below the reply.

Session names are faint, while reply text retains its normal styling. The focused
preview's session name is also bold. Creating or cycling to a preview moves this
emphasis. Plain response labels and session names remain draggable; clicking them
focuses the preview without activating an action. Cycling leaves an already-visible
preview in place and only reveals previews that are off-screen. Scrolling another preview with the
wheel or its arrow controls does not move focus, select its window or move the
source cursor.

The reply, header controls and conversation name wrap to the window width.
Sideways wheel gestures over the reply do not shift the document. Use `SPC a P`
to revisit a preview and reset its horizontal alignment.

Click it to focus Emacs and centre that conversation's inline response; if the
preview was closed, the conversation buffer opens instead. Returning to the
matching shell, viewport, or visible current inline response dismisses its
alert. Reading older history or leaving the preview off-screen does not.
You can also dismiss the alert manually. Notifications do not take over Enter.

Tool output previews retain at most 32,768 characters plus a truncation notice.
This limit also affects the Emacs transcript, but does not change the tool result
received by the agent. Redirect large command output to a file when you need
the complete log. Inline tool titles show a short, single-line preview.

Agent sessions also receive an `emacs-navigation` MCP server. Ask, for example,
“Find where authentication is configured and take me there.” The agent can
search with its usual tools, then use `open_file` with an absolute path and
optional one-based line/column, or `list_buffers` and `switch_buffer` for an
already open buffer. Navigation centres the location in a source window,
creating a split if only the agent is visible.

This requires rebuilding Doom and starting a new agent session after installation.
The server starts on demand in the running Emacs; Nix provides `socat` for its
local socket connection. `M-x mcp-server-status` reports the server status.

Select some code and press `SPC a p`. A small prompt window opens below your
source. Enter your question, press `Esc`, then type `:wq` and press `RET` to send.
In insert state, `RET` adds a newline. The prompt closes and the answer streams beside
your source. The conversation stays in the background.

Use `SPC a l` to continue your most recently selected inline conversation at the cursor,
including in another file such as the generated Org review. Write your follow-up
and send with `:wq`; the reply appears in that file with the same conversation
history. This does not select the separate reviewer session unless you last used
that session for an inline message. Closed conversations are skipped.

Completed previews keep their original replies when new turns are sent elsewhere.
A newer-reply count appears with a clickable **Latest reply** action,
available without entering navigation. It updates only that preview and follows
the latest turn if it is still streaming. Previous/next still browse the full
history of that preview's conversation.

Click the highlighted shortcut beside the conversation name to choose another
session for that preview. Other previews keep their sessions. The same shortcut
in the composer changes that draft's destination; `SPC m v` still visits its conversation.

Drag a preview vertically to move it immediately, even while the pointer remains
inside it. Dragging measures displayed line heights and preserves where you grabbed
the preview, including across windows. Navigation controls are clickable while their
temporary keymap is active, with keys highlighted like the options panel.
Pending permissions show **Approve** (the oldest request) and **Approve all**
(all requests currently waiting in that conversation). In emacs2 their highlighted
shortcuts are `SPC a y` and `SPC a Y`; Latest reply uses `SPC a g`. Only the
highlighted shortcut is clickable; the label is plain text. Both approvals allow once; they
leave other conversations and future requests unchanged.

The status text reports work, review requests and completion without a separate
waiting animation. Transport checks still report disconnected agents. Streamed
chunks are rendered together at most every 100 ms, with completion rendered immediately.

An empty or whitespace-only draft closes without sending, even with source
context selected. If sending fails or the agent is busy, the draft stays open and the previous
preview remains available.

The extension reuses your last conversation for that source buffer, otherwise
an Agent Shell session in the current project. If none exists, it asks you to
choose an agent and starts one without displaying its buffer. Authentication
still follows that agent's normal setup.

`SPC m h` toggles the original-style options table above the prompt, keeping
focus in the composer. Keys are highlighted and show the Doom bindings. The
header links to the active conversation and shows the selected context and
prompt controls. Closing the prompt also closes its options panel.

For a quick message without the prompt window or source context, use `SPC a m`.
Type the message in the minibuffer. It continues the nearest existing preview
in the current buffer, including off-screen previews, using that conversation.
If there is no preview, its reply appears in a new box at the cursor.

## Prompt controls

| Key | Doom local leader | Action |
| --- | --- | --- |
| `:wq` in normal state | — | Send draft and reference; close if empty |
| `C-c SPC` | `SPC m c` | Cycle source reference; repeat with `.` |
| `C-c C-a` | `SPC m a` | Append to shell input without submitting |
| `C-c C-b` | `SPC m b` | Select another conversation or create a new one |
| `C-c C-v` | `SPC m v` | Visit the conversation |
| `C-c C-k` | `:q` (or `SPC m q`) | Discard the prompt |
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

## Response controls: SPC a

Press `SPC a n` once for temporary preview navigation:

- `j/k`: scroll down/up without moving the source cursor.
- `J/K`: next/previous conversation reply, in the same preview.
- `C-d/C-u`: page down/up.
- `g`: return to this preview's live reply.
- `Esc` or `q`: exit navigation. Any other editing command also exits and runs normally.

The highlighted shortcut portions of reply, navigate and more are clickable, as are
the scroll arrows. In navigation mode, click any labelled action to scroll,
browse replies, return to the live reply or exit. Clicks act on that preview;
scrolling keeps your source cursor in place. The response body can still be dragged.

These keys only take over while navigation is active. Mouse wheel scrolling
over the preview affects only the reply and stops at either end. Scroll outside
the preview to scroll the source document. History comes from Agent Shell,
including replies sent in its conversation window. Browsing does not resend,
rewind or fork the conversation; a new reply still continues the live session.
At the newest reply, `J` stops. While reading history, the live response can
continue streaming separately. Copy copies the reply currently displayed.

If a small document wheel scroll stalls at the preview's attachment line,
the window skips past that display block. This works in either direction,
when the pointer is outside the preview. The preview stays attached
to the source and is visible again when you return to it.

| Key | Action |
| --- | --- |
| `n` | Enter temporary navigation |
| `o` | Action menu: reply, review, copy, clear, interrupt, resize |
| `v` | Review pending permissions here; otherwise visit the conversation/question form |
| `j/k` | Scroll by line |
| `D/U` | Page down / up |
| `x` | Interrupt the agent (retains its confirmation policy) |

In the action menu (`SPC a o`), `y` copies the full displayed response,
`c` clears the preview without stopping the agent, and `+`/`-` resize it.
Browse reply history with `J/K` after entering navigation (`SPC a n`).

`C-c C-o` also opens response actions. Mouse scrolling and dragging the preview
are retained. Use `SPC a r` to reply to an existing preview, then `Esc :wq RET`
to send. The action menu's reply and `C-u SPC a p` also work.
`SPC a S` sends the selected region to Agent Shell.
`C-g` returns from the conversation to the source layout.
Opening the action menu shows its highlighted choices directly in the response
header. After resizing, repeat with `+`/`-`, or use `0` to reset the height.
Follow-up replies keep the preview's dragged position and height, including
when it was dragged into another buffer. New previews start at the cursor.
The context highlight belongs to the draft and clears after a successful send.
Prompt text wraps automatically. Response previews wrap to the available window
width and scroll by displayed lines, without changing source-buffer truncation
or copied response text. Separate agent messages receive paragraph breaks,
including messages separated by thinking or tool activity.

Permissions show “Review required” in the preview without opening a popup or
capturing editing keys. Press `SPC a v` (or click review in the preview's action
menu) to review that conversation's pending requests beside your source. The
source window stays selected; the backing chat buffer stays in the background.

Inside the permission menu, `y` allows once, `!` always allows when the agent
offers that option, and `n` rejects and interrupts that conversation. `p`/`N`
cycle requests only within that conversation. `q`, `Esc` and `C-g` defer without
answering and restore your editing keys. A resolved or replaced request closes
its menu instead of silently assigning the approval key to another request.

The menu includes a shortened summary. Use `i` for the full request, including
raw arguments and content; `q`/`Esc`/`C-g` return from this read-only view. Use
`v` for available diffs: ordinary Evil navigation and yank keys remain intact,
`SPC m a` accepts, `SPC m r` rejects, and `q`/`Esc`/`C-g` close without answering.
Reopen `SPC a v` after inspection or deferral to make a decision.

`B` asks for confirmation before bypassing permissions for that conversation's
session. It answers queued and future requests with `allow_once` where offered;
the setting resets on session cleanup or when the mode is disabled. The mode
refuses to disable while requests are pending; resolve or interrupt them first.

In a shell buffer, `C-c C-p` or `SPC m p p` opens the same manual menu. If the
preview was closed, `M-x agent-shell-permission-transient-menu` lets you select
a conversation with pending requests. Question forms still use Agent Shell's
native UI. A normal reply or completed response never opens the chat itself.

The permission extension is vendored from Jamie-Cui/agent-shell-permission-transient
at `02db0bc1155186ea61ea041f3945909697fa17d7`, with local changes for manual inline
review and session isolation. Its original licence is included in
`agent-shell-permission-transient.el`.

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
emacs --batch -l users/josh/configs/doom/tests/permissions.el -f ert-run-tests-batch-and-exit
```

These tests do not contact a provider. The interactive Doom startup checks also
cover the inline prompt's effective bindings and source-reference selection.
The permission suite also runs the inline suite and checks approval, rejection,
deferral, session isolation, full inspection, stale requests and Evil key handling.
