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

func TestImportedInterfaceConformance(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example/probe\ngo 1.26\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "app.go"), []byte(`package probe
import "io"
type Value struct{}
func (Value) Read(p []byte)(int,error){ return 0,nil }
type Pointer struct{}
func (*Pointer) Read(p []byte)(int,error){ return 0,nil }
type Neither struct{}
var _ io.Reader = Value{}
var _ io.Reader = (*Pointer)(nil)
`), 0600))
	graph, err := analysis.Load(context.Background(), analysis.Options{Root: root})
	require.NoError(t, err)
	require.Empty(t, graph.Errors)
	assert.True(t, graph.Nodes["io.Reader"].External)
	tests := []struct {
		from   string
		kind   string
		to     string
		status Status
	}{
		{"example/probe.Value", "implements", "io.Reader", Pass},
		{"example/probe.Value", "forbid_implements", "io.Reader", Fail},
		{"example/probe.Pointer", "implements", "io.Reader", Fail},
		{"example/probe.Pointer", "forbid_implements", "io.Reader", Pass},
		{"*example/probe.Pointer", "implements", "io.Reader", Pass},
		{"*example/probe.Pointer", "forbid_implements", "io.Reader", Fail},
		{"example/probe.Neither", "forbid_implements", "io.Reader", Pass},
		{"example/probe.Value", "forbid_implements", "io.ReadCloser", Pass},
	}
	for _, test := range tests {
		t.Run(fmt.Sprintf("%s %s %s", test.from, test.kind, test.to), func(t *testing.T) {
			t.Parallel()
			result, err := Evaluate(context.Background(), Request{Rules: []Rule{{ID: "interface", Kind: test.kind, From: test.from, To: test.to}}}, graph)
			require.NoError(t, err)
			assert.Equal(t, test.status, result.Status, "%+v", result.Findings)
		})
	}
}
