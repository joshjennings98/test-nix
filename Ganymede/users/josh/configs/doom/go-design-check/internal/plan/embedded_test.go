package plan

import (
	"context"
	"fmt"
	"testing"

	"github.com/ARM-software/golang-utils/utils/field"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go-design-check/internal/check"
)

func TestFieldProposals(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		before    string
		after     string
		symbol    string
		change    string
		signature *string
	}{
		{"preserve named layout", "type S struct{ A byte; B int; C byte }", "type S struct{ A byte; B int; C byte }", "A", "preserve", nil},
		{"preserve grouped first", "type S struct{ A,B,C byte; Tail int }", "type S struct{ A,B,C byte; Tail int }", "A", "preserve", nil},
		{"preserve grouped middle", "type S struct{ A,B,C byte; Tail int }", "type S struct{ A,B,C byte; Tail int }", "B", "preserve", nil},
		{"preserve grouped last", "type S struct{ A,B,C byte; Tail int }", "type S struct{ A,B,C byte; Tail int }", "C", "preserve", nil},
		{"modify grouped middle", "type S struct{ A,B,C byte; Tail int }", "type S struct{ A byte; B int; C byte; Tail int }", "B", "modify", field.ToOptional("int")},
		{"remove grouped middle", "type S struct{ A,B,C byte; Tail int }", "type S struct{ A,C byte; Tail int }", "B", "remove", nil},
		{"preserve value and order", "type E struct{ N int }; type S struct{ E; Tail byte }", "type E struct{ N int }; type S struct{ E; Tail byte }", "E", "preserve", nil},
		{"preserve pointer", "type E struct{ N int }; type S struct{ *E; Tail byte }", "type E struct{ N int }; type S struct{ *E; Tail byte }", "E", "preserve", nil},
		{"preserve generic", "type E[T any] struct{ N T }; type S struct{ E[int]; Tail byte }", "type E[T any] struct{ N T }; type S struct{ E[int]; Tail byte }", "E", "preserve", nil},
		{"preserve qualified", "type S struct{ context.Context; Tail byte }", "type S struct{ context.Context; Tail byte }", "Context", "preserve", nil},
		{"modify to pointer", "type E struct{ N int }; type S struct{ E; Tail byte }", "type E struct{ N int }; type S struct{ *E; Tail byte }", "E", "modify", field.ToOptional("*E")},
		{"modify to named field", "type E struct{ N int }; type S struct{ E; Tail byte }", "type E struct{ N int }; type S struct{ E byte; Tail byte }", "E", "modify", field.ToOptional("byte")},
		{"remove value", "type E struct{ N int }; type S struct{ E }", "type E struct{ N int }; type S struct{}", "E", "remove", nil},
		{"remove pointer", "type E struct{ N int }; type S struct{ *E }", "type E struct{ N int }; type S struct{}", "E", "remove", nil},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			baseline := loadProposalFixture(t, fmt.Sprintf("import (\"unsafe\"; \"context\"); var _ context.Context; var _ = unsafe.Sizeof(0); %s", test.before))
			declarations := []Declaration{
				{Symbol: fmt.Sprintf("example/probe.(S).%s", test.symbol), Kind: "field", Change: test.change, After: test.signature},
				{Symbol: "example/probe.Buf", Kind: "variable", Change: "add", After: field.ToOptional("[unsafe.Sizeof(S{})]byte"), Imports: map[string]string{"unsafe": "unsafe"}},
			}
			if test.change == "preserve" {
				declarations = append(declarations, Declaration{Symbol: "example/probe.S", Kind: "type", Change: "preserve"})
			}
			document := Document{Graphs: []Graph{{ID: "proposal", Declarations: declarations}}}
			result, err := Validate(context.Background(), document, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)
			repeated, err := Validate(context.Background(), document, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, repeated.Status, "%+v", repeated.Findings)
			implemented := loadProposalFixture(t, fmt.Sprintf("import (\"unsafe\"; \"context\"); var _ context.Context; %s; var Buf [unsafe.Sizeof(S{})]byte", test.after))
			checked, err := check.Evaluate(context.Background(), result.Requests["proposal"], implemented)
			require.NoError(t, err)
			assert.Equal(t, check.Pass, checked.Status, "%+v", checked.Findings)
		})
	}
}

func TestRemoveGroupedInitialisers(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		before  string
		removed []string
	}{
		{"independent specs", "func obsolete() int { return 1 }; var (A=obsolete(); B=1)", []string{"A"}},
		{"independent expressions", "func obsolete() int { return 1 }; var A,B=obsolete(),1", []string{"A"}},
		{"whole tuple", "func obsolete()(int,int) { return 1,2 }; var (A,C=obsolete(); B=1)", []string{"A", "C"}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			baseline := loadProposalFixture(t, test.before)
			declarations := []Declaration{{Symbol: "example/probe.obsolete", Kind: "function", Change: "remove"}}
			for _, name := range test.removed {
				declarations = append(declarations, Declaration{Symbol: fmt.Sprintf("example/probe.%s", name), Kind: "variable", Change: "remove"})
			}
			result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "proposal", Declarations: declarations}}}, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)
			implemented := loadProposalFixture(t, "var B=1")
			checked, err := check.Evaluate(context.Background(), result.Requests["proposal"], implemented)
			require.NoError(t, err)
			assert.Equal(t, check.Pass, checked.Status, "%+v", checked.Findings)
		})
	}
}

func TestRetainedTupleStillRequiresItsInitialiser(t *testing.T) {
	t.Parallel()
	baseline := loadProposalFixture(t, "func pair()(int,int) { return 1,2 }; var A,B=pair()")
	result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "proposal", Declarations: []Declaration{
		{Symbol: "example/probe.A", Kind: "variable", Change: "remove"},
		{Symbol: "example/probe.pair", Kind: "function", Change: "remove"},
	}}}}, baseline)
	require.NoError(t, err)
	assert.Equal(t, check.Error, result.Status, "B still depends on pair")
}
