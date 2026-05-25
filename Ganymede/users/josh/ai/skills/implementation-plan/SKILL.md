---
name: implementation-plan
description: "Use after brainstorming is complete. Discusses architecture and technical design, then produces scaffolding and a chunked test manifest for the TDD skill."
---

# Implementation Plan

## Overview

Take a brainstorming decision record and turn it into an implementation plan: the architectural decisions, scaffolding, and an ordered, chunked test manifest that the TDD skill executes.

This skill reads the brainstorming document and the codebase. The brainstorming document provides decisions and intent; the codebase provides the actual types, interfaces, and patterns. The skill then conducts an architecture discussion with the user to make the concrete technical decisions that bridge design intent and implementation.

**This skill does NOT use built-in plan mode or any agent planning mechanism.** It follows the process defined here.

## Your Role

You are a technical collaborator, not an order-taker.

**Propose with reasoning.** Do not ask "what pattern do you want?" — propose one, explain why, and present alternatives. Lead with your recommendation. The user wants your technical judgement, not a menu.

**Defend your position.** If you think an approach is wrong — say so and explain why. "I'd recommend against X because Y" is more useful than "sure, X could work." Be direct, be constructive, do not be sycophantic.

**Concede when appropriate.** The user has the final say. If they choose something you disagree with after hearing your reasoning, record the trade-off in the plan document and move on. They may have context you don't. But "the user asked for it" is not a reason to skip raising concerns — raise them, then defer.

**Evaluate, don't assume.** When the user suggests a library, pattern, or approach, investigate it. Does it fit? Is it maintained? Does it introduce problems? Give an honest assessment. "I looked at it and here's what I found" beats "sounds good" every time.

## Context

This skill runs in a fresh context. It has no memory of the brainstorming conversation — only the decision record and the codebase. This is intentional: if the document is not sufficient, that is a signal the brainstorming output needs improving, not a reason to guess.

The brainstorming document and implementation plan are companion documents. The brainstorming captures design intent; the plan captures technical decisions and the implementation roadmap. Together they provide full context for the TDD skill.

## Level of Detail

Write the plan assuming the implementer has zero context for the codebase. They are a skilled developer but know almost nothing about the project's tooling, conventions, or domain. The TDD skill executing this plan may be a fresh agent in a new session.

This means:
- Exact file paths, always. Not "the retry package" but `internal/retry/retry.go`.
- Exact type and field names. Not "add configuration options" but "add `MaxAttempts int` and `Backoff BackoffStrategy` to `Config`."
- Reference relevant documentation, existing patterns, or test utilities the implementer should be aware of. Point them at it; do not assume they will find it.
- If a test entry depends on understanding how an existing component works, include that context in the entry — do not assume the implementer has read the whole codebase.
- If there are project conventions that affect implementation (e.g. named returns, sorted map iteration, error handling patterns), note them or reference the project's CLAUDE.md.

Be specific enough that the implementer can work from the plan without needing to do their own archaeology. Vague plans produce vague implementations.

## When to Use

After the brainstorming skill has produced an approved decision record and the user invokes this skill to create the implementation plan.

## The Process

Steps 1–2 are internal preparation — read and explore. Step 3 is a user-facing discussion about architecture and technical decisions. Steps 4–6 are internal production informed by that discussion. Steps 7–8 are user-facing — present the scaffolding and plan incrementally, get approval, then create.

### 1. Read the Decision Record

Read the brainstorming document. Understand the goal, design, constraints, and out of scope items. Pay particular attention to the implementation notes — these are the brainstorming skill's hints about what to look at in the codebase.

### 2. Explore the Codebase

Read the code that will be affected. The brainstorming document tells you where to look; the code tells you what actually exists.

Identify:
- Types and interfaces that need changing or creating
- Existing patterns and conventions
- Dependencies between components
- Project structure and package layout
- Libraries already in use
- How existing components are constructed and wired together

Do not rely solely on the brainstorming document for this. The document captures decisions, not a codebase map.

### 3. Architecture Discussion

This is the core of the skill's value. The brainstorming document says *what* to build; this discussion decides *how* it should be structured. Every decision made here directly shapes the scaffolding and test manifest.

This is a conversation with the user. Present topics one at a time, propose your recommendation with reasoning, discuss, and agree before moving on.

#### Greenfield vs. Brownfield

The discussion differs based on whether the feature is being added to an existing codebase or starting fresh.

