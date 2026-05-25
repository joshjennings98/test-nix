# Testing Anti-Patterns

**Load this reference when:** writing or changing tests, adding mocks, or tempted to add test-only methods to production types.

## Overview

Tests must verify real behaviour, not mock behaviour. Mocks are a means to isolate, not the thing being tested.

**Core principle:** Test what the code does, not what the mocks do.

**Following strict TDD prevents these anti-patterns.**

## The Iron Laws

```
1. NEVER test mock behaviour
2. NEVER add test-only methods to production types
3. NEVER mock without understanding dependencies
```

## Anti-Pattern 1: Testing Mock Behaviour

**The violation:**

```go
// BAD: Testing that the mock was called, not that the code works
func TestProcessor_SendsNotification(t *testing.T) {
	mock := &MockNotifier{}

	p := NewProcessor(mock)
	p.Process(order)

	assert.True(t, mock.Called)
	assert.Equal(t, 1, mock.CallCount)
}
```

**Why this is wrong:**
- You're verifying the mock works, not that the processor works
- Test passes when mock is present, fails when it's not
- Tells you nothing about real behaviour

**The fix:**

```go
// GOOD: Test real behaviour through the result
func TestProcessor_SendsNotification(t *testing.T) {
	notifier := NewInMemoryNotifier()

	p := NewProcessor(notifier)
	p.Process(order)

	require.Len(t, notifier.Sent, 1)
	assert.Equal(t, order.CustomerEmail, notifier.Sent[0].To)
}
```

Use a real in-memory implementation that preserves behaviour rather than a mock that only records calls.

### Gate Function

```
BEFORE asserting on any mock:
  Ask: "Am I testing real behaviour or just mock existence?"

  IF testing mock existence:
    STOP - Delete the assertion or use a real implementation

  Test real behaviour instead
```

## Anti-Pattern 2: Test-Only Methods in Production

**The violation:**

```go
// BAD: Reset() only used in tests
type ConnectionPool struct {
	conns []*Connection
}

func (p *ConnectionPool) Reset() {
	for _, c := range p.conns {
		c.Close()
	}
	p.conns = nil
}
```

**Why this is wrong:**
- Production type polluted with test-only code
- Dangerous if accidentally called in production
- Violates YAGNI and separation of concerns
- Confuses object lifecycle with entity lifecycle

**The fix:**

```go
// GOOD: Test helpers handle test cleanup
// ConnectionPool has no Reset() - it's not part of the real API

// In testutils/
func CleanupPool(t *testing.T, pool *ConnectionPool) {
	t.Helper()
	for _, c := range pool.Connections() {
		c.Close()
	}
}

// In tests
t.Cleanup(func() { testutils.CleanupPool(t, pool) })
```

### Gate Function

```
BEFORE adding any method to a production type:
  Ask: "Is this only used by tests?"

  IF yes:
    STOP - Don't add it
    Put it in test utilities instead

  Ask: "Does this type own this resource's lifecycle?"

  IF no:
    STOP - Wrong type for this method
```

## Anti-Pattern 3: Mocking Without Understanding

**The violation:**

```go
// BAD: Mock prevents behaviour the test depends on
func TestAddServer_DetectsDuplicate(t *testing.T) {
	// Mock prevents config write that test depends on!
	registry := &MockRegistry{
		RegisterFunc: func(_ Server) error { return nil },
	}

	mgr := NewManager(registry)
	err := mgr.AddServer(config)
	require.NoError(t, err)

	err = mgr.AddServer(config) // Should fail - but won't!
	// Registry mock discards state, duplicate never detected
}
```

**Why this is wrong:**
- Mocked method had a side effect the test depended on (persisting state)
- Over-mocking to "be safe" breaks actual behaviour
- Test passes for wrong reason or fails mysteriously

**The fix:**

```go
// GOOD: Mock at the correct level
func TestAddServer_DetectsDuplicate(t *testing.T) {
	// Use real registry, only mock the slow external call
	registry := NewInMemoryRegistry()

	mgr := NewManager(registry)
	err := mgr.AddServer(config)
	require.NoError(t, err)

	err = mgr.AddServer(config) // Duplicate detected
	errortest.AssertError(t, err, commonerrors.ErrConflict)
}
```

### Gate Function

```
BEFORE mocking any dependency:
  STOP - Don't mock yet

  1. Ask: "What side effects does the real implementation have?"
  2. Ask: "Does this test depend on any of those side effects?"
  3. Ask: "Do I fully understand what this test needs?"

  IF depends on side effects:
    Mock at a lower level (the actual slow/external operation)
    OR use in-memory implementations that preserve necessary behaviour
    NOT the high-level dependency the test depends on

  IF unsure what test depends on:
    Run test with real implementation FIRST
    Observe what actually needs to happen
    THEN add minimal mocking at the right level

  Red flags:
    - "I'll mock this to be safe"
    - "This might be slow, better mock it"
    - Mocking without understanding the dependency chain
```

