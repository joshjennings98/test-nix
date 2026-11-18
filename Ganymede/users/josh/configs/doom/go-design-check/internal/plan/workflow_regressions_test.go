package plan

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go-design-check/internal/analysis"
	"go-design-check/internal/check"
)

func TestGenericMethodCallRequirements(t *testing.T) {
	t.Parallel()
	baseline := loadProposalFixture(t, `
type Box[T any] struct{ Value T }
func (b Box[T]) Get() T { return b.Value }
func (b *Box[T]) Set(value T) { b.Value = value }
func Use() int {
 b := Box[int]{Value: 1}
 b.Set(2)
 return b.Get()
}
`)
	for _, target := range []string{"example/probe.(Box[T]).Get", "example/probe.(*Box[T]).Set"} {
		t.Run(target, func(t *testing.T) {
			t.Parallel()
			result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "calls", Roots: []Node{
				{Symbol: "example/probe.Use", Children: []Node{{Symbol: target, Relation: "direct_call", Change: "preserve"}}},
			}}}}, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)

			checked, err := check.Evaluate(context.Background(), result.Requests["calls"], baseline)
			require.NoError(t, err)
			assert.Equal(t, check.Pass, checked.Status, "%+v", checked.Findings)

			forbidden, err := check.Evaluate(context.Background(), check.Request{Rules: []check.Rule{
				{ID: "forbidden", Kind: "forbid_call", From: "example/probe.Use", To: target},
			}}, baseline)
			require.NoError(t, err)
			assert.Equal(t, check.Fail, forbidden.Status, "%+v", forbidden.Findings)
		})
	}
}

func TestPreserveImportedDeclarationsWithoutImportMap(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	require.NoError(t, filesystem.MkDir(filepath.Join(root, "model")))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example/probe\ngo 1.26\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "model", "model.go"), []byte("package model\ntype Item struct{ ID string }\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "app.go"), []byte(`package probe
import (
 data "example/probe/model"
 "net/http"
)
func Save(item data.Item) {}
func Handle(req *http.Request) {}
type Record struct { Item data.Item }
`), 0600))
	baseline, err := analysis.Load(context.Background(), analysis.Options{Root: root})
	require.NoError(t, err)
	require.Empty(t, baseline.Errors)

	for _, declaration := range []Declaration{
		{Symbol: "example/probe.Save", Kind: "function", Change: "preserve"},
		{Symbol: "example/probe.Handle", Kind: "function", Change: "preserve"},
		{Symbol: "example/probe.(Record).Item", Kind: "field", Change: "preserve"},
	} {
		t.Run(declaration.Symbol, func(t *testing.T) {
			t.Parallel()
			result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "keep", Declarations: []Declaration{declaration}}}}, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)

			checked, err := check.Evaluate(context.Background(), result.Requests["keep"], baseline)
			require.NoError(t, err)
			assert.Equal(t, check.Pass, checked.Status, "%+v", checked.Findings)
		})
	}
}
