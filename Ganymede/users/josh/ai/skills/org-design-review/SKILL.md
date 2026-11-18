---
name: org-design-review
description: Plan Go changes through the Emacs Org backing document and its MCP/Babel checks, with a mandatory stop before implementation. Use for the Emacs design workflow, including call graphs, test expectations and Mermaid diagrams, and subsequent explicitly authorised implementation and review.
---

Use one authoritative Org document throughout the conversation. Keep decisions,
diagrams, planned code relationships, test expectations and results together.
Do not create a separate Show Me artefact or Markdown plan for this workflow.
A standalone PR explanation is a different task.

## Mandatory stop before implementation

When this skill is invoked, you MUST stop before implementation. Inspect the
project, discuss the design, write the Org plan and validate the document. Then
present the plan for review and end the turn. Do not edit implementation source,
write implementation tests or delegate implementation during this planning phase.

This stop applies even if the invoking request also asks you to build or implement
the feature. Do not treat earlier permission, agreement on design details or a
successful validation as permission to cross this boundary. Implementation may
begin only after the user explicitly authorises it in a subsequent message,
after the plan has been presented. Further planning requests do not grant that
authorisation.

Follow the plain-language principles of ASD-STE100 Simplified Technical English,
without claiming strict compliance. Use short sentences, active voice, consistent
terms, specific nouns, and concrete examples. Prefer familiar words, but keep
precise technical terms. Explain cause and effect without padding, praise,
repetition, or invented drama. Simple writing must not mean shallow analysis.

All agent-authored changes to the backing document must use the Emacs review MCP
tools. Do not write or patch its file directly, use shell redirection, or bypass
the tools through raw buffer edits. This restriction concerns the backing document,
not implementation source files or the user's own manual edits. Examples below
are tool payloads, not instructions to edit a file.

## Start or resume

Discover the connected Emacs tools (their server prefix can vary). Use
`list_buffers` and project files to find an existing review. Prefer the document
the user names or has open. Read it with `review-read`: the live buffer can contain
unsaved changes absent from disk. If several documents plausibly apply, ask which.
Otherwise create `design-review.org` in the Go project root using `review-create`
with absolute `path`, `root` and `title`. It pins Git HEAD; preserve that baseline.
Use `baseline: "none"` only when explicitly choosing no historical comparison.

If review tools are unavailable, explain that the Agent Shell conversation needs
the emacs-navigation connection. Do not silently substitute a different plan
format or claim validation ran. Read-only investigation can continue.
Do not fall back to direct document edits when a tool is missing or rejects input.

## Develop the plan in the document

Inspect existing source and tests. Discuss behaviour, responsibilities and
meaningful design choices; retain decisions already made. Ask only questions
needed to resolve uncertainty. Invoking planning does not authorise implementation.

Put context beside the block it explains. Create the graph or test block first,
then call `review-set-context` with `path`, `before` set to that block's ID, and
`body` containing short paragraphs or lists. Use no headings in adjacent context.
Read first and send the complete revised context for that location, including
user notes. Explain the reason for a requirement without repeating its contents.

Omit `before` for a short document-wide Context and decisions section near the
start. Reserve it for purpose and decisions that affect the whole change; use
`**` or deeper headings there if useful. Do not collect all explanations at the
end. These contexts replace separate capture/synthesis documents from the generic
planning skills when this workflow is active.

Reserve free-text additions for context: rationale, explanations, assumptions and
open questions belong beside the relevant block. Encode checkable call relationships and
declarations with `review-set-graph`, and test behaviours and expectations with
`review-set-tests`; prose must not replace those structured requirements. Mermaid
source goes through `review-set-context`. Diagrams are optional. Do not invent a
diagram to fill a template. The tools add a diagram review only when diagrams
exist. A `design-graph` block checks code relationships; it is not a rendered diagram.

Choose small readable views: call trees for relationships, signatures for
interfaces, pseudocode for algorithms, Mermaid for sequence/state interactions.
Add these through the appropriate MCP tool. Use `open_file` to show the relevant
section. Keep conversation concise; the document carries the detail. Distinguish
agreed intent from existing behaviour and alternatives under discussion.

Example context beside an existing `save-request` graph block. On later edits,
read and preserve the context already stored at that location:

```json
{
  "path": "/absolute/project/design-review.org",
  "before": "save-request",
  "body": "Validate the request before saving it. Invalid requests must not change stored data.\n"
}
```

Use unique, stable diagram names and output filenames next to the document. Org
renders these with Babel (`C-c C-c`) and displays images inline. Successful
rendering does not verify behaviour. Avoid duplicating a graph in Mermaid unless
the second view answers a different question.

Author executable requirements through `review-set-graph` using its live schema.
Use canonical symbols from inspection, explicit relations on children and
declarations for proposed symbols. Unmarked nodes are baseline context;
`add`, `remove` and `preserve` mark requirements. Declaration signatures describe
Go shapes without bodies. Reuse IDs; submit related declarations together when
references depend on them. Rejected mutations leave the document unchanged:
correct the request instead of bypassing validation with direct edits.

Use one named `test-review` Babel block per planned test. Call `review-set-tests`
once per test with a stable block ID and a one-item `tests` array. Keep the test
behaviour and its expectations inside that block so its results appear directly
below it. Do not combine the whole test plan into one large block or move the
expectations into prose. Table-driven cases can stay together under their test.
Use short expectation lines; put any rationale immediately before the block via
`review-set-context`. Reuse `test-alignment` for the first test when it still holds
the template placeholder. Never duplicate test names across blocks.

Run `validate-document` before implementation handover: it checks
document/proposal validity, not whether proposed code already exists. Keep prose,
diagrams and test intent consistent with graph requirements.

## Implement and verify

Only after the mandatory stop and subsequent explicit authorisation, implement
from this document. Surface genuine design changes
and update agreed intent explicitly. Do not revise requirements just to pass.

Run relevant tests and `review-check` (omit `id` for all review blocks).
Read `review-results` for asynchronous progress and feedback. Let queued reviews
finish before interpreting them or resubmitting a block. Reviews share one
dedicated Codex/Astra conversation, separate from the implementation conversation.
Recommend one fresh subagent per focused review when supported, each given the
FULL authored plan and its assigned remit. The review conversation collects their
findings for the corresponding Org results. Without subagents, perform the focused
reviews sequentially there. Keep using the Emacs review tools so results return to
the document; do not replace them with unrecorded reviews in the author conversation.

- Graph blocks check explicit structural requirements deterministically.
- Each test review assesses its named test against the block's expectations.
  Other tests in the document provide context, not duplicate review assignments.
- Implementation review assesses whether planned code matches its responsibilities.
- Diagram review explicitly assesses every diagram: participants, order, branches,
  errors and side effects as applicable. Static call edges do not prove ordering.
- Change review surfaces work outside the plan and its effects on planned work.

Reviewers receive the whole authored Org document, including diagrams and notes,
with previous Babel output removed. Each reviewer reports only on its own remit;
other sections provide context, not additional review assignments. Missing diagram assessments or insufficient
evidence must not count as agreement. Agent findings remain advisory; report actual
test execution separately. Use inline source/Magit links to investigate and fix,
then rerun affected checks. There is no automatic freshness tracking. Never
manufacture results or treat old findings as proof about new edits.

`review-check` executes review blocks, not Mermaid rendering. Executing the whole
Org buffer renders diagrams and runs reviews together, with results in the same
backing document.
