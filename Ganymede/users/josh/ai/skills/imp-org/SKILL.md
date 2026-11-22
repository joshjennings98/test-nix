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

When continuing from [plan-org](../plan-org/SKILL.md), reuse its live backing
document and settled feature breakdown. Do not restart feature discovery, create
a second document or require a separate synthesis step. Read the user's latest
answers and open deferrals before planning the implementation. Reopen a feature
decision only when a concrete conflict or missing requirement needs resolution.

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

Read applicable `AGENTS.md` files, including nested guidance for affected areas.
Extract architectural constraints and design preferences, not just coding rules:
responsibility boundaries, dependency direction, ownership, extension points and
compatibility expectations. Apply these when shaping the plan; this is not a
code-style audit.

Inspect the existing architecture, nearby implementations and their tests before
proposing structure. Prefer established patterns and existing abstractions when
they fit the required behaviour. Identify the concrete types, interfaces or
modules to reuse and explain their roles in the relevant feature block. Do not
invent a parallel abstraction or force reuse of one with the wrong responsibility.
If a departure is needed, explain the mismatch and trade-off and resolve the design
choice explicitly. Put any resulting requirement inside the affected block so its
focused reviewer can check it without the rest of the document.

Use one named `plan-review` block per coherent, independently reviewable change.
A large feature may need separate blocks for distinct responsibilities. Each block
is the complete approved specification for its focused reviewer. Include the
relevant interface contracts, failure behaviour and preserved behaviour in it;
do not rely on requirements elsewhere in the document. The implementor reads the
whole document, while the overall reviewer checks integration between blocks.

Place a short human summary immediately above each block through
`review-set-context` with `before` set to its ID. This summary explains the change;
it must not introduce requirements absent from the block. Read existing context
first and preserve user notes. Use Org =inline code= in prose. Document-wide
Context and decisions retains the feature breakdown from `plan-org`.

Write blocks with `review-set-plan` using `path`, a stable `id` and `body`.
Make the specification visually scannable: short labelled sections, blank lines,
indented trees and brief inline annotations. Choose only the views that explain
this change: a call/component tree, interfaces, a file layout or pseudocode.
Do not turn the block into an essay or repeat views without a review benefit.
These are human-readable specifications, not executable code or a fixed grammar.

Presentation conventions inside a block:
- `@@ Label` starts a visually distinct section. Use meaningful labels, not a fixed template.
- A leading `+` colours an addition green; a leading `-` colours a removal red.
  Keep unchanged lines around changes to show where they fit. Indentation is allowed before the marker.
- `//` or `#` after whitespace introduces a muted annotation. Keep annotations short.
- `==important phrase==` adds a highlighter background. Use sparingly for a key constraint.
- Separate logical chunks with a blank line. Keep requirements concise and explicit.
  A muted comment is still part of the approved specification.

### Architecture context and review

Include a short architecture paragraph and one self-contained architecture review
assignment in every implementation plan. Keep this proportional to the change;
it is not a separate architecture study or a catalogue of possible patterns.

Inspect the project's existing structure and applicable guidance first. When a
pattern decision matters, consult any available project architecture catalogue
and a reliable pattern reference. In one short paragraph, explain the approach,
why it fits, which existing abstractions it uses and any material trade-off.
Include a direct Org link to further reading about the relevant pattern, plus
local source links where useful. Read the linked material before citing it; do
not invent a reference or use a pattern name as a substitute for an explanation.
Treat references as background, not as additional requirements for the reviewer.

Create this assignment with `review-set-plan`, normally using the stable ID
`architecture-alignment`. Then place the paragraph immediately above it using
`review-set-context` with `before` set to that ID. This is an ordinary `plan-review`
block, not a new Babel language. Its results and comparison appear below it, and
it runs alongside other non-test reviews and must pass before test reviews start.

Inside the block, state the architectural requirements to check against actual
source: relevant dependency directions, responsibility boundaries, state ownership,
construction/lifecycle rules and reuse of existing abstractions. Name concrete
modules or interfaces and distinguish changes from preserved structure. Include
all needed context because this reviewer receives only its assigned block.
Request source evidence and a planned-versus-observed structural comparison.
Keep feature behaviour in the feature blocks and integrated behaviour in the
overall implementation review; this assignment owns architectural conformance.

For a simple change, explicitly write **No architecture changes planned** in the
context paragraph and identify the existing structure being retained. Do not
force a pattern label or reading link when no pattern explanation is needed.
The block must still specify what to preserve, rather than merely saying
"check no architecture changes". For example:

```text
@@ Architecture — preserve existing boundaries
api.Handler -> service.Service -> storage.Store
Handler owns HTTP status mapping and the early rate-limit response.
Service owns the capacity decision; Store owns insertion and Count mutation.

@@ Review expectations
==No architecture changes planned==
Check the handler does not bypass Service to write to Store.
Check existing dependency ownership and construction remain unchanged.
Check no new layer, storage path or external dependency was introduced.
Provide source evidence and compare the observed structure with this plan.
```

### Choose the view for the planning decision

