---
name: plan-org
description: "Explore feature intent, requirements and behaviour through collaborative dialogue, capturing the evolving breakdown in a live Org backing document before implementation planning."
---

Interview me relentlessly about every aspect of this feature until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions. For each question, provide your recommended answer.

Read relevant files, docs, and recent commits. Understand the current state. Find facts yourself rather than asking the user for information you can look up.

Read applicable `AGENTS.md` files and relevant codebase context to determine what not to ask: avoid questions already answered by explicit project guidance or facts you can establish yourself. This is preparation for feature discovery, not a source of feature requirements or an invitation to discuss architecture. Do not infer desired behaviour from the current implementation, treat existing limitations as agreed scope, or ask the user to choose patterns or abstractions. Keep discovery focused on the user's purpose and desired behaviour. Raise a project constraint only when it creates a concrete conflict or ambiguity that affects those answers; otherwise retain technical observations for implementation planning.

You will notice things during this phase — potential approaches, patterns, problems. That's fine. But recognise that these observations are formed without the user's input. They are starting points for questions, not conclusions.

If you notice something useful from the exploration during the discussion with the user (for example an existing retry pattern or helper that could be reused based on a discussion about retries), make a note of it for use by an implementor later. Whether the insight is useful will be decided in a later phase. These insights should not be surfaced to the user unless they change the product discussion itself — for example, if the requested functionality already exists in another form, conflicts with current behaviour, or exposes a constraint the user must account for.

**Ask about the problem, not about solutions.** Questions should explore purpose, constraints, success criteria, past experience, and edge cases. They should not present implementation options or steer toward a technical approach. Recommendations concern desired feature behaviour only.

Good questions:
- "What's the actual pain point this solves?"
- "How do you expect to interact with this day to day?"
- "Is there anything you've tried before that didn't work?"
- "What would make this not worth doing?"
- "What should happen if this fails?"
- "Should the user be able to retry?"
- "What should the user see when this cannot be completed?"

Bad questions (solution-space questions — these belong in implementation planning, not here):
- "Should we use approach A or approach B?"
- "Would you prefer polling or webhooks?"
- "I see three options — which appeals to you?"
- "Should we reuse the existing retry helper?"
- "Should retries live in the API client or the job runner?"
- "Should we refactor the current flow into a shared abstraction?"

**Ask in rounds, not one question at a time.** Each round contains all questions whose prerequisite decisions are already settled. Number each question and give your recommended answer with a brief reason; where applicable, word it so “yes” accepts that recommendation. Questions that depend on another unanswered question belong to a later round. Wait for the user's answers, update the breakdown, then work out the next round. Accept partial answers and corrections; unanswered questions remain open, not implicitly agreed. Investigate missing facts yourself and defer only the questions that depend on them.

Focus only on the high-level design and the features this will need:
- What capability is being added
- Who uses it, and when
- What the expected user experience is
- What success and failure look like
- What edge cases matter
- What constraints or non-goals should shape the design
- What behaviour should be configurable, visible, automatic, or manual

A good rule of thumb: ask about the behaviour the user wants, not the mechanism that will produce it. If the user could answer without knowing the codebase, it probably belongs here. If the question depends on libraries, architecture, existing abstractions, or refactoring strategy, save it for implementation planning.

## Org backing document

Before the first question round, capture the user's initial idea in the backing document. Discover the Emacs review MCP tools and use `list_buffers` and project context to find an existing document. Read it with `review-read`, including unsaved edits. Otherwise use `review-create` with an absolute `path` to `design-review.org` in the project `root` and a short `title`. Preserve its pinned baseline. Ask only if the project or document is ambiguous.

Use `review-set-context` with `path` and `body` to maintain the feature breakdown in Context and decisions; `**` headings can separate features and decisions. Read first and preserve user notes: the tool replaces the whole context section. All document edits must use these MCP tools. If they are unavailable, explain that the conversation needs the emacs-navigation connection; do not silently substitute a file or claim the document was updated.

Ask questions in the conversation so the user can answer through the inline agent or normal Agent Shell UI. After each answer, update the document before asking the next round. Capture settled feature decisions, relevant answers and rationale, and open decisions needed for subsequent rounds. Mark assumptions as unconfirmed and revise affected requirements when an answer changes them. Keep a coherent breakdown, not a transcript or a separate Q&A file awaiting synthesis. Use Org =inline code= in prose.

Do not produce implementation planning here or fill the template's review placeholders with invented technical requirements. Keep useful code observations as uncommitted notes for the later implementor.

When the in-scope feature decisions are settled or explicitly deferred, run `validate-document` and poll `review-results` if needed. This checks document structure, not feature correctness. Summarise the agreed feature and any deferrals, link the document, and ask whether it captures the user's intent and whether they want to move on to `imp-org` for implementation planning. Stop and wait. If they agree, continue with `imp-org` in the same document; this does not authorise coding.
