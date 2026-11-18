---
name: prototype
description: "Build a throwaway prototype to answer a design or implementation question. Use when the user wants to sanity-check whether a specific implementation or logic feels right or would work well, or explore what a UI should look like."
---

A prototype is **throwaway code that answers a question**. The question decides the shape.

## Pick a prototype

Identify what question is being answered from the user's prompt, the surrounding code, by asking if the user, or state of the current conversation. For example:

- **"What might this look like?"** -> [UI Prototyping](UI-prototyping.md): Generate several radically different UI variations on a single route, switchable via a URL search param and a floating bottom bar.
- **"How might this be implemented?"** -> [Implementation Prototyping](Implementation-prototyping.md): This is for code/architecture level prototypes. It could be to show how a system should be integrated with existing code or to demonstrate a pattern. The artefact here is the code itself for viewing by the user.
- **"What would be the consequences of X?"** or **"Why not do it like Y?"** **"How would we do Z?"** -> [Investigating Options](Investigating-options.md): Use this for non-exploratory, non-UI prototypes. The goal of this prototyping path is to show how an option will affect the system as a whole. This is different to UI prototyping as it may provide extra tools for demonstrating a problem (e.g. _hey_ for loadtesting an API implementation) and be more backend focused. This is a kind of mixture of the previous two prototype types.

These are not an exhaustive list of the types of prototypes that you could make. Decide based upon the context of the situation.

Ask the user before making a prototype (it may be that a prototype is overkill for the situation) unless another SKILL is suggesting to make the prototype.

## Rules that apply to all prototypes

1. **Throwaway from day one, and clearly marked as such:** Create a new _git worktree_ with clear naming that indicates it is a prototype. Commit changes to the worktree branch so that the git state is clean. Do not delete the worktree afterwards.
2. **Trivial to run:** Create a _`flake.nix`_ file in the worktree if no nix flake exists, or update the existing one in that worktree. In the event that a protoype is being used to demonstrate some functionality (e.g. UI or API changes) it should provide a "binary" called `prototype` that can be invoked to spin up all dependencies and start the prototype. It should provide clear information in the terminal about what is needed to run or test the prototype. 
3. **Include any necessary dependencies:** The nix flake should include all dependencies needed to run the project (for example: _pnpm_ if demoing a website or _postgres_ if a database is needed). It will also include any dependencies needed for the manual tests (for example: _httpie_ for querying APIs or _hey_ for load testing them). The included dependencies are highly dependent on what is being prototyped.
4. **Skip the polish:** No tests, no error handling beyond what makes the prototype _runnable_, no abstractions, don't care about linting. The point is to get an answer fast.
5. **Capture it when done:** Log the decisions made. Do not fold the code into any other branch. Reference the worktree/branch (along with the specific variant if multiple variants were created as part of the prototype) in any decision document so that it can be referenced when doing the actual implementation. The work done in a prototype is an **unpolished throwaway** and not representitive of the final implementation. 
