# AGENTS.md

Use British English where possible. If a keyword or library function requires American English then that is acceptable but anything you define should be using British English.

## Go

Note, all logical chunks should have spacing between them. This is things like if statements and for loops etc.

The most important thing is to optimise for readability (and therefore maintainability) above all else.

## Conventions

- Prefer short declarations when introducing a new variable, e.g. `src, err := ...`, even in functions with named returns.
- Prefer named returns and naked returns where practical.
  - Example:
    ```go
    func loadThing(path string) (data []byte, err error) {
    	data, err = fs.ReadFile(path)
    	if err != nil {
    		return
    	}
    	return
    }
    ```
- When iterating over maps, use sorted keys:
  - `for _, k := range slices.Sorted(maps.Keys(m)) { ... }`
  - Example:
    ```go
    for _, k := range slices.Sorted(maps.Keys(props)) {
    	prop := props[k]
    	_ = prop
    }
    ```
- For loops over slices/arrays, prefer `for i := range items` over index comparisons, and use `for range items` when the index is not needed.
  - Example:
    ```go
    for i := range records {
    	_ = records[i]
    }
    for range records {
    	// no index needed
    }
    ```
- Context rule: `context.Context` should be the first parameter and named `ctx`.
  - Example:
    ```go
    func Load(ctx context.Context, id string) (err error) {
    	_ = ctx
    	_ = id
    	return
    }
    ```
- Avoid direct string concatenation; use `fmt.Sprint`, `fmt.Sprintf`, or builders.
  - Example:
    ```go
    name := fmt.Sprintf("%s.%s", pkg, typ)
    ```
  - Exception: only allow `+` in truly hot paths where profiling shows it materially outweighs network/IO overhead.
- Use `golang-utils/utils/field` for safe pointer deref.
  - Example:
    ```go
    timeout := field.Optional(cfg.Timeout, 5*time.Second)
    ```
  - Example (optional pointer):
    ```go
    cfg.Timeout = field.ToOptional(10 * time.Second)
    ```
- Use `golang-utils/utils/commonerrors` instead of `fmt.Errorf`.
  - Example:
    ```go
    return nil, commonerrors.Newf(commonerrors.ErrInvalid, "missing %q", name)
    ```
  - Example (wrap):
    ```go
    return nil, commonerrors.WrapErrorf(commonerrors.ErrInvalid, err, "load %q", name)
    ```
  - Example (loop + short var + wrapped sub-error):
    ```go
    field, subErr := propertyToField(logger, fieldName, resolvedProp, ext)
    if subErr != nil {
    	err = commonerrors.WrapErrorf(commonerrors.ErrInvalid, subErr, "property %q", fieldName)
    	return
    }
    _ = field
    ```
  - Avoid:
    ```go
    var field FieldType
    field, err = propertyToField(logger, fieldName, resolvedProp, ext)
    if err != nil {
    	err = commonerrors.WrapErrorf(commonerrors.ErrInvalid, err, "property %q", fieldName)
    	return
    }
    ```
- Use `golang-utils/utils/filesystem` for file operations (use `filesystem.MkDir`, not `os.MkdirAll`).
  - Example:
    ```go
    if err := filesystem.MkDir(outDir); err != nil {
    	return err
    }
    ```
- Keep import order gci-friendly: stdlib → external (including ARM-software) → local (Arm-Debug).
  - Example:
    ```go
    import (
        "context"
        "time"

        "github.com/ARM-software/golang-utils/utils/commonerrors"
        "github.com/stretchr/testify/require"

        "github.com/Arm-Debug/some-internal-repo/common/config"
    )
    ```
 - Use `t.Helper()` in test helpers (and sub‑helpers) for accurate line reporting.
   - Example:
     ```go
     func mustLoad(t *testing.T, path string) []byte {
     	t.Helper()
     	data, _ := os.ReadFile(path)
     	return data
     }
     ```
- Prefer `errors.Is/As` (or `commonerrors.Any` for commonerrors) over string comparisons.
  - Example:
    ```go
    if errors.Is(err, fs.ErrNotExist) {
    	return err
    }
    if commonerrors.Any(err, commonerrors.ErrInvalid) {
    	return err
    }
    ```
- Prefer `any` over `interface{}` in new code (Go 1.18+).
  - Example:
    ```go
    var payload any
    _ = payload
    ```
