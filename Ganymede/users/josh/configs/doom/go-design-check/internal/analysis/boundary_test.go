package analysis

import (
	"context"
	"path/filepath"
	"slices"
	"testing"

	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDependencyTerminalsAndDispatch(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example.com/boundary\ngo 1.26\n"), 0600))
	source := `package boundary
import ("strings"; "sort")
func Trim(s string) string { return strings.TrimSpace(s) }
func Target() {}
func Known() { f := Target; f() }
func Unknown(f func()) { f() }
type Runner interface { Run() }
type Worker struct{}
func (Worker) Run() {}
func Dispatch(r Runner) { r.Run() }
func Invoke() { Dispatch(Worker{}) }
func Sort(items []int) { sort.Slice(items, func(i, j int) bool { return items[i] < items[j] }) }
`
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "boundary.go"), []byte(source), 0600))
	g, err := Load(context.Background(), Options{Root: root})
	require.NoError(t, err)
	require.Empty(t, g.Errors)
	assert.True(t, g.Nodes["strings.TrimSpace"].External)
	assert.NotEmpty(t, g.Path("example.com/boundary.Trim", "strings.TrimSpace", false))
	assert.False(t, g.RelevantGap("example.com/boundary.Trim"))
	for _, edge := range g.Edges {
		assert.False(t, g.Nodes[edge.From].External, "external body leaked: %s", edge.From)
	}
	assert.NotEmpty(t, g.Path("example.com/boundary.Known", "example.com/boundary.Target", false))
	assert.False(t, g.RelationshipGap("example.com/boundary.Known", "direct_call"))
	assert.True(t, g.RelationshipGap("example.com/boundary.Unknown", "direct_call"))
	assert.True(t, g.RelationshipGap("example.com/boundary.Dispatch", "direct_call"))
	assert.True(t, slices.ContainsFunc(g.Edges, func(edge Edge) bool {
		return edge.From == "example.com/boundary.Dispatch" && edge.To == "example.com/boundary.(Worker).Run" && edge.Kind == "possible_call"
	}))
	assert.True(t, g.RelationshipGap("example.com/boundary.Sort", "direct_call"), "external callback invocation must remain unassessed")
}
