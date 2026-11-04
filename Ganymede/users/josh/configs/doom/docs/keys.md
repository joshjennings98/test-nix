# Agent Shell in Doom

`SPC a` works from source buffers. `SPC m` is the local leader inside agent
buffers. In insert state use `M-SPC a` and `M-SPC m`. Which-key labels all menus.
`SPC a ?` (or `SPC m ?`) searches every public interactive Agent Shell command,
including provider launchers and less common commands without dedicated keys.
Commands retain upstream requirements: session features depend on the agent's
advertised capabilities, and buffer-specific commands need the appropriate view.

## From source buffers: SPC a

| Key | Action |
| --- | --- |
| `a`, `n`, `t`, `b` | Open, new, toggle, switch shell |
| `R`, `w` | Resume session, new worktree shell |
| `c`, `v` | Compose prompt, view last interaction |
| `r`, `d` | Send selection, send selection or diagnostic |
| `f`, `F` | Current file, choose another file |
| `i`, `s` | Clipboard image, screenshot |
| `p`, `m` | Inline source discussion, quick background message |
| `e` | Inline preview actions, review, scrolling and interruption |
| `?` | All Agent Shell commands |

The [inline workflow guide](inline.md) covers reference selection, prompt
bindings and response previews. In its prompt window, `SPC m` controls the
inline composer rather than the full conversation.
For repeated preview navigation, press `SPC a e n` once, then use `j/k` to
scroll, `J/K` for newer/older replies, `C-d/C-u` for pages, and `g` for the live
reply. `Esc`, `q`, or an ordinary editing command leaves navigation.

The send commands keep upstream behaviour: some insert context for a prompt
rather than submitting it immediately. Prefix arguments retain their upstream
meaning, including shell selection. Image commands need upstream's image tools.

## Agent shell: SPC m

| Key or prefix | Action |
| --- | --- |
| `s`, `S` | Submit/queue, override busy submission (upstream defaults to steering) |
| `x` | Interrupt and reject pending permission requests |
| `c`, `r`, `o` | Compose, quote selection, switch shell/viewport |
| `m m/c/v/t/o` | Mode, cycle mode, model, thought level, any ACP option |
| `p p/j/k/RET` | Latest permission, next/previous button, activate selected button |
| `p q/n/b/v` | Latest question form, next/previous field, preview option |
| `q q/d/r/s` | Queue prompt, remove queued prompt, resume queue, steer turn |
| `i f/p/!/d` | Insert file, clipboard, shell command output, text drawing |
| `b r/R/f/y/t/u/c` | Reload, restart, fork, copy ID, transcript, usage, chat labels |
| `l a/t/s/l/r` | ACP logs, traffic, save traffic, toggle logging, reset logs |
| `f f/a` | Fold current block, toggle all folds |
| `y y/r/c/l` | Copy last response, Markdown region, code block, link URL |
| `z +/-/0` | Increase/decrease/reset image size |
| `h`, `?` | Upstream transient menu, full command picker |

In normal state, `j/k`, scrolling, selection and `y` use Evil. `]]` / `[[`
and `TAB` / `S-TAB` navigate items. `za` toggles the current fold; `zm` toggles
all folds. `RET` activates a button/link/fold at point, otherwise submits the
shell prompt. In insert state, `RET` inserts a newline. `C-c RET` explicitly
submits, and `C-c S-<return>` invokes the override submission route without the
i3 `Alt+Return` conflict. The local-leader `S` works in terminals that cannot
distinguish Shift+Return.

For permissions, navigate to the desired labelled button and press `RET`.
Plain `y`, `v`, `n` and `!` retain Evil behaviour. ACP question forms likewise
use their own controls; submitting an answer is an explicit button action.

## Viewport and compose

Shared local-leader groups: `m` for mode/model/thought level, `q` for the prompt
queue, `b` for session ID/transcript, and `l` for logs/traffic. `o` returns to the
associated shell, where additional session settings are available.

In viewport view mode, `]]` / `[[` move between items and `]p` / `[p` between
interactions. `SPC m r/R` replies or quotes and replies, `j/k` changes interaction,
`g` refreshes, `x` interrupts and `h` opens the upstream viewport menu. Fold,
copy and image-size menus match the shell. Plain `q` buries the viewport.
Upstream quick replies (including numbered replies) are available through its
menu or the full command picker; normal-state numbers remain Evil counts.

Compose opens in insert state with upstream list editing and completion.
Normal-state `RET` or `SPC m s` submits; `SPC m S` uses the override route.
`SPC m v` sends and shows the response, `d` sends and dismisses, `k` cancels,
`p` peeks at the previous interaction, and `h` opens compose help. The `H` menu
provides history search (`s`), previous (`k`) and next (`j`).

## Diff review and drawings

Diffs open in normal state. `]c` / `[c` move between hunks, `RET` visits the file,
`SPC m a/r` accepts/rejects changes and `q` closes review. Copying with `y`
never accepts changes. Closing retains upstream's on-exit behaviour.

In the scratch drawing buffer, `SPC m s/k` inserts/cancels the drawing,
`h` opens drawing tools, and `p/n` browses drawing history.

## Verification

`tests/keys.el` runs with `users/josh/tests/doom-startup.el` against the built
Doom package. Tests use synthetic local buffers and do not start an ACP agent.