## Anti-Pattern 4: Incomplete Mocks

**The violation:**

```go
// BAD: Partial mock - only fields you think you need
resp := &APIResponse{
	Status: "success",
	Data:   UserData{ID: "123", Name: "Alice"},
	// Missing: Metadata that downstream code uses
}

// Later: panics when code accesses resp.Metadata.RequestID
```

**Why this is wrong:**
- **Partial mocks hide structural assumptions** (you only mocked fields you know about)
- **Downstream code may depend on fields you didn't include** (silent failures or panics)
- **Tests pass but integration fails** (mock incomplete, real API complete)
- **False confidence** (test proves nothing about real behaviour)

**Go makes this particularly dangerous.** Omitted struct fields silently zero-value (empty strings, nils, and zeroes all compile without complaint). Unlike languages that would give you an `undefined` or a missing-key error, Go happily hands you a zero value that passes superficial checks but causes subtle bugs downstream.

**The Iron Rule:** Mock the COMPLETE data structure as it exists in reality, not just fields your immediate test uses.

**The fix:**

```go
// GOOD: Mirror real API completeness
resp := &APIResponse{
	Status: "success",
	Data:   UserData{ID: "123", Name: "Alice"},
	Metadata: Metadata{
		RequestID: "req-789",
		Timestamp: time.Now(),
	},
}
```

### Gate Function

```
BEFORE creating mock responses:
  Check: "What fields does the real response contain?"

  Actions:
    1. Examine actual response from docs/examples
    2. Include ALL fields system might consume downstream
    3. Verify mock matches real response schema completely

  Critical:
    If you're creating a mock, you must understand the ENTIRE structure
    Partial mocks fail silently when code depends on omitted fields

  If uncertain: Include all documented fields
```

## Anti-Pattern 5: Integration Tests as Afterthought

**The violation:**

```
Implementation complete
No tests written
"Ready for testing"
```

**Why this is wrong:**
- Testing is part of implementation, not optional follow-up
- TDD would have caught this
- Can't claim complete without tests

**The fix:**
```
TDD cycle:
1. Write failing test
2. Implement to pass
3. Refactor
4. THEN claim complete
```

## When Mocks Are Acceptable

Mocks are appropriate when simulating external services that are outside your control:

- **External APIs** (mocking a 400/500 response to test your error handling)
- **Third-party services** (simulating timeouts, rate limits, or outages)
- **Infrastructure** (databases, message queues, or cloud services in unit tests)

The key distinction: you're not testing the external service, you're testing **your code's behaviour** when the external service responds in a particular way. Attempting to reproduce these conditions with a real service is reliant on the service not changing, being available, and being deterministic.

Use interfaces to define the boundary:

```go
// Small, focused interface at the boundary
type EmailSender interface {
	Send(ctx context.Context, to string, body string) error
}

// Real implementation for production
type SMTPSender struct { /* ... */ }

// In-memory implementation for tests (preserves behaviour)
type InMemorySender struct {
	Sent []Email
	Err  error // Set this to simulate failures
}

func (s *InMemorySender) Send(_ context.Context, to string, body string) error {
	if s.Err != nil {
		return s.Err
	}
	s.Sent = append(s.Sent, Email{To: to, Body: body})
	return nil
}
```

Prefer in-memory implementations over mock frameworks. They preserve real behaviour and are easier to reason about.

## When Mocks Become Too Complex

**Warning signs:**
- Mock setup longer than test logic
- Mocking everything to make test pass
- Mocks missing methods real implementations have
- Test breaks when mock changes

**Consider:** Integration tests with real components are often simpler than complex mocks.

## TDD Prevents These Anti-Patterns

**Why TDD helps:**
1. **Write test first:** forces you to think about what you're actually testing
2. **Watch it fail:** confirms test tests real behaviour, not mocks
3. **Minimal implementation:** no test-only methods creep in
4. **Real dependencies:** you see what the test actually needs before mocking

**If you're testing mock behaviour, you violated TDD:** you added mocks without watching test fail against real code first.

## Quick Reference

| Anti-Pattern | Fix |
|--------------|-----|
| Assert on mock calls | Test real behaviour or use in-memory implementation |
| Test-only methods in production | Move to test utilities |
| Mock without understanding | Understand dependencies first, mock minimally |
| Incomplete mocks | Mirror real response completely |
| Tests as afterthought | TDD (tests first) |
| Over-complex mocks | Consider integration tests |

## Red Flags

- Assertions only check mock call counts
- Methods only called in test files
- Mock setup is >50% of test
- Test fails when you remove mock
- Can't explain why mock is needed
- Mocking "just to be safe"
- Mocking something internal to the system under test

## The Bottom Line

**Mocks are tools to isolate from external boundaries, not things to test.**

If TDD reveals you're testing mock behaviour, you've gone wrong.

Fix: Test real behaviour or question why you're mocking at all.
