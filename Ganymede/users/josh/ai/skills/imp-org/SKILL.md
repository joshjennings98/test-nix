---
name: imp-org
description: Plan changes across code, configuration and languages through the Emacs Org backing document and its MCP/Babel checks, with a mandatory stop before implementation. Use for the Emacs design workflow, including freeform Show Me plans, test expectations and Mermaid diagrams, and subsequent explicitly authorised implementation and review.
---

Use one authoritative Org document throughout the conversation. Keep decisions,
diagrams, planned changes, test expectations and results together.
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
Otherwise create `design-review.org` in the project root using `review-create`
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

Put context beside the block it explains. Create the plan or test block first,
then call `review-set-context` with `path`, `before` set to that block's ID, and
`body` containing short paragraphs or lists. Use no headings in adjacent context.
Read first and send the complete revised context for that location, including
user notes. Explain the reason for a requirement without repeating its contents.
Use Org `=inline code=` for identifiers, paths and code snippets in context prose,
not Markdown backticks. Keep source-block bodies in their own language syntax.

Omit `before` for a short document-wide Context and decisions section near the
start. Reserve it for purpose and decisions that affect the whole change; use
`**` or deeper headings there if useful. Do not collect all explanations at the
end. These contexts replace separate capture/synthesis documents from the generic
planning skills when this workflow is active.

Author planned changes through `review-set-plan` with `path`, a unique stable `id`,
and a freeform `body`. Each named `plan-review` box is one focused review assignment.
Use separate boxes for distinct parts of a feature: frontend, backend and deployment
configuration, for example. Give each enough detail to review independently, with
shared decisions and contracts in the surrounding document. Reuse IDs when refining.

There is NO prescribed specification, call-graph grammar, declaration schema or
programming language for the body. Choose the representation that helps the human
understand this part of the feature, following the Show Me examples:

- Dex: component trees with state ownership, inputs, callbacks and boundaries to
  establish a shared understanding before implementation.
- Dillon Mulroy: types, interfaces, composition, pseudocode and call trees; separate
  production and test paths when that makes dependency substitution clear.
- Tanishq: call-tree diffs showing additions and removals within unchanged context.
- File trees with responsibilities, configuration examples, sequence/state diagrams,
  or concise prose when these better communicate the change.

These are choices, not required sections. A box may mix representations. Explain
what changes, where it belongs and what must remain true. Distinguish current
behaviour, proposed additions/modifications/removals, preserved behaviour and
alternatives. Do not invent structure to satisfy a template. Do not translate
non-Go work into Go symbols or require a particular spelling of a call stack.

Example tool payload:

```json
{
  "path": "/absolute/project/design-review.org",
  "id": "preferences-frontend",
  "body": "PreferencesPanel\n  + ThemeSelector: owns the unsaved selection\n  ~ Save -> preferences client -> existing preferences endpoint\n  preserve: failed saves retain the selected value for retry"
}
```

Use a separate backend box to describe persistence and validation, referencing the
shared API contract. The reviewer receives both boxes as context but owns only its
assigned box. Keep general rationale in adjacent context via `review-set-context`.
Use `open_file` to show the relevant section; the document carries the detail.

The source body is review material, never executable application code. Org source
blocks cannot be nested inside it. Put renderable Mermaid or other source blocks
in adjacent context with unique stable names and output filenames. Rendering does
not verify behaviour. Standalone diagrams receive diagram review; plan reviewers
use adjacent diagrams as context without duplicating that review.

Legacy `design-graph` blocks are read as freeform planned changes and assessed by
an agent; their old deterministic results are historical, not current proof.
Use `review-set-plan` with the same ID and preserved body to convert each one.

Use one named `test-review` Babel block per planned test. Call `review-set-tests`
once per test with a stable block ID and a one-item `tests` array. Keep the test
behaviour and its expectations inside that block so its results appear directly
below it. Do not combine the whole test plan into one large block or move the
expectations into prose. Table-driven cases can stay together under their test.
Use short expectation lines; put any rationale immediately before the block via
`review-set-context`. Reuse `test-alignment` for the first test when it still holds
the template placeholder. Never duplicate test names across blocks.

Run `validate-document` before implementation handover: it checks
document structure and unique IDs, not semantic correctness or whether proposed
code already exists. Keep prose, diagrams and test intent consistent. Validation
PASS is not approval of the plan or evidence that implementation aligns.

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

- Each plan review interprets its assigned freeform box and checks every planned
  addition, modification, removal and preserved behaviour against actual source
  and configuration. There is no required syntax or language. Equivalent code
  may fulfil the intent without matching the notation literally. Require specific
  evidence for each assessed change; discrepancies, omitted work and insufficient
  evidence must be reported. Never revise the plan to fit the implementation.
  Return a multiline =comparison= string in the review JSON showing the differences
  between the agreed plan and observed implementation in a suitable Show Me form:
  an annotated tree, pseudocode/signature diff, configuration comparison or labelled
  planned/observed views. Retain enough matching context to locate differences.
  Distinguish planned-but-missing work, actual deviations, equivalent implementations
  and unknowns; explain the notation and connect differences to source evidence and
  findings. Compare the plan with the implementation, not the Git baseline with
  current code. If aligned, show the checked structure and state that no differences
  were found. Preserve indentation and newlines; use plain text without source
  delimiters or fences. The comparison appears below the box alongside the feedback.
  A verdict or prose summary alone is insufficient; an omitted comparison is UNKNOWN.
- Each test review assesses its named test against the block's expectations.
  Other tests in the document provide context, not duplicate review assignments.
- Implementation review owns overall behaviour, integration between the planned
  parts, edge cases and document-wide context. It does not duplicate individual
  plan-box assessments.
- Diagram review explicitly assesses every diagram: participants, order, branches,
  errors and side effects as applicable. Static call edges do not prove ordering.
- Change review surfaces work outside the plan and its effects on planned work.

Reviewers receive the whole authored Org document, including diagrams and notes,
with previous Babel output removed. Each reviewer reports only on its own remit;
other sections provide context, not additional review assignments. Missing diagram assessments or insufficient
evidence must not count as agreement. Agent findings remain advisory; report actual
test execution separately. Use inline source/Magit links to investigate and fix,
then rerun affected checks. Freshness covers saved Git-listed project files and authored requirements; ignored
files and external dependencies are outside that boundary. Never
manufacture results or treat old findings as proof about new edits.

`review-check` executes review blocks, not Mermaid rendering. Executing the whole
Org buffer renders diagrams and runs reviews together, with results in the same
backing document.

The focused reviewer prompt must contain these responsibilities explicitly. Do not
assume a subagent has loaded this skill: provide the FULL authored document,
assigned block ID and body, root, baseline and its exact remit. Require it to
inspect the relevant files and report only its assignment, including evidence and
uncertainty. An empty or incomplete assessment is not agreement. Results belong
under their originating boxes. Actual test execution remains separate from agent
judgement. The Go checker is not part of this workflow.
