---
name: plan-what
description: "Use before any feature work, behaviour change, or non-trivial addition. Explores intent, requirements, and design through collaborative dialogue before implementation begins."
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Read relevant files, docs, and recent commits. Understand the current state.

You will notice things during this phase — potential approaches, patterns, problems. That's fine. But recognise that these observations are formed without the user's input. They are starting points for questions, not conclusions.

If you notice something useful from the exploration during the discussion with the user (for example an existing retry pattern or helper that could be reused based on a discussion about retries), make a note of it for use by an implementor later. Whether the insight is useful will be decided in a later phase. These insights should not be surfaced to the user unless they change the product discussion itself — for example, if the requested functionality already exists in another form, conflicts with current behaviour, or exposes a constraint the user must account for.

**Ask about the problem, not about solutions.** Questions should explore purpose, constraints, success criteria, past experience, and edge cases. They should not present options or steer toward an approach.

Good questions:
- "What's the actual pain point this solves?"
- "How do you expect to interact with this day to day?"
- "Is there anything you've tried before that didn't work?"
- "What would make this not worth doing?"
- "What should happen if this fails?"
- "Should the user be able to retry?"
- "What should the user see when this cannot be completed?"

Bad questions (solution-space questions — these belong in implementation plan, not here):
- "Should we use approach A or approach B?"
- "Would you prefer polling or webhooks?"
- "I see three options — which appeals to you?"
- "Should we reuse the existing retry helper?"
- "Should retries live in the API client or the job runner?"
- "Should we refactor the current flow into a shared abstraction?"

**One question per message.** Do not overwhelm with multiple questions at once.

Focus only on the high-level design and the features this will need:
- What capability is being added
- Who uses it, and when
- What the expected user experience is
- What success and failure look like
- What edge cases matter
- What constraints or non-goals should shape the design
- What behaviour should be configurable, visible, automatic, or manual

A good rule of thumb: ask about the behaviour the user wants, not the mechanism that will produce it. If the user could answer without knowing the codebase, it probably belongs here. If the question depends on libraries, architecture, existing abstractions, or refactoring strategy, save it for implementation planning.

## Q&A capture

During the discussion, keep a concise capture of the questions and answers that establish feature understanding. Keep this in a document at the project root called `plan.feature.md`.

Record:
- The question asked
- The user's answer
- Any settled feature decision
- Any relevant note that changes how the feature should be understood

Do not record ordinary follow-up questions, temporary uncertainty, or items that are simply waiting for later discussion. The conversation can carry that state until it is resolved.

