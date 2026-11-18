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

func TestRemovedConstantDependencies(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		before string
		after  string
	}{
		{"independent typed constant", "type Old int; const (A Old=1; B=2)", "const B=2"},
		{"independent expression", "type Old int; const (A=Old(1); B=2)", "const B=2"},
		{"partial multi-name spec", "type Old int; const (A,B=Old(1),2)", "const B=2"},
		{"inherited multi-name spec", "type Old int; const (X,Y=Old(1),2; A,B)", "const B=2"},
		{"iota position", "type Old int; const (A Old=iota; B=iota; C)", "const (B=1; C=2)"},
		{"inherited iota expression", "type Old int; const (A=iota+3; B; C)", "const (B=4; C=5)"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			baseline := loadProposalFixture(t, test.before)
			declarations := []Declaration{
				{Symbol: "example/probe.Old", Kind: "type", Change: "remove"},
				{Symbol: "example/probe.A", Kind: "constant", Change: "remove"},
				{Symbol: "example/probe.Buf", Kind: "variable", Change: "add", After: field.ToOptional("[B]int")},
			}
			for _, name := range []string{"X", "Y"} {
				symbol := fmt.Sprintf("example/probe.%s", name)
				if _, exists := baseline.Nodes[symbol]; exists {
					declarations = append(declarations, Declaration{Symbol: symbol, Kind: "constant", Change: "remove"})
				}
			}
			document := Document{Graphs: []Graph{{ID: "proposal", Declarations: declarations}}}
			result, err := Validate(context.Background(), document, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)
			repeated, err := Validate(context.Background(), document, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, repeated.Status, "%+v", repeated.Findings)
			implemented := loadProposalFixture(t, fmt.Sprintf("%s; var Buf [B]int", test.after))
			checked, err := check.Evaluate(context.Background(), result.Requests["proposal"], implemented)
			require.NoError(t, err)
			assert.Equal(t, check.Pass, checked.Status, "%+v", checked.Findings)
		})
	}
}

func TestRetainedConstantStillRequiresInheritedType(t *testing.T) {
	t.Parallel()
	baseline := loadProposalFixture(t, "type Old int; const (A Old=1; B)")
	result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "proposal", Declarations: []Declaration{
		{Symbol: "example/probe.Old", Kind: "type", Change: "remove"},
		{Symbol: "example/probe.A", Kind: "constant", Change: "remove"},
	}}}}, baseline)
	require.NoError(t, err)
	assert.Equal(t, check.Error, result.Status, "B still has type Old")
}
