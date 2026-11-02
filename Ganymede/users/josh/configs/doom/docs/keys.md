# GPTel keyboard coverage

This covers the keyboard maps in the pinned gptel, gptel-agent and gptel-inline
sources, including dynamically created editors and previews. Binding changes
live in `../keys.el`; Nix adjusts upstream Alt+Return hints and the inline
reference-repeat key. i3 is unchanged. Native Control bindings remain usable.

In normal/visual state, `SPC a` opens the AI commands. In insert state, use
Doom's alternate leader, `M-SPC a`, or leave insert state first. Do not treat
the single-letter actions in transient menus as movement keys: their letters
select the labelled actions, just as in Magit.

## Entry points and inline prompt

| Action | Evil route | Native key / behaviour |
| --- | --- | --- |
| Discuss source selection | `SPC a p` | Active visual selection becomes the reference |
| Open agent | `SPC a g` | `gptel-agent` |
| Send prompt | `SPC a s` | `C-c RET`; remaps to inline send inside its prompt |
| Cycle source reference | `SPC a c`, then `.` to repeat | `C-c SPC`; repeat changed from Space so the leader works |
| Append prompt/reference without sending | `SPC a a` | `C-c C-a`; prefix argument keeps prompt open |
| Switch conversation | `SPC a b` | `C-c C-b` |
| Visit conversation | `SPC a v` | Inline prompt: `C-c C-v` |
| Cancel prompt | `SPC a q` | `C-c C-k` |
| Toggle inline help | `SPC a h` | `C-c ?`; `?` repeats while the help map is active |
| Request options | `SPC a m` | gptel transient menu |
| System instructions | `SPC a d` | System-prompt transient |
| Presets | `SPC a @` | Apply/save preset and choose scope |
| Context list | `SPC a C` | Request menu's “Inspect context” action |

Selecting text in the inline **prompt** before sending requests a standalone
response without conversation history. This differs from selecting **source**
text before opening the prompt, which chooses the reference. Prompt editing
retains normal Evil insert/normal/visual behaviour.

## Inline response preview

The Nix-applied `../patches/gptel-inline-header.patch` makes the preview header
show `SPC a: j/k line, J/K page, o actions, v chat`. Tool approval hints likewise
show `SPC a RET` and `SPC a q`. These are leader sequences, not bare `j/k` keys
or a separate preview-navigation mode.

| Action | Route |
| --- | --- |
| Scroll one line | `SPC a j` / `SPC a k` (native `C-M-n` / `C-M-p` retained) |
| Scroll one preview page | `SPC a J` / `SPC a K` (native scroll-other-window remaps retained) |
| Open actions | `SPC a o` or `C-c C-o`; replaces conflicting Alt+Return |
| Visit actual conversation | `SPC a v`, or actions then `v` |
| Reply | Actions then `r` |
| Clear preview | Actions then `c` (native exit-recursive-edit remap retained) |
| Copy displayed response | Actions then `w` (also clears preview) |
| Resize | Actions then `+` / `-`; repeat with `+`, `=`, `-`; `0` resets |
| Dismiss actions | `q` in the action chooser |
| Return from visited conversation | `SPC a u` or `C-g`, while its return map is active |

The overlay is not selectable buffer text. Visit the conversation to use
`j/k`, `C-d/C-u`, `v/V`, text objects and `y` on the response. Plain source-buffer
movement stays unchanged. Wheel scrolling, click-to-open-actions and dragging
the preview remain available; dragging is a mouse interaction, not a new
keyboard mode. The native enlarge-window remap also still resizes the preview.

## Tool previews, approval and inspection

| Action | Evil route | Native key |
| --- | --- | --- |
| Select available tools | `SPC a t t` | Request menu `t` |
| Next/previous tool preview | `j/k` on preview or `SPC a t j/k` | `n/p` |
| Fold tool preview or Markdown code block | `SPC a f` or `TAB` at the block | `TAB` / graphical Tab |
| Toggle agent task list | `SPC a t T`, or `SPC a f` at its header | `TAB` at task-list header |
| Approve pending tools | `SPC a t a` or `SPC a RET` | `C-c C-c` |
| Reject pending tools | `SPC a t q` or `SPC a q` | `C-c C-k`; native agent preview also has `q` |
| Inspect arguments | `SPC a t i` or `SPC a i` | `C-c C-i` |
| Approve/reject edited arguments | Same approve/reject keys in inspection buffer | `C-c C-c` / `C-c C-k` |
| Leave inspection | `SPC a i` | `C-c C-i` |