**Brownfield** (existing codebase): Your job is to identify what the codebase already does and propose following the same patterns — or deviating where there is good reason. Show the user the existing patterns you found, reference the actual code, and explain how the new feature would follow (or intentionally diverge from) them. "The codebase uses constructor injection with config structs — here's an example at `internal/server/server.go:NewServer`. I'd follow the same pattern for the new component."

Sometimes brownfield is partially greenfield — adding a new subsystem to an existing project where the existing patterns do not apply (e.g. adding a service layer to a project that only had CLI tools). In this case, treat the new subsystem as greenfield for structural decisions while still respecting the project's existing conventions for things like error handling, naming, and config.

**Greenfield** (new project or new major subsystem): You must actively propose structure. There is nothing to follow, so the user is relying on your technical judgement more heavily. Propose package layout, DI approach, key conventions, and explain the reasoning. Present alternatives where multiple valid approaches exist.

Greenfield decisions are more consequential than brownfield ones. In brownfield, a poor choice in one feature is contained by the existing structure. In greenfield, the first feature's structure becomes the template everything else follows. A bad convention or layout is painful to change after several thousand lines of code have been written on top of it. The discussion should be proportionally more thorough.

Greenfield-specific concerns that must be covered:

- **Project skeleton.** `go.mod` setup, top-level directory layout (`cmd/`, `internal/`, `pkg/` if applicable), where tests live, build tooling (Makefile, taskfile, etc.). These are foundational and rarely change. Propose a layout with reasoning — "I'd suggest `cmd/appname/` for the entrypoint and `internal/` for all packages because [reasoning]. Here's what an alternative flat structure would look like."
- **Convention establishment.** You are setting the conventions that all future code will follow. Error handling approach, logging strategy, config management, naming conventions for packages and types. In brownfield these already exist; in greenfield you are choosing them for the first time. Be deliberate — a convention chosen carelessly now will be copied everywhere.
- **Foundational dependencies.** Choosing the HTTP framework (or stdlib `net/http`), logging library, config library, and testing utilities for a new project is not the same as adding a library to an existing project. These are the foundation. They constrain everything downstream and are the hardest to change later. Give them more attention than you would a library choice in brownfield.

#### Topics

These are the areas the discussion should cover. Not every topic needs lengthy discussion — scale to complexity. A small feature in a brownfield codebase might cover all of these in a few minutes. A greenfield project might spend significant time on each.

**Project structure.** Where will new code live? What packages will be created? How do they relate to existing packages? What are the dependency relationships? For greenfield: what is the overall package layout and why? (See greenfield-specific concerns above.)

**Patterns.** What structural patterns should the new code follow? This includes:
- Dependency injection approach (constructor injection, functional options, config structs)
- Service/manager patterns (common interfaces like `Init/Run/Close`, lifecycle management)
- Data access patterns (repository pattern, DAO/DTO separation)
- API boundary patterns (facades, adapters)
- Builder or fluent patterns for complex construction
- Any other pattern that affects how components are structured and connected

For greenfield, these are foundational choices — they set the vocabulary the entire codebase will use. For brownfield, they should follow existing conventions unless there is a good reason to deviate.

These are decisions that affect file, package, and interface structure. They must be agreed before scaffolding, not left to emerge during TDD. TDD drives internal behaviour; these patterns drive external structure.

Internal patterns — extracting a helper, choosing a map over a slice, simplifying control flow — are TDD territory. They emerge during refactoring. The line is: **would a different choice change the file, package, or interface structure?** If yes, decide it here. If no, let TDD handle it.

**Libraries.** Should the feature use existing libraries (internal or external) or build from scratch?

Suggest relevant options with links and a brief note on each. The user will look at them and decide what to investigate further. Do not spend time doing deep evaluation upfront — surface the options, recommend one with reasoning, and let the user steer. For greenfield, foundational library choices (HTTP, logging, config, testing) deserve more discussion than incidental ones — see greenfield-specific concerns above.

- **Consider the standard library first.** Especially in Go, the standard library covers a lot. "Build with stdlib" should always be on the table as an option.
- **Do not rely on training knowledge alone.** Libraries get deprecated, licences change, better alternatives appear. If you are not confident a library is current, say so. When the user asks you to investigate a specific library, then do the deeper evaluation — check maintenance status, licence, API fit.
- **When the user suggests a library**, look into it honestly. Does it fit? Is the API appropriate? Would it introduce awkward dependencies? Give a straight assessment — do not blindly adopt, and do not blindly dismiss.