- Avoid introducing a new err in a nested scope when the function already has a named err return. That includes patterns like if `err := ...; err != nil { ... }`, `for err := range ...`, or `switch err := ....`. These hide the outer err, which makes return behaviour easy to misread. Prefer a distinct name (e.g.
  subErr) in inner scopes and then assign to the named return, for example:
  ```go
  if subErr := doThing(); subErr != nil {
      err = subErr
      return
  }
  ```
  Using := in the same scope is fine when it does not create a new err, e.g. `db, err := ...`` at function scope where err already exists and db is new.
- When using `context.Context`, check for cancellation early in long-running loops or before expensive calls using `parallelisation.DetermineContextError`.
  - Example:
    ```go
    for _, item := range items {
    	if err = parallelisation.DetermineContextError(ctx); err != nil {
    		return
    	}
    	if err = processItem(ctx, item); err != nil {
    		return
    	}
    }
    ```
- For functions that take a `context.Context`, perform a cancellation check near the top (do not nil-check ctx).
  - Example:
    ```go
    func Load(ctx context.Context, id string) (err error) {
    	if err = parallelisation.DetermineContextError(ctx); err != nil {
    		return
    	}
    	_ = id
    	return
    }
    ```
- If a pointer to a configurable dependency is passed (e.g., `logger`, `cfg`, `client`, `metrics`, or optional service interfaces), check for nil before use. Do not blanket-check every interface; only guard those that are optional or can be unset at runtime. Skip compile-time/static dependencies.
  - Example:
    ```go
    func UseConfig(cfg *Config) (err error) {
    	if cfg == nil {
    		err = commonerrors.UndefinedVariable("config")
    		return
    	}
    	return
    }
    ```
- For enums, try to use `enumer`. This lets us generate the sort of useful helpers that you need with enums whilst retaining the iota support.
  - If you need to have `String()` return somthing different use `-linecomment`
  - More information can be found at https://raw.githubusercontent.com/dmarkham/enumer/refs/heads/master/README.md if you need it

## Testing

Don't be a purist. Use tools where they help, but know their limits.

- **Use `testify/require`** for setup and errors (stop the test immediately).
- **Use `testify/assert`** for simple value checks (booleans, strings, counts).
- **Use `google/go-cmp`** for complex structs (superior diff output).

When using commonerrors, prefer error assertions that take `error` values via `golang-utils/utils/commonerrors/errortest`.
- For example:
  ```go
  errortest.AssertError(t, err, commonerrors.ErrInvalid, commonerrors.ErrNotFound)
  errortest.RequireError(t, err, commonerrors.ErrInvalid, commonerrors.ErrNotFound)
  ```
- Avoid string-matching error checks; if you need more detail, use `commonerrors.RequireErrorDescription` or `errortest.AssertErrorDescription`.
  - Example:
    ```go
    errortest.AssertErrorDescription(t, err, "missing id", "invalid payload")
    errortest.RequireErrorDescription(t, err, "missing id", "invalid payload")
    ```

```go
import (
    "testing"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
    "github.com/google/go-cmp/cmp"
)

func TestUserProcessing(t *testing.T) {
    // SETUP
    // Use 'require' to fail fast if setup fails
    user, err := CreateUser("test@example.com")
    require.NoError(t, err, "Setup failed, stopping test")
    require.NotNil(t, user)

    // ACTION
    processedUser := Process(user)

    // ASSERTIONS
    // Use 'assert' for simple scalar values
    assert.Equal(t, "processed", processedUser.Status)
    assert.True(t, processedUser.IsActive)

    // Use 'go-cmp' for complex objects
    // Testify's output for large structs can be unreadable.
    // cmp.Diff shows exactly which field differs (-expected +actual)
    expected := User{
        Email:    "test@example.com",
        Status:   "processed",
        IsActive: true,
        Metadata: map[string]string{"source": "web"},
    }

    if diff := cmp.Diff(expected, processedUser); diff != "" {
        t.Errorf("Process() mismatch (-expected +actual):\n%s", diff)
    }
}
```

_Note: do not add excessive comments, the comments here are to help with the examples._

### Table-Driven Tests (The Gold Standard)

This is the dominant pattern in Go. Combine it with `t.Parallel()` for speed.

```go
func TestParseURL(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        expected    string // simplified for example
        expectedErr error
    }{
        {
            name:  "valid http",
            input: "http://example.com",
            expected:  "example.com",
        },
        {
            name:    "missing protocol",
            input:   "example.com",
            expectedErr: commonerrors.ErrInvalid,
        },
    }

    for _, test := range tests {
        test := test // Capture variable for parallel execution
        t.Run(test.name, func(t *testing.T) {
            t.Parallel()

            actual, err := ParseURL(test.input)

            if test.expectedErr != nil {
                errortest.AssertError(t, err, test.expectedErr)
            }

            require.NoError(t, err)
            assert.Equal(t, test.expected, actual)
        })
    }
}
```

### Integration tests

Integration tests that require external services should run with `-tags=integration`.
- In code: `//go:build integration`
- When running: `go test -tags=integration ./...`