Confirm/reject/inspect resolve the **current** gptel keymap. Inline approvals,
ordinary tool previews and the inspection editor use distinct upstream handlers.
These keys refuse an unrelated mode's Control command. Navigation/folding does
not approve execution. Original mouse dispatch remains available.

## Context list

`j/k` navigate entries, `RET` visits, `d` flags removal and `q` quits.
`SPC a RET` confirms the changes; `SPC a q` cancels. Native `n/p`, `C-c C-c`
and `C-c C-k` remain available. The list starts in Evil normal state.

## Rewrites

Select text and use `SPC a r` to start a rewrite, or use it to reopen rewrite
options. The per-rewrite commands below operate at point; the transient menu
also has explicit actions for **all** pending rewrites.

| Action at point | Evil route | Native key |
| --- | --- | --- |
| Actions | `SPC a R o` | `RET` / mouse click |
| Accept | `SPC a R a` | `C-c C-a` |
| Iterate | `SPC a R r` | `C-c C-r` |
| Reject | `SPC a R q` | `C-c C-k` |
| Diff | `SPC a R d` | `C-c C-d` |
| Ediff | `SPC a R e` | `C-c C-e` |
| Merge | `SPC a R m` | `C-c C-m` |
| Next/previous | `SPC a R j/k` | `C-c C-n` / `C-c C-p` |

## Instruction and query editors

In the full instruction editor, `SPC a RET` saves and `SPC a q` cancels
(`C-c C-c` / `C-c C-k`). These invoke the editor's own buffer-local closures.

In the dry-run query inspection buffer, `SPC a RET` **sends the inspected
request**, `SPC a y` copies its curl command, and `SPC a q` closes it.
Native keys are `C-c C-c`, `C-c C-w`, `C-c C-k`. Read-only mode can be toggled
using the normal Emacs command; ordinary movement/copying remains available.

## Transients and minibuffers: keep their displayed action keys

These interfaces already use direct action keys rather than Control chords.
Overriding `j/k` globally here would take away menu actions and dynamically
assigned tool shortcuts. All of the following remain accessible:

- Request menu: system message (`s`), directive (`d`), presets (`@`), scope (`=`),
  provider/model (`-m`), context inclusion (`-i`), reasoning (`-v`), tool use
  (`-t`), and conditional expert settings for tokens, messages, temperature,
  response tracking and media. Context actions include kill-ring (`C-y`),
  region (`-r`), buffer (`-b`), file (`-f`), removal (`-d`) and inspection.
- Prompt source: minibuffer (`m`), kill-ring (`y`), respond in place (`i`).
  Output destination: echo area (`e`), another buffer (`b`), chat (`g`),
  kill-ring (`k`). `RET` sends with the selected settings.
- Response actions: mark (`SPC`), regenerate (**`C-c RET`**, replacing `M-RET`),
  previous/next variant (`P/N`), and Ediff (`E`) when available. Existing
  conditional Lisp/JSON dry-run inspection (`I/J`) and log controls remain.
- Tool menu: generated category/tool keys toggle selections; `RET` confirms,
  `q` cancels. Scope, enablement, confirmation and result-inclusion options
  keep their displayed keys. Optional MCP `M+`/`M-` are literal two-key
  sequences, not Alt combinations; the sandbox policy is unchanged.
- System-prompt menu: displayed generated directive keys, `s` to edit and
  `=` for scope. Preset completion uses `C-s` to save and `=` for scope.
- Rewrite menu: presets (`@`), directive (`s/d`), context, diff options,
  rewrite (`r`), diff/Ediff (`D/E`), merge/accept/reject all (`M/A/K`), and
  conditional dry-run inspection (`I/J`).
- Prompt/rewrite minibuffers: `C-c C-e` opens the full editor; **`C-c RET`**
  replaces Alt+Return for include/ignore selection or opening rewrite options.
  Rewrite/directive `TAB` cycling remains. Normal minibuffer submission and
  `C-g` cancellation remain. These are text-entry controls, not Evil list maps.
- Standard transient help, quit and prefix handling are inherited from
  Transient/Doom; menu descriptions show whichever conditional actions exist.

## Verification and scope

The interactive checks in `../tests/keys.el` run against the actual Doom
package, using a fresh HOME and synthetic buffers. They cover visual selections,
preview scrolling, conversation copying, tool navigation, context-sensitive
actions, inline reference cycling/append, rewrite accept/reject, and source-map
coverage for inline prompts and rewrite actions. No model requests are allowed.

This does not replace unrelated Org/Markdown, Evil, completion, Ediff or
Transient framework bindings. Mouse gestures are retained, not translated into
a separate keyboard UI. Conditional menu entries retain their upstream
behaviour; binding coverage is not a claim to have exercised every provider or
network workflow.
