# Agent Shell in Doom

`SPC f` opens the project file picker. The file command menu is under `SPC F`,
so `SPC F f` opens the directory-based file finder.
`SPC b` opens the buffer picker previously on `SPC b b`; the buffer menu is
under `SPC B`.
`SPC SPC` is unbound. Which-key menus appear after 0.01 seconds for both
leader and local-leader prefixes.

`SPC r` reviews all due Org FC flashcards. `SPC R` chooses an Org file under
`~/Documents/org/` for editing or creation. Both work outside Org buffers.
An agent completion alert stays visible while you review; click it to return
to that agent, or leave the review with `q` and use `SPC a P`.

`SPC a` works from source buffers. `SPC m` is the local leader inside agent
buffers. In insert state use `M-SPC a` and `M-SPC m`. Which-key labels all menus.
`SPC a ?` (or `SPC m ?`) searches every public interactive Agent Shell command,
including provider launchers and less common commands without dedicated keys.
Commands retain upstream requirements: session features depend on the agent's
advertised capabilities, and buffer-specific commands need the appropriate view.

## Terminal

`SPC T n` opens a new Ghostel terminal in the current window; `SPC T s` opens
one in a new split below. `SPC t` remains the toggles prefix. Ghostel uses Doom's
terminal integration and a native module built by Nix, with bright bold colours.

## Org flashcards

In Org buffers, `SPC m F` opens Org FC's Transient menu:

| Key | Action |
| --- | --- |
| `i n` | Turn the current heading into a normal question/answer card |
| `i c` | Turn the current heading into a cloze deletion card |
| `i d`, `i t` | Create a double-sided or text-input card |
| `u` | Update the current card after editing |
| `r` | Review cards; choose the current buffer or all configured directories |
| `d` | Dashboard |

Cards are discovered under `~/Documents/org/`. Save the Org file before
starting a review. During review, `RET` reveals the answer, then `a/h/g/e`
rates it again/hard/good/easy; `q` quits. Review history is stored in Doom's
persisted state directory. Scheduling data lives in the Org files themselves.

## From source buffers: SPC a

| Key | Action |
| --- | --- |
| `a`, `t`, `b` | Open, toggle, switch shell |
| `N n/r/w` | New shell, resume session, new worktree shell |
| `r` | Reply to an inline preview |
| `S`, `f` | Send selection, current file |
| `i f/i/s/d` | Another file, clipboard image, screenshot, selection or diagnostic |
| `p`, `m` | Inline source discussion, quick background message |
| `P` | Centre an existing inline preview; cycle through open previews |
| `j/k`, `D/U` | Scroll inline response by line or page |
| `n`, `o` | Enter preview navigation, response actions |
| `v`, `x` | Visit/review conversation, interrupt |
| `?` | All Agent Shell commands |

The [inline workflow guide](inline.md) covers reference selection, prompt
bindings and response previews. In its prompt window, `SPC m` controls the
inline composer rather than the full conversation.
For repeated preview navigation, press `SPC a n` once, then use `j/k` to
scroll, `J/K` for newer/older replies, `C-d/C-u` for pages, and `g` for the live
reply. `Esc`, `q`, or an ordinary editing command leaves navigation.
Use `SPC a o` for copy (`y`), clear (`c`) and resize (`+`/`-`).
The options inside the preview are clickable too. Resizing keeps them open;
`q` or `Esc` closes them, and `0` resets the height.
Shell compose and last-interaction commands remain available through `SPC a ?`
and the shell's local-leader controls.

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