# Generic Code Rules For Agents

## How to use this document

- Treat these rules as defaults for writing and editing code, not just for reviewing it.
- Prefer the smallest correct change that satisfies the rule.
- Use the context section to decide whether the rule applies.
- If two rules conflict, prefer the one that keeps the code clearer and the design more explicit.
- Do not cargo-cult examples. Match the rule to the real boundary, dependency, or readability problem in front of you.

## Rule format

Each rule uses this shape:

- Context: when the rule matters.
- Rule: the direct instruction.
- Apply it like this: the default implementation pattern.
- Watch for: common signals that the rule should be applied.
- Example: included only for high-signal or commonly misapplied rules.

## Rules

### Rule 1: Do not add function aliases without a verified need

**Context**

This applies when code introduces a package-level variable or local alias that only re-exposes another function.

**Rule**

Call dependencies directly unless there is a specific, verified reason to introduce indirection.

**Apply it like this**

- Keep simple orchestration code direct.
- Extract pure mapping or transformation logic into small helpers and test those directly.
- If substitution is genuinely required, use an explicit wrapper, interface, or injected dependency that shows why the seam exists.

**Watch for**

- A variable exists only to point at another function.
- Tests mutate package state to observe simple input/output shaping.
- The real dependency name is hidden for no runtime reason.

**Example**

```go
var runThing = external.Run

func Execute(cfg Config) (err error) {
	err = runThing(buildInput(cfg))
	return
}
```

Prefer:

```go
func Execute(cfg Config) (err error) {
	err = external.Run(buildInput(cfg))
	return
}
```

### Rule 2: Match dependency injection to the real boundary

**Context**

This applies when deciding whether code needs a seam for testing, substitution, retries, alternate behaviour, or runtime configuration.

**Rule**

Introduce dependency injection only after identifying the exact reason the dependency must be substitutable. Use the smallest seam that matches that reason.

**Apply it like this**

- Use a pure helper for mapping, validation, or shaping logic.
- Use a function parameter for a narrow, local behavioural seam.
- Use a small consumer-side interface for meaningful substitutable behaviour.
- Use a wrapper type or service struct when several dependencies belong to one object lifetime.
- Avoid mutable package-level variables as the default test seam.

**Watch for**

- Tests assign to globals and restore them in cleanup.
- Injection is being added even though the code only constructs data and passes it through.
- The seam is broader than the real behaviour under test.

### Rule 3: Make dependency seams explicit, or change the code shape until they are unnecessary

**Context**

This applies when the only available seam seems to be a hidden package-level function variable or another form of disguised injection.

**Rule**

Do not use mutable package-level function variables as hidden dependency injection. If the dependency is fixed, make it a normal function. If it is genuinely substitutable, model that boundary explicitly.

**Apply it like this**

- Keep fixed behaviour as ordinary functions.
- Use a small interface when the consumer truly depends on variable behaviour.
- If no clean interface emerges, reconsider the code shape: extract pure logic, move responsibility, or test at a higher boundary.

**Watch for**

- Tests patch package variables in `t.Cleanup`.
- Functions look ordinary but are secretly runtime-configurable.
- Several tiny seams exist only to unit-test one orchestrator step by step.

**Example**

```go
var resolveThing = shared.ResolveThing
```

Prefer either a normal function when behaviour is fixed:

```go
func resolveThing(ctx context.Context, input Input) (thing Thing, err error) {
	thing, err = shared.ResolveThing(ctx, input)
	return
}
```

Or an explicit interface when behaviour is genuinely substitutable.

