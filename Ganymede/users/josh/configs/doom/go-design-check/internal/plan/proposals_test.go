package plan

import (
	"context"
	"fmt"
	"path/filepath"
	"testing"

	"github.com/ARM-software/golang-utils/utils/field"
	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go-design-check/internal/analysis"
	"go-design-check/internal/check"
)

func TestGroupedAndMemberProposals(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name         string
		before       string
		declarations []Declaration
		after        string
	}{
		{
			name:   "preserve first iota",
			before: "const (A=iota; B; C)",
			declarations: []Declaration{
				{
					Symbol: "example/probe.A",
					Kind:   "constant",
					Change: "preserve",
				},
			},
			after: "const (A=iota; B; C)",
		},
		{
			name:   "modify middle iota",
			before: "const (A=iota; B; C)",
			declarations: []Declaration{
				{
					Symbol: "example/probe.B",
					Kind:   "constant",
					Change: "modify",
					After:  field.ToOptional("untyped int = 9"),
				},
				{
					Symbol: "example/probe.Values",
					Kind:   "variable",
					Change: "add",
					After:  field.ToOptional("[C]int"),
				},
			},
			after: "const (A=0; B=9; C=2); var Values [C]int",
		},
		{
			name:   "remove first iota",
			before: "const (A=iota; B; C)",
			declarations: []Declaration{
				{
					Symbol: "example/probe.A",
					Kind:   "constant",
					Change: "remove",
				},
				{
					Symbol: "example/probe.Values",
					Kind:   "variable",
					Change: "add",
					After:  field.ToOptional("[C]int"),
				},
			},
			after: "const (B=1; C=2); var Values [C]int",
		},
		{
			name:   "preserve tuple variable",
			before: "func pair()(int,string){return 1,\"two\"}; var A,B=pair()",
			declarations: []Declaration{
				{
					Symbol: "example/probe.A",
					Kind:   "variable",
					Change: "preserve",
				},
			},
			after: "func pair()(int,string){return 1,\"two\"}; var A,B=pair()",
		},
		{
			name:   "modify tuple variable",
			before: "func pair()(int,string){return 1,\"two\"}; var A,B=pair()",
			declarations: []Declaration{
				{
					Symbol: "example/probe.A",
					Kind:   "variable",
					Change: "modify",
					After:  field.ToOptional("int64"),
				},
				{
					Symbol: "example/probe.B",
					Kind:   "variable",
					Change: "preserve",
				},
			},
			after: "var A int64; var B string",
		},
		{
			name:   "remove tuple variable",
			before: "func pair()(int,string){return 1,\"two\"}; var A,B=pair()",
			declarations: []Declaration{
				{
					Symbol: "example/probe.A",
					Kind:   "variable",
					Change: "remove",
				},
			},
			after: "var B string",
		},
		{
			name:   "preserve interface method",
			before: "type I interface { Run() }",
			declarations: []Declaration{
				{
					Symbol: "example/probe.(I).Run",
					Kind:   "method",
					Change: "preserve",
				},
			},
			after: "type I interface { Run() }",
		},
		{
			name:   "modify interface method",
			before: "type I interface { Run() }",
			declarations: []Declaration{
				{
					Symbol: "example/probe.(I).Run",
					Kind:   "method",
					Change: "modify",
					After:  field.ToOptional("func(int) error"),
				},
			},
			after: "type I interface { Run(int) error }",
		},
		{
			name:   "add interface method",
			before: "type I interface { Run() }",
			declarations: []Declaration{
				{
					Symbol: "example/probe.(I).Stop",
					Kind:   "method",
					Change: "add",
					After:  field.ToOptional("func()"),
				},
			},
			after: "type I interface { Run(); Stop() }",
		},
		{
			name:   "remove interface method",
			before: "type I interface { Run(); Stop() }",
			declarations: []Declaration{
				{
					Symbol: "example/probe.(I).Run",
					Kind:   "method",
					Change: "remove",
				},
				{
					Symbol: "example/probe.(I).Stop",
					Kind:   "method",
					Change: "preserve",
				},
			},
			after: "type I interface { Stop() }",
		},
		{
			name:   "new interface before member",
			before: "type Existing int",
			declarations: []Declaration{
				{
					Symbol: "example/probe.(I).Run",
					Kind:   "method",
					Change: "add",
					After:  field.ToOptional("func()"),
				},
				{
					Symbol: "example/probe.I",
					Kind:   "interface",
					Change: "add",
					After:  field.ToOptional("interface{}"),
				},
			},
			after: "type Existing int; type I interface { Run() }",
		},
		{
			name:   "interface member import",
			before: "import _ \"context\"; type I interface{}",
			declarations: []Declaration{
				{
					Symbol:  "example/probe.(I).Run",
					Kind:    "method",
					Change:  "add",
					After:   field.ToOptional("func(ctx.Context)"),
					Imports: map[string]string{"ctx": "context"},
				},
			},
			after: "import \"context\"; type I interface { Run(context.Context) }",
		},
		{
			name:   "interface member different import alias",
			before: "import \"context\"; type I interface { Run(context.Context) }",
			declarations: []Declaration{
				{
					Symbol:  "example/probe.(I).Run",
					Kind:    "method",
					Change:  "modify",
					After:   field.ToOptional("func(ctx.Context) error"),
					Imports: map[string]string{"ctx": "context"},
				},
			},
			after: "import \"context\"; type I interface { Run(context.Context) error }",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			baseline := loadProposalFixture(t, test.before)
			document := Document{Graphs: []Graph{{ID: "proposal", Declarations: test.declarations}}}
			result, err := Validate(context.Background(), document, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)
			// Revalidating the same baseline must not observe mutations from the first run.
			repeated, err := Validate(context.Background(), document, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, repeated.Status, "%+v", repeated.Findings)
			implemented := loadProposalFixture(t, test.after)
			checked, err := check.Evaluate(context.Background(), result.Requests["proposal"], implemented)
			require.NoError(t, err)
			assert.Equal(t, check.Pass, checked.Status, "%+v", checked.Findings)
		})
	}
}

func loadProposalFixture(t *testing.T, source string) *analysis.Graph {
	t.Helper()
	root := t.TempDir()
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example/probe\ngo 1.26\n"), 0600))
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "app.go"), []byte(fmt.Sprintf("package probe\n%s\n", source)), 0600))
	graph, err := analysis.Load(context.Background(), analysis.Options{Root: root})
	require.NoError(t, err)
	require.Empty(t, graph.Errors)
	return graph
}

func TestInvalidInterfaceMemberProposals(t *testing.T) {
	t.Parallel()
	baseline := loadProposalFixture(t, "type I interface { Run() }")
	tests := []Declaration{
		{Symbol: "example/probe.(I).Run", Kind: "method", Change: "preserve", After: field.ToOptional("func(int)")},
		{Symbol: "example/probe.(I).Run", Kind: "method", Change: "modify", After: field.ToOptional("func(Missing)")},
		{Symbol: "example/probe.(*I).Stop", Kind: "method", Change: "add", After: field.ToOptional("func()")},
	}
	for _, declaration := range tests {
		result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "invalid", Declarations: []Declaration{declaration}}}}, baseline)
		require.NoError(t, err)
		assert.Equal(t, check.Error, result.Status, "%+v: %+v", declaration, result.Findings)
	}
}