Adapted from the representation choices in
[HumanLayer's show-me skill](https://raw.githubusercontent.com/humanlayer/skills/refs/heads/main/plugins/show-me/skills/show-me/SKILL.md).
Choose the smallest useful view. Avoid redundant views. For complex behaviour,
overlapping views are appropriate when they materially help review—for example,
a call tree showing responsibilities and a sequence diagram making ordering
easier to check. Do not add another view unless it adds clarity, and do not fill
a checklist of representations.

| Planning question | View | Include |
| --- | --- | --- |
| What calls what? | Indented call tree | Entry point, relevant calls, ownership boundaries and failure paths |
| Who owns UI state? | Component tree | State owner, inputs, callbacks and module boundaries |
| Where will the change live? | Shallow file tree | Project-relative paths and one responsibility per entry |
| What crosses a boundary? | Types and signatures | Inputs, outputs, errors and constraints; no implementation bodies |
| What decisions does the algorithm make? | Pseudocode | Branches, ordering, cancellation and side effects that matter |
| How do participants interact over time? | Sequence/state view | Participants, transitions, errors and ordering |

For existing code, show proposed additions/removals within unchanged structure.
For a mostly new component, show the intended complete shape and label it proposed.
Inspect existing code before marking anything preserved. These sketches describe
agreed future behaviour, not a claim that implementation already exists.

Examples of different views within feature specifications (choose, do not copy all):

```text
@@ Proposed call path
submitJob
  validateRequest
+ reserveSlot                 // reject before creating work if capacity is exhausted
  JobStore.insert
  Worker.start
    onFailure -> releaseSlot

@@ Proposed component ownership
<PreferencesPage>             // owns draft and save error
  <ThemeSelector value=draft onChange=setDraft>
+ <SaveButton onClick=save disabled=saving>
  onSaveFailure -> retainDraft

@@ Proposed files
src/jobs/
  handler.go                 # validates and starts jobs
+ capacity.go                # owns slot reservations and release

@@ Proposed algorithm
on worker completion or failure
  if reservation already released
    return                   // release is idempotent
  release reservation
```

Keep a short explanation beside the relevant visual, not a long preamble.
Put required ordering or interface details inside the assigned feature block.
Renderable Mermaid stays in adjacent Org context because source blocks cannot
nest; its separate diagram review checks it. Any requirement needed by a focused
feature reviewer must also be explicit in that feature's specification.
Do not create HTML or a second plan artefact for this workflow.

For example, one feature block might contain:

```text
@@ Save path
savePreferences
  validateSelection
- writeLocalFile
+ preferencesClient.save(selection)  // existing API contract below
  onFailure -> retainDraft           // allow retry

@@ Interface
save(selection: Theme) -> SavedPreferences | SaveError
Theme = light | dark | system

@@ Behaviour
==Only clear the draft after a successful save==
Failure preserves the selected theme and displays the returned error.
```

Use `open_file` to show the relevant section. Review results stay below their
originating block. The same readable notation should be used in the reviewer's
planned-versus-observed comparison.

The source body is review material, never executable application code. Org source
blocks cannot be nested inside it. Put renderable Mermaid or other source blocks
in adjacent context with unique stable names and output filenames. Rendering does
not verify behaviour. Standalone diagrams receive diagram review; feature reviewers use only the
requirements captured inside their assigned block.

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
Read `review-results` for asynchronous progress and feedback. Non-test reviews
run concurrently in separate Codex review conversations, one per block. The
Emacs review launcher registers the Org reviewers for those conversations.
Each review conversation uses the named subagent for its block when available.
Plan, implementation and diagram reviews use =org-implementation-alignment=.
Change reviews use =org-implementation-misalignment= and test reviews use
=org-test-reviewer=. The review conversation passes the supplied assignment and
returns the assessment in the format Emacs expects.
Feature reviewers receive only their assigned specification, root and baseline;
implementation, diagram and change reviewers receive the full authored document.
Test reviews start only after every non-test assessment passes for the same
source and requirements snapshot. Missing evidence, failures and unresolved
findings block that stage. Let running reviews finish before resubmitting.
Keep using the Emacs review tools so results return to the document.

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
  parts, edge cases and document-wide context. Its Org block also reviews the
  changed code and affected callers for defects and regressions using available
  code-review skills.
- Diagram review explicitly assesses every diagram: participants, order, branches,
  errors and side effects as applicable. Static call edges do not prove ordering.
- Change review surfaces work outside the plan and its effects on planned work.

Focused feature reviewers inspect actual code and dependencies against their
approved block only. They must not read the backing document or import requirements
from other blocks. An incomplete contract is UNKNOWN, not permission to infer one.
Overall reviewers receive the full authored document with previous results removed.
Agent findings remain advisory; report actual test execution separately. Use source
and Magit links to investigate and rerun affected checks after fixes. Freshness
covers saved Git-listed project files and authored requirements; ignored files and
external dependencies are outside that boundary.

`review-check` executes review blocks, not Mermaid rendering. Executing the whole
Org buffer renders diagrams and runs reviews together, with results in the same
backing document.

The focused reviewer prompt must include its assigned block ID and complete body,
root, baseline and exact remit. Any subagent receives the same bounded assignment.
Require source evidence and explicit uncertainty. A complete review with no
findings can return PASS with an empty findings list. It still needs a summary of
what was checked and any required plan comparison or diagram assessments.
Results belong under their originating blocks. Actual test execution remains
separate from agent judgement. The Go checker is not part of this workflow.
