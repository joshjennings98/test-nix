package check

import (
	"context"
	"fmt"
	"path/filepath"
	"testing"

	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go-design-check/internal/analysis"
)

func TestInterfaceUncertaintyReview(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example.com/review\ngo 1.26\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "app.go"), []byte(`package review
func Run(err error) { _ = err.Error() }
func Register() {}
type Failure struct{}
func (Failure) Error() string { Register(); return "failure" }
func Callback(f func()) { f() }
type Generic[T any] struct{}
func (Generic[T]) Value() T { var value T; return value }
func Dispatch(value interface { Value() string }) { value.Value() }
`), 0600))
	graph, err := analysis.Load(context.Background(), analysis.Options{Root: root})
	require.NoError(t, err)
	require.Empty(t, graph.Errors)
	tests := []struct {
		name, from, to, kind string
		status               Status
	}{
		{"unrelated direct target", "Run", "Register", "forbid_call", Pass},
		{"compatible method", "Run", "(Failure).Error", "forbid_call", Unknown},
		{"transitive remains uncertain", "Run", "Register", "forbid_path", Unknown},
		{"callback remains uncertain", "Callback", "Register", "forbid_call", Unknown},
		{"generic receiver remains uncertain", "Dispatch", "(Generic[T]).Value", "forbid_call", Unknown},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			rule := Rule{ID: test.name, From: fmt.Sprint("example.com/review.", test.from), To: fmt.Sprint("example.com/review.", test.to), Kind: test.kind}
			result, subErr := Evaluate(context.Background(), Request{Rules: []Rule{rule}}, graph)
			require.NoError(t, subErr)
			require.Len(t, result.Findings, 1)
			finding := result.Findings[0]
			assert.Equal(t, test.status, finding.Status)
			if test.status == Pass {
				assert.Nil(t, finding.Review)
				assert.Empty(t, finding.Gaps)
				return
			}
			require.NotNil(t, finding.Review)
			assert.Equal(t, "review_needed", finding.Review.Kind)
			assert.Equal(t, rule, finding.Review.Requirement)
			assert.Equal(t, "app.go", finding.Review.Caller.Location.File)
			assert.NotEmpty(t, finding.Review.Guidance)
			require.NotEmpty(t, finding.Gaps)
			assert.Equal(t, "app.go", finding.Gaps[0].Location.File)
		})
	}
}

func TestBlockedReviewRetainsDiagnostics(t *testing.T) {
	t.Parallel()
	graph := analysis.New()
	graph.Errors = []string{"package example.com/broken could not load"}
	rule := Rule{ID: "calls", From: "example.Run", To: "example.Save", Kind: "forbid_call"}
	result, err := Evaluate(context.Background(), Request{Rules: []Rule{rule}}, graph)
	require.NoError(t, err)
	require.Len(t, result.Findings, 1)
	finding := result.Findings[0]
	assert.Equal(t, Unknown, finding.Status)
	require.NotNil(t, finding.Review)
	assert.Equal(t, "analysis_blocked", finding.Review.Kind)
	assert.Equal(t, graph.Errors, finding.Review.Diagnostics)
}