### Rule 4: Treat `_ = singleVariable` as a smell to explain, not a pattern to copy

**Context**

This applies when code names a variable or parameter and then discards it purely to silence the compiler.

**Rule**

Do not use `_ = singleVariable` as the default fix for an unused value. Work out why it is unused, then apply the explicit correction that matches that cause.

**Apply it like this**

- If a required parameter is genuinely unused, mark it as `_` in the signature.
- If the parameter should not exist, remove it where possible.
- If the value points to missing logic, implement the logic.
- If the unused value is `ctx`, check whether cancellation handling is missing.
- Treat generated `_ = value` lines as scaffolding to review, not production guidance.

**Watch for**

- A line exists only to say `_ = value`.
- A stub names several parameters and discards them immediately.
- A generated file compiles by ignoring meaningful values.

**Example**

```go
run = func(ctx context.Context, logger Logger, _ Input) (err error) {
	_ = ctx
	_ = logger
	return
}
```

Prefer:

```go
run = func(_ context.Context, _ Logger, _ Input) (err error) {
	return
}
```

### Rule 5: Establish invariants once at the boundary, then rely on them internally

**Context**

This applies when the same validation, nil check, or normalisation appears repeatedly in one call path.

**Rule**

If code depends on an invariant, establish it at the earliest boundary that owns the contract, then rely on it internally.

**Apply it like this**

- Decide what must be true: non-nil dependency, valid config, authenticated caller, normalised option, and so on.
- Identify the owning boundary: constructor, factory, public entry point, parser, deserialiser, composition root.
- Enforce or normalise it there.
- Keep downstream code simple unless execution crosses a new trust boundary.

**Watch for**

- The same guard appears in several functions in the same flow.
- Helpers defend against broken setup that should have failed earlier.
- Wrappers exist only to hide repeated nil checks.

### Rule 6: Decide the logger contract once, then log normally

**Context**

This applies when a logger can be required or optional and the code is repeatedly checking, ignoring, or patching it.

**Rule**

Decide at setup time whether the logger is required or optional. Enforce that once, then use the logger directly.

**Apply it like this**

- Required logger: reject `nil` at construction or the public boundary.
- Optional logger: replace `nil` with a no-op logger at construction or the public boundary.
- Do not keep re-checking the logger in internal helpers or methods.

**Watch for**

- `if logger == nil` appears in multiple functions.
- A logger parameter is accepted and then ignored.
- A helper exists only to make logging safe against nil.

### Rule 7: Make tests declarative, and make test helpers authoritative

**Context**

This applies when writing or refactoring tests in a codebase that already has a chosen testing style or assertion library.

**Rule**

Use the chosen assertion style consistently. Helpers should normally own setup failures instead of returning errors for every caller to check.

**Apply it like this**

- Use `require` for setup, preconditions, and failures after which the test cannot continue.
- Use `assert` for ordinary value checks when further failures would still be useful.
- Use `go-cmp` for complex structure comparisons.
- Write helpers that take `*testing.T`, call `t.Helper()`, and fail internally when success is required for the test to proceed.
- Keep trivial one-off setup inline.

**Watch for**

- Tests use handwritten `if ... { t.Fatal(...) }` for ordinary assertions.
- A helper returns `(value, error)` and every caller immediately does `require.NoError`.
- Assertion style varies across nearby tests without a good reason.

### Rule 8: In slice loops, iterate over the real subject and keep per-item errors distinct

**Context**

This applies when looping over slices or arrays, especially in functions that already have a named or outer `err`.

**Rule**

Range over the value when the value is the subject of the logic. Keep the index only when the index itself matters. If per-item work can fail and an outer `err` already exists, use `subErr` for the inner failure.

**Apply it like this**

- Use `for _, item := range items` when the loop is about each value.
- Use `for i, item := range items` when both index and value matter.
- Use `for i := range items` only when the index is the real subject.
- Avoid repeated `items[i]` lookups when the value is what matters.
- Keep the function-level error as `err` and the inner per-item error as `subErr` when shadowing would otherwise occur.

**Watch for**

- The first line inside the loop is `item := items[i]`.
- The loop body introduces a new `err` even though an outer `err` already exists.
- Error wrapping inside the loop is hard to follow.

**Example**