**Construction and wiring.** How will new components be constructed? How will they be connected to the rest of the application? What dependencies need injecting? This is where DI decisions become concrete: "The retrier will be constructed via `NewRetrier(cfg Config, backoff BackoffStrategy)` and injected into the HTTP client at startup."

#### Detecting Gaps

The architecture discussion will surface things the brainstorming document did not cover. Handle them based on severity:

**Clarification** (ambiguous wording, unclear boundary): Resolve it in the discussion. Record the clarification back into the brainstorming document in the correct section (see [Updating the Brainstorming Document](#updating-the-brainstorming-document)).

**Design gap** (something the brainstorming document did not consider that affects the approach — a missing abstraction, a conflicting requirement, an assumption that does not hold against the codebase): Stop the architecture discussion. Note what was discovered and why it matters. The brainstorming document needs updating before the plan can continue.

The user decides whether to re-invoke the brainstorming skill or resolve it directly. Either way, the gap and its resolution must be tracked in the brainstorming document. The note must be clear enough that brainstorming can be re-invoked in a fresh context and know exactly what gap to address.

This is different from the architecture discussion revealing that a *pattern* or *structural choice* needs making — that is this skill's job. A design gap is when the fundamental *approach* chosen in brainstorming does not work or has an unconsidered aspect.

#### Recording Decisions

As decisions are agreed during the discussion, note them — you will write them into the plan document's Technical Decisions section later. Each decision should capture:
- What was decided
- Why (the reasoning, not just the conclusion)
- Whether it is a **structural constraint** (must be followed during TDD) or a **stylistic preference** (follow unless TDD reveals a better approach). If the boundary is unclear, surface it for discussion rather than guessing — ambiguity here causes confusion during TDD.
- If the user chose something you recommended against, note the trade-off. This is not passive-aggressive documentation — it is useful context for the TDD agent if something goes wrong later.

### 4. Produce the Scaffolding

The scaffolding is the public API: interfaces, exported types, function signatures, file structure. These implement the architectural decisions agreed in step 3. They define the contract that callers will use and that tests will exercise.

```
SCAFFOLDING IS STRUCTURE, NOT LOGIC
```

The scaffolding contains **no implementation**. Function bodies return zero values. No conditionals, no loops, no helper calls, no error wrapping, no validation — nothing that constitutes behaviour. If it could appear in a test assertion, it does not belong in the scaffolding. The TDD cycle fills in all logic.

**Scaffolding includes:**
- New types, structs, interfaces and where they live
- Changes to existing types (new fields, new methods, interface additions)
- New files and their locations
- Function signatures with their parameters and return types
- Dependencies between new and existing components

**Scaffolding does not include:**
- Any logic inside function bodies (return zero values only)
- Helper or utility functions (these emerge during TDD)
- Error handling beyond `return` with zero values
- Wiring, registration, or integration code
- Anything that "seems obvious" to implement now

If you catch yourself writing `if`, `for`, `switch`, or calling another function inside a scaffolded body — stop. That is implementation. Delete it and return zero values.

<Good>

```go
func (r *retrier) Retry(ctx context.Context, fn func() error) (err error) {
	return
}
```

</Good>

<Bad>

```go
func (r *retrier) Retry(ctx context.Context, fn func() error) (err error) {
	for i := range r.maxAttempts {
		if err = fn(); err == nil {
			return
		}
		r.backoff.Wait(i)
	}
	return
}
```

This is implementation, not scaffolding. The TDD cycle drives this code into existence through failing tests.

</Bad>

**The scaffolding is created before TDD starts.** The implementation plan skill creates the files, types, interfaces, and function signatures (with zero-value returns) in the codebase. This gives the TDD skill a concrete API to write tests against. The tests are black-box from the caller's perspective — they test the behaviour of the public API, not internal structure.

**The scaffolding is also the plan materialised in code.** If the TDD skill needs to change an interface, add an exported field, or alter a function signature, that is a deviation from the plan. It must be raised with the user and the plan updated before the change is made. This is how the plan enforces consistency across the TDD cycle.

Be specific:
<Good>

- Create `internal/retry/retry.go` with `Retrier` interface: `Retry(ctx context.Context, fn func() error) error`
- Add `MaxAttempts int` and `Backoff BackoffStrategy` fields to `internal/retry/config.go:Config`
- Create `BackoffStrategy` interface in `internal/retry/backoff.go`: `Wait(attempt int) time.Duration`

</Good>

<Bad>

- Create retry package with necessary types
- Add configuration options
- Create backoff interface

</Bad>

### 5. Produce the Test Manifest

The test manifest is an ordered list of behaviours that must be tested, grouped into implementation chunks. Each entry describes **what** to test, not **how** — the TDD skill writes the actual test code.

The manifest is a **minimum bound**. The TDD skill must cover every entry but may add more tests if it discovers additional cases during implementation. The TDD skill cannot skip or remove entries without the user's approval.

#### Manifest Structure

Each entry has:
- **Behaviour**: what the test proves, in plain language
- **Context**: any setup, preconditions, or relevant details the TDD skill needs
- **Expected outcome**: what should happen (pass, fail, error, specific value, etc.)
- **Boundaries**: what this test is and is not responsible for (prevents over-engineering during the GREEN step)

#### Chunking

The test manifest is divided into **implementation chunks**. Each chunk is a coherent unit of work that can be implemented, reviewed, and committed independently.

**Why chunk?** Two reasons, both important:

1. **Reviewability.** Agentic programming produces code fast, which makes thorough review harder. Large, monolithic PRs get "LGTM'd" without proper scrutiny. Each chunk produces a commit that a reviewer can understand on its own — what it does, why, and whether the implementation is correct. The goal is that no single commit requires holding the entire feature in the reviewer's head.

2. **Context management.** Each chunk is small enough to complete in a single context. The TDD skill can cold-start any chunk by reading the plan document. If context fills up or a session ends, no work is lost and no context needs reconstructing.

**How to chunk:**

Chunks should follow naturally from the architecture. If the architecture discussion produced clear packages and component boundaries, the chunks map to those boundaries: "build the repository layer, then the service layer that uses it, then the handler that uses the service, then wire it together."

Each chunk:
- Has a **name and theme** (e.g. "Core retry logic", "Backoff strategies", "HTTP client integration")
- Contains a subset of manifest entries that form a coherent, committable unit
- Lists **dependencies on previous chunks** if any (chunk 2 builds on types from chunk 1)
- Targets roughly **150-200 lines of actual implementation** (excluding tests) as a guideline — the real constraint is reviewability and coherence, not a line count
- Ends with **wiring/integration entries** where appropriate (the final chunk must include wiring into the application)

If chunks do not fall out naturally from the architecture, that is a signal the architecture discussion may not have produced clear enough boundaries. Revisit before continuing.

Order chunks by dependency first, then by what makes the most logical progression for a reviewer. Within each chunk, order entries from simple to complex: basic behaviour first, edge cases and error handling after, interactions last.

#### Integration / Wiring Tests

The final entries in the manifest must verify that the feature is **wired into the application** — not just that it works in isolation. A feature with passing unit tests but no integration point is incomplete. The user should be able to use the feature after TDD is done, not discover it still needs to be hooked up.

What "wired in" means depends on the feature:
- A new handler is registered on the router
- A new service is constructed and injected where it is needed
- A new CLI subcommand is reachable
- A new middleware is applied to the relevant chain
- A new configuration option is read and passed to the component that uses it

The wiring test exercises the real integration path. It constructs the application (or the relevant subsystem) and verifies the feature is reachable through the normal entry point. This is not a full end-to-end test — it is a focused test that proves the feature is connected.

If wiring requires changes to existing code (adding a field to a struct, calling a registration function, updating a constructor), include those changes in the scaffolding and note them explicitly.

#### Example

```markdown
### Chunk 1: Core Retry Logic

1. **Retry succeeds on first attempt without retrying**
   - Context: Operation succeeds immediately
   - Expected: Returns result, no retries performed
   - Boundaries: Does not test backoff or error handling

2. **Retry succeeds after transient failures**
   - Context: Operation fails twice then succeeds
   - Expected: Returns result after third attempt
   - Boundaries: Does not test max attempts or backoff timing

3. **Retry returns last error after max attempts exhausted**
   - Context: Operation fails on every attempt, max attempts = 3
   - Expected: Returns error from final attempt
   - Boundaries: Does not test backoff, does not test context cancellation

4. **Retry respects context cancellation**
   - Context: Context cancelled between retry attempts
   - Expected: Returns context error, does not attempt further retries
   - Boundaries: Does not test backoff timing

5. **Retry does not retry non-retryable errors**
   - Context: Operation returns an error marked as non-retryable
   - Expected: Returns error immediately without retrying
   - Boundaries: Only tests the retryable check, not retry logic itself

### Chunk 2: Backoff Strategies

_Depends on: Chunk 1_

6. **Retry applies backoff between attempts**
   - Context: Operation fails, custom backoff strategy provided
   - Expected: Backoff strategy called with correct attempt number between retries
   - Boundaries: Tests backoff integration, not backoff calculation

### Chunk 3: HTTP Client Integration

_Depends on: Chunk 1, Chunk 2_

7. **HTTP client uses retry for transient failures**
   - Context: HTTP client is constructed with default configuration
   - Expected: Client's transport wraps requests with the retry mechanism; a request that receives a 503 is retried
   - Boundaries: Tests wiring and integration, not retry logic (covered above)
```

### 6. Respect Out of Scope

Cross-reference the test manifest against the brainstorming document's out of scope section. If a test entry touches something explicitly excluded, remove it. If you are unsure, ask the user rather than including it.

### 7. Create the Scaffolding in the Codebase

This is not just documentation — the scaffolding is created as actual code. But it is created **incrementally with the user**, not dumped all at once.

#### Present, then create

For each piece of scaffolding (a new file, a type, an interface, a set of related function signatures):

1. **Explain what you are about to create and why.** What architectural decision does this implement? Why this type/interface/signature? Why in this file?
2. **Show the code you will write.** The user sees exactly what will be created before it exists.
3. **Wait for the user's response.** They may approve, ask questions, or request changes. Do not proceed until they are satisfied with this piece.
4. **Create it in the codebase**, then move to the next piece.

This is a conversation, not a code dump. The user should understand every structural choice and have the opportunity to shape it. If they say "that looks wrong" or "I'd prefer a different signature", adjust before writing.

**Batch sensibly.** Closely related items (a struct and its constructor signature, an interface and its primary implementation type) can be presented together. Unrelated items should be separate. Use judgement — the goal is that nothing surprises the user when they look at the code afterwards.

#### What gets created

The scaffolding contains **no logic**. Function bodies return zero values — no conditionals, no loops, no calls. The TDD cycle fills them in. If you find yourself writing anything beyond `return` in a function body, stop. That is implementation, not scaffolding.

### 8. Write the Plan Document

The plan document is built **section by section with the user**, not written all at once. This is the same principle as the scaffolding step — present, explain, wait for approval, then write. The plan is a conversation, not a document dump.

#### Section-by-section presentation

Present each section of the plan in order. For each section:

1. **Present the section with your reasoning.** Explain the choices — why this ordering, why these chunks, why these test entries, why these boundaries. The user should understand the thinking, not just the output.
2. **Wait for the user's response.** They may approve, ask questions, propose changes, or disagree with the approach.
3. **If changes are requested, assess the ripple effect.** A change to one section may invalidate or alter sections already agreed. Before accepting a change, check whether it affects:
   - The technical decisions (does a pattern choice need revisiting?)
   - The scaffolding (does a signature need changing? does a new type need adding?)
   - Earlier test manifest entries (do boundaries need updating? does ordering need changing?)
   - Later test manifest entries (are they still valid given this change?)
   - Chunk boundaries (does a test need to move between chunks?)
   - The scaffolding already created in the codebase (does code need updating to match?)
4. **If there is a ripple effect, surface it.** Tell the user what else would change and why. Do not silently absorb a change that contradicts an earlier decision — make the conflict visible so the user can decide.
5. **Once approved, write the section** and move to the next.

**The sections, in order:**

1. **Technical Decisions** — what was agreed in step 3. This section should already be agreed from the architecture discussion, so present it for confirmation rather than debate. Ensure each decision is clearly marked as structural constraint or stylistic preference.
2. **Scaffolding summary** — what was created in step 7, documented for the TDD skill. This section should already be agreed from the scaffolding step, so present it for confirmation rather than discussion.
3. **Test manifest** — present chunk by chunk. Each chunk is a natural pause point for discussion. Do not present all chunks at once.
4. **Notes** — anything discovered during codebase exploration that the TDD skill should know.

The Progress section starts empty — it is populated by the TDD skill during implementation.

#### After all sections are approved

Save the implementation plan to: `YYYY-MM-DD-<topic>-plan.md` in the project root. Use the same date and topic as the brainstorming document for easy association.

Do not commit the plan or the scaffolding. The user will handle that.

#### The TDD Workflow

Once the plan is written:

1. **Commit the scaffolding.** This is the first commit — structure only, no behaviour.
2. **For each chunk, in order:**
   a. The TDD skill works through the chunk's manifest entries using RED-GREEN-REFACTOR.
   b. After each REFACTOR step, the assessment includes: "Does this follow the patterns and conventions in the Technical Decisions section?"
   c. After completing all entries in the chunk, commit.
   d. If context is full or a session ends, a fresh context can pick up from the next chunk by reading the plan document.
3. **After the final chunk:** run the full verification checklist.

The plan document structure:

```markdown
# [Topic] Implementation Plan

**Design document:** [filename of brainstorming document]

**Goal:** [one sentence, from the brainstorming document]

## Technical Decisions

[Decisions agreed during the architecture discussion. For each decision:
what was decided, why, and whether it is a structural constraint or
stylistic preference.

If the user chose something against the recommendation, note the
trade-off — this is context for the TDD skill, not commentary.]

## Scaffolding

[Structural changes that were created in the codebase — types, interfaces, files,
field additions. This section documents what was done, not what needs to be done.
Include exact file paths and type definitions so the TDD skill knows what exists.]

## Test Manifest

[Ordered list of test entries grouped into chunks. Each chunk has a name,
theme, dependencies on previous chunks, and the test entries with behaviour,
context, expected outcome, and boundaries.]

## Progress

[Initially empty. As the TDD skill works through the manifest, entries are marked
as done here. Updated after each RED-GREEN-REFACTOR cycle — which entries were
completed, any modifications, any additional tests discovered. This section
persists across sessions — it is how a fresh context knows where to pick up.]

## Notes

[Anything discovered during codebase exploration that the TDD skill should know —
existing patterns, potential pitfalls, relevant test utilities already available.
Omit this section if there is nothing to note.]
```

### Tracking Progress

The implementation plan must persist across sessions and context compactions. A fresh agent with no memory of previous work must be able to read the plan and know exactly where things stand.

The **Progress** section exists for this purpose. It starts empty and is updated by the TDD skill during implementation. Between the technical decisions (how to build), the scaffolding section (what exists in the codebase), the test manifest (what must be done, chunked), and the progress section (what has been done), a fresh context has enough information to continue without repeating work or missing entries.

## Updating the Brainstorming Document

When this skill records a clarification or decision back into the brainstorming document:

- Put it in the correct section (a new constraint goes in Constraints, a scope change updates Out of Scope, etc.)
- Do not append to the end of the document
- Do not add "addendum" or "update" headings
- The document must read as coherent — as if it was written in one pass
- Do not rewrite or restructure sections that are unaffected

## Updating the Plan

The implementation plan is a living document during the TDD phase. If the TDD skill:

- **Adds tests**: New entries are added to the manifest (within the appropriate chunk) with a note that they were discovered during implementation
- **Discovers a test is not possible or does not make sense**: The entry is updated with an explanation and the user's approval is recorded
- **Discovers scaffolding changes**: The scaffolding section is updated and the user is informed
- **Discovers a technical decision needs revising**: The Technical Decisions section is updated with the change and reasoning

The plan should reflect what was actually done, not just what was originally planned. This keeps it useful as a historical record even though it is a transient artefact.

## Key Principles

- **Collaborator, not transcriber** — propose, defend, concede. Have opinions. The user has the final say but expects your technical judgement
- **Architecture before scaffolding** — structural decisions are discussed and agreed, not made implicitly during scaffolding production
- **Greenfield gets more attention** — when there is no existing codebase to follow, actively propose structure rather than asking the user to dictate it
- **Behaviours, not test code** — the manifest says what to test, the TDD skill decides how
- **Chunked for reviewability** — each chunk is a coherent, independently reviewable commit. No mega-PRs
- **Order matters** — simple first, complex last, dependencies respected, within and across chunks
- **Minimum bound** — every entry must be covered, more can be added, nothing skipped without approval
- **Specific scaffolding** — exact types, exact fields, exact file paths
- **Out of scope is respected** — do not test what was explicitly excluded
- **Codebase over assumptions** — read the code, do not rely solely on the brainstorming document for implementation details
- **Honest about library knowledge** — suggest options with links, flag when you are not confident something is current. Investigate deeper when asked, not upfront
- **Cold-start capable** — the plan document must be detailed enough that a fresh agent can pick up any chunk without context from prior conversations
