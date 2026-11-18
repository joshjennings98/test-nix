package analysis

import (
	"context"
	"fmt"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/ARM-software/golang-utils/utils/field"
	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestInheritedBuildSettingsAndOverrides(t *testing.T) {
	t.Setenv("GOOS", "invalid-parent-os")
	t.Setenv("GOARCH", "invalid-parent-architecture")
	t.Setenv("CGO_ENABLED", "1")
	t.Setenv("GOPACKAGESDRIVER", filepath.Join(t.TempDir(), "missing-driver"))
	t.Setenv("GOFLAGS", "-tags=inherited")

	root := t.TempDir()
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example/env\ngo 1.26\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "base.go"), []byte("package env\nfunc Base() {}\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "tagged.go"), []byte("//go:build inherited\n\npackage env\nfunc Tagged() {}\n"), 0600))

	require.NoError(t, filesystem.WriteFile(filepath.Join(root, fmt.Sprintf("host_%s_%s.go", runtime.GOOS, runtime.GOARCH)), []byte("package env\nfunc Host() {}\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "cgo.go"), []byte("//go:build cgo\n\npackage env\nfunc WithCGO() {}\n"), 0600))

	tests := []struct {
		name     string
		override *bool
		expected bool
	}{
		{name: "inherit CGO", expected: true},
		{name: "override CGO", override: field.ToOptional(false), expected: false},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			graph, err := Load(context.Background(), Options{Root: root, CGOEnabled: test.override})
			require.NoError(t, err)
			require.Empty(t, graph.Errors)
			assert.Contains(t, graph.Nodes, "example/env.Tagged")
			assert.Contains(t, graph.Nodes, "example/env.Host")
			_, hasCGO := graph.Nodes["example/env.WithCGO"]
			assert.Equal(t, test.expected, hasCGO)
		})
	}
}
