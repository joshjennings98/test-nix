package analysis

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/ARM-software/golang-utils/utils/field"
	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBuildSelection(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example/app\ngo 1.26\n"), 0600))
	path := filepath.Join(root, "app.go")
	require.NoError(t, filesystem.WriteFile(path, []byte("package app\nfunc A() int { return 1 }\nfunc B() int { return A() }\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "extra.go"), []byte("//go:build extra\n\npackage app\nfunc Extra() {}\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "app_test.go"), []byte("package app\nfunc TestOnly() {}\n"), 0600))
	opts := Options{Root: root, CGOEnabled: field.ToOptional(false)}
	before, err := Load(context.Background(), opts)
	require.NoError(t, err)
	require.Empty(t, before.Errors)
	assert.NotContains(t, before.Nodes, "example/app.Extra")
	assert.NotContains(t, before.Nodes, "example/app.TestOnly")
	assert.Equal(t, []string{"example/app.B", "example/app.A"}, before.Path("example/app.B", "example/app.A", false))

	opts.Tags = []string{"extra"}
	tagged, err := Load(context.Background(), opts)
	require.NoError(t, err)
	require.Empty(t, tagged.Errors)
	assert.Contains(t, tagged.Nodes, "example/app.Extra")

	require.NoError(t, filesystem.WriteFile(path, []byte("package app\nfunc Broken(\n"), 0600))
	broken, err := Load(context.Background(), opts)
	require.NoError(t, err)
	assert.NotEmpty(t, broken.Errors)
}