```go
func transformAll(values []Value) (results []Result, err error) {
	for i := range values {
		result, subErr := transform(values[i])
		if subErr != nil {
			err = subErr
			return
		}

		results = append(results, result)
	}

	return
}
```

Prefer:

```go
func transformAll(values []Value) (results []Result, err error) {
	for _, value := range values {
		result, subErr := transform(value)
		if subErr != nil {
			err = subErr
			return
		}

		results = append(results, result)
	}

	return
}
```

### Rule 9: Use named and naked returns when they make the function read as a linear flow

**Context**

This applies to Go functions whose work is a straightforward sequence of validation, loading, parsing, transformation, and finalisation steps.

**Rule**

Prefer named return values and naked returns when they make the function read as one clear sequence of steps. Do not force the style when it makes the returned state harder to understand.

**Apply it like this**

- Use named returns when the return set is small and stable.
- Keep the body as a visible sequence of state updates and guard clauses.
- Use short declarations such as `value, err := ...` when they remain clearer and do not create a shadowing problem.
- Switch to explicit returns when branches return materially different states or the return set is too large.

**Watch for**

- The function is linear, but every branch reconstructs explicit return tuples.
- Predeclared locals exist only to avoid `x, err := ...`.
- Named returns start to obscure rather than clarify the result state.

**Example**

```go
func loadThing(path string) (data []byte, err error) {
	data, err = os.ReadFile(path)
	if err != nil {
		return
	}

	return
}
```

### Rule 10: Do not preallocate slices by default when append flow is clearer

**Context**

This applies when building a result slice by appending values.

**Rule**

Do not preallocate with `make(..., 0, n)` by default. Prefer the simpler append-based form unless preallocation materially improves understanding or there is evidence that the path is performance-sensitive.

**Apply it like this**

- Use `var items []T` followed by `append` for ordinary accumulation.
- Use `make` when initial length is part of the meaning.
- Use capacity preallocation only as a deliberate optimisation.

**Watch for**

- A slice is preallocated simply because the source length is available.
- The code offers no evidence that allocation behaviour matters in this path.
- The capacity argument draws more attention than the actual logic.

### Rule 11: Prefer explicit string formatting over punctuation-heavy concatenation

**Context**

This applies when constructing strings whose shape is easier to understand as a template than as a sequence of `+` operations.

**Rule**

Prefer the clearest string-building form. Use `fmt.Sprintf`, `fmt.Sprint`, or a builder when that makes the string shape easier to read than direct concatenation.

**Apply it like this**

- Use `fmt.Sprintf` when punctuation or ordering is part of the meaning.
- Use `fmt.Sprint` when values are being combined and the layout is obvious.
- Use direct concatenation only when it is genuinely the clearest form.
- Use lower-level concatenation or builders for hot paths only when measurement justifies it.

**Watch for**

- A string is assembled from several parts with punctuation such as `.`, `/`, `:`, or suffix markers.
- The concatenation reads like an operator chain rather than one obvious template.

### Rule 12: For enum-like values, prefer typed constants with generated helpers

**Context**

This applies in Go when a set of constants clearly represents one closed set of states, modes, or lifecycle values.

**Rule**

Model enum-like values with a named type and named constants. Generate helper methods when the type needs enum-like ergonomics.

**Apply it like this**

- Define a real named type such as `type Status int`.
- Define named constants on that type.
- Use `enumer` when the type needs `String()`, parsing, value lists, validation helpers, or JSON/text support.
- Keep tiny local constant groups simple when no helper behaviour is needed.

**Watch for**

- Raw constants are acting like an enum without enum support.
- Parsing, listing, or validation logic is being rewritten by hand around the same constant group.
- Logs or serialisation need readable string forms.

### Rule 13: Write validation rules so the contract reads clearly at the call site

**Context**

This applies when validation code is part of a type's readable contract, especially when using a validation library.

**Rule**

Keep validation readable and declarative at the call site. Use built-in rules when they express the contract clearly, and use small named helpers for custom rules.

**Apply it like this**

- Keep `Validate()` close to the type it validates.
- Use declarative validation shapes such as `validation.ValidateStruct` and `validation.Field` when that is the project pattern.
- Prefer built-in rules over custom logic when they fit.
- Use `validation.By(namedRule)` for custom behaviour that still represents one named concept.
- Normalise inputs before validation when that makes the rules simpler and more truthful.

