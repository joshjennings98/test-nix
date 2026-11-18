package plan

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/ARM-software/golang-utils/utils/field"
	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go-design-check/internal/analysis"
	"go-design-check/internal/check"
)

func TestDocumentValidityIsSeparateFromImplementation(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example/app\ngo 1.26\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "app.go"), []byte("package app\nfunc Start() { Save() }\nfunc Save() {}\ntype Record struct { ID string }\n"), 0600))
	baseline, err := analysis.Load(context.Background(), analysis.Options{Root: root})
	require.NoError(t, err)
	require.Empty(t, baseline.Errors)

	declaration := Declaration{Symbol: "example/app.Validate", Kind: "function", Change: "add", After: field.ToOptional("func(value Record) error")}
	document := Document{Graphs: []Graph{
		{ID: "declarations", Declarations: []Declaration{declaration}},
		{ID: "calls", Roots: []Node{{Symbol: "example/app.Start", Children: []Node{
			{Symbol: "example/app.Validate", Relation: "direct_call", Change: "add"},
			{Symbol: "example/app.Save", Relation: "direct_call"},
		}}}},
	}}
	result, err := Validate(context.Background(), document, baseline)
	require.NoError(t, err)
	require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)
	require.Len(t, result.Requests["calls"].Rules, 1, "context does not become a requirement")
	assert.Equal(t, "func(value example/app.Record) error", result.Requests["declarations"].Rules[0].Signature)
	checked, err := check.Evaluate(context.Background(), result.Requests["calls"], baseline)
	require.NoError(t, err)
	assert.Equal(t, check.Fail, checked.Status, "valid additions are not implemented yet")

	tests := []struct {
		name string
		doc  Document
	}{
		{"missing proposed declaration", Document{Graphs: []Graph{document.Graphs[1]}}},
		{"unknown signature type", Document{Graphs: []Graph{{ID: "x", Declarations: []Declaration{{Symbol: "example/app.New", Kind: "function", Change: "add", After: field.ToOptional("func(UnknownType)")}}}}}},
		{"function body in signature", Document{Graphs: []Graph{{ID: "x", Declarations: []Declaration{{Symbol: "example/app.New", Kind: "function", Change: "add", After: field.ToOptional("func() {}")}}}}}},
		{"existing addition", Document{Graphs: []Graph{{ID: "x", Declarations: []Declaration{{Symbol: "example/app.Save", Kind: "function", Change: "add", After: field.ToOptional("func()")}}}}}},
		{"invented existing edge", Document{Graphs: []Graph{{ID: "x", Roots: []Node{{Symbol: "example/app.Save", Children: []Node{{Symbol: "example/app.Start", Relation: "direct_call"}}}}}}}},
		{"type cannot be called", Document{Graphs: []Graph{{ID: "x", Roots: []Node{{Symbol: "example/app.Start", Children: []Node{{Symbol: "example/app.Record", Relation: "direct_call", Change: "add"}}}}}}}},
		{"duplicate declaration across blocks", Document{Graphs: []Graph{document.Graphs[0], {ID: "another", Declarations: []Declaration{declaration}}}}},
		{"duplicate block IDs", Document{Graphs: []Graph{document.Graphs[0], document.Graphs[0]}}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			result, err := Validate(context.Background(), test.doc, baseline)
			require.NoError(t, err)
			assert.Equal(t, check.Error, result.Status, "%+v", result.Findings)
		})
	}

	t.Run("preserve and remove conflict", func(t *testing.T) {
		result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "x", Roots: []Node{
			{Symbol: "example/app.Start", Children: []Node{
				{Symbol: "example/app.Save", Relation: "direct_call", Change: "preserve"},
				{Symbol: "example/app.Save", Relation: "direct_call", Change: "remove"},
			}},
		}}}}, baseline)
		require.NoError(t, err)
		assert.Equal(t, check.Error, result.Status)
	})

	t.Run("member context", func(t *testing.T) {
		result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "x", Roots: []Node{
			{Symbol: "example/app.Record", Children: []Node{{Symbol: "example/app.(Record).ID", Relation: "member"}}},
		}}}}, baseline)
		require.NoError(t, err)
		assert.Equal(t, check.Pass, result.Status)
		assert.Empty(t, result.Requests["x"].Rules)
	})

	t.Run("canonical field proposal matches implementation", func(t *testing.T) {
		result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "field", Declarations: []Declaration{
			{Symbol: "example/app.(Record).Count", Kind: "field", Change: "add", After: field.ToOptional("int")},
		}}}}, baseline)
		require.NoError(t, err)
		require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)

		implemented := t.TempDir()
		require.NoError(t, filesystem.WriteFile(filepath.Join(implemented, "go.mod"), []byte("module example/app\ngo 1.26\n"), 0600))
		require.NoError(t, filesystem.WriteFile(filepath.Join(implemented, "app.go"), []byte("package app\ntype Record struct { ID string; Count int }\n"), 0600))
		graph, err := analysis.Load(context.Background(), analysis.Options{Root: implemented})
		require.NoError(t, err)
		require.Empty(t, graph.Errors)
		checked, err := check.Evaluate(context.Background(), result.Requests["field"], graph)
		require.NoError(t, err)
		assert.Equal(t, check.Pass, checked.Status)
	})
}
