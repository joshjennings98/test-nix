# AGENTS.md

Use British English where possible. If a keyword or library function requires American English then that is acceptable but anything you define should be using British English.

## Go

Note, all logical chunks should have spacing between them. This is things like if statements and for loops etc.

The most important thing is to optimise for readability (and therefore maintainability) above all else.

## Conventions

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
- Context rule: `context.Context` should be the first parameter and named `ctx`. Use this for functions that reasonably should take a context like a long running action you might want to cancel.
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
 - Use `t.Helper()` in test helpers (and sub‑helpers) for accurate line reporting.
   - Example:
     ```go
     func mustLoad(t *testing.T, path string) []byte {
     	t.Helper()
     	data, _ := os.ReadFile(path)
     	return data
     }
     ```
- Prefer `errors.Is/As` over string comparisons.
  - Example:
    ```go
    if errors.Is(err, fs.ErrNotExist) {
    	return err
    }
    if commonerrors.Any(err, commonerrors.ErrInvalid) {
    	return err
    }
    ```
- Prefer `any` over `interface{}`.
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
      