**Watch for**

- The call site hides the real rules behind anonymous functions.
- Distant helpers make the validation contract hard to scan.
- Simple built-in checks have been replaced with bespoke logic for no real gain.

**Example**

```go
func (item Widget) Validate() (err error) {
	err = validation.ValidateStruct(&item,
		validation.Field(&item.ID, validation.Required),
		validation.Field(&item.Status, validation.Required, validation.In("pending", "running", "failed", "succeeded")),
		validation.Field(&item.Position, validation.By(validateOptionalRequiredString)),
	)
	return
}
```

### Rule 14: At boundaries, let schema describe shape and validation describe behaviour

**Context**

This applies when transport or boundary types come from schema-driven contracts and still need richer runtime checks.

**Rule**

Keep transport shape in schema and generated types. Use code-level validation for the richer procedural rules that schema does not express well.

**Apply it like this**

- Let the schema own the wire contract.
- Let generated types reflect that contract honestly.
- Use validation and normalisation code for procedural checks, cross-field logic, and generator gaps.
- Avoid duplicating wire-shape description in validation code.

**Watch for**

- Validation code is re-documenting the schema instead of adding behavioural rules.
- Schema is being stretched to express procedural logic that reads better in code.

### Rule 15: Split files by role once the package has enough shape to justify it

**Context**

This applies when a Go package has grown beyond one file being a useful overview.

**Rule**

Split files by role once interfaces, types, and implementation logic start competing for space in the same file.

**Apply it like this**

- Keep small packages in one file while that remains the clearest shape.
- Once the package has enough content, separate interfaces, related types, and main behaviour by role.
- Use predictable filenames such as `interfaces.go`, `types.go`, and an entry-point file like `publish.go` or `validate.go`.
- Avoid splitting tiny packages purely for symmetry.

**Watch for**

- One file contains several interfaces, several types, and the package behaviour all mixed together.
- Readers must scroll through contracts and type declarations just to reach the logic.

## Smaller defaults

Use these as quick heuristics while editing:

### S1: Avoid `must*` names when the signature already says the function cannot fail

- Prefer names that describe behaviour.
- Reserve `must*` for deliberate panic-on-failure conventions or similarly exceptional cases.

### S2: Avoid predeclaring locals just to dodge `x, err := ...`

- If `x` is new and `err` is being reused in the same scope, `x, err := ...` is usually the clearest form.

### S3: Prefer emptiness checks when emptiness is the real concern

- Use `len(x) == 0` when emptiness is what matters.
- Reserve `x == nil` for cases where nil itself has distinct meaning.

### S4: Prefer early `continue` and `return` over unnecessary nesting

- Keep the main path flat unless the nesting expresses real structure.

### S5: Avoid speculative helper extraction

- Extract a helper when the name makes the code clearer or the logic is genuinely reused or self-contained.
- Do not extract just because a block is a few lines long.

### S5.5: Do not hide trivial test setup behind tiny helpers

- Keep one-off or obvious setup inline.
- Extract only when it removes meaningful repeated noise or establishes an important test contract.

### S6: Prefer one clear state variable over several parallel booleans

- Use one state representation when that expresses the logic more clearly than several flags.

### S7: Avoid configuration-shaped local code when simple values are enough

- Do not introduce small local structs, maps, or option bags just to carry a couple of values within one function.

### S8: Keep validation close to the value it protects

- Keep a check near the value or operation it exists to protect.

### S9: Prefer direct assignment over passthrough locals

- Remove locals that add no meaning before returning or assigning a value.
- If the destination is a named return, prefer assigning to it directly.

### S10: Avoid default variables that are far from where they matter

- Keep defaults near the branch or construction site that uses them unless they are true constants.

### S11: Prefix interface names with `I`

- When the codebase follows this convention, use `I`-prefixed names to make interface roles explicit.

### S12: Keep method receivers short, and do not add fake receiver usage

- Use short receiver names when needed.
- If a receiver is unused, do not invent a name and then discard it.

### S13: Name orchestration types by their domain role, not by vague process words

- Prefer specific domain names over catch-all names such as `manager`, `processor`, or `flow`.

## Agent reminder

When applying these rules, prefer the minimal change that makes the design clearer. If following a rule would require a large refactor, first check whether a smaller local fix can achieve the same clarity without inventing new abstractions.
