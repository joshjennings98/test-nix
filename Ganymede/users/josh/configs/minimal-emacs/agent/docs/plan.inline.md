# Inline Agent Shell conversations

## Intent

Adapt the upstream gptel-inline file into a separate local Lisp file, retaining
its prompt/reference/preview workflow while using Agent Shell as the backing
conversation. Send messages without showing the conversation. Integrate with
Doom's leader keys without conflicting with i3's Alt bindings.

## Approach

`agent-shell-inline.el` retains upstream attribution, licence, reference
selection, scrolling and overlay UI. Prompts are separate text buffers rather
than indirect buffers sharing a comint shell's text. Agent Shell owns all ACP
transport, history, authentication, tools and permissions. No gptel dependency
is installed.

Preserve upstream's styled, aligned prompt header, clickable conversation,
attached vtable options panel, highlighted response action header and repeated
resize controls. Doom supplies the displayed command keys; interactive tests
verify that each displayed key resolves to that command. Panel toggling keeps
focus in the prompt, and closing a prompt cleans up its panel.

Preview navigation is explicitly entered with `SPC a e n`: j/k scroll, J/K
browse newer/older replies, C-d/C-u page, g returns to the live reply. Escape,
q or another editing command exits; no permanent scrolling/window remaps.
Use public `shell-maker-history` for previous and later existing replies,
with a separate display buffer so browsing cannot overwrite streaming output.
Browsing never changes the conversation or where subsequent prompts are sent.

Resolve the previously used conversation or a project shell, and create a
hidden shell if necessary. Private integration uses `agent-shell--new-shell`
because the pinned release's public project startup API cannot suppress display.
It also reads `agent-shell--state`'s `:chunked-group-count` during message events:
the pinned public event omits message boundaries, but this counter advances
before the event for new messages and after thinking/tool activity. Use public
insertion, initialisation, status and subscription APIs for the rest of the backend.

Wait for initialisation before submitting. Permit one inline request per shell;
a busy shell leaves the prompt draft intact. Append adds context/text to the
shell's unsent input. Clear detaches the preview; interrupt explicitly cancels
a pending or running request. Keep source references and subscriptions owned
by the preview and clean them up on source deletion. Preview errors and review
requests without stealing focus. Native permission/question controls remain
in the conversation, reachable from the preview and with a return-to-source key.

ACP sessions retain their history. The old gptel behaviour of selecting a prompt
to bypass chat history does not apply; choose a new conversation explicitly.

## Validation

Use a deterministic local ACP server to test the real Agent Shell transport:
hidden submission, streaming, follow-ups, references, appended input, startup
cancellation, busy-agent drafts, permission review, errors and cleanup. Exercise
Doom keymaps and prompt typing interactively. Build the Nix-managed editor.
No authenticated agent requests or NixOS activation are part of verification.
