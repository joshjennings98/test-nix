package plan

import (
	"context"
	"testing"

	"github.com/ARM-software/golang-utils/utils/field"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go-design-check/internal/check"
)

func TestPreserveConstantValuesAndKinds(t *testing.T) {
	t.Parallel()
	cases := []string{
		"const X = 0.1", "const X float64 = 0.1", "const X float32 = 0.1",
		"const X = complex(0.1,0.2)", "const X complex64 = complex(0.1,-0.2)",
		"const X = 1.0", "const X = 'A'",
		"const X = -0.1", "const X = 1i", "const X = 1.0/3",
		"type Decimal float64; const X Decimal = 0.1",
		"const X = 42", "const X = true", "const X = \"a,b\"",
	}
	for _, source := range cases {
		t.Run(source, func(t *testing.T) {
			t.Parallel()
			baseline := loadProposalFixture(t, source)
			result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "proposal", Declarations: []Declaration{
				{Symbol: "example/probe.X", Kind: "constant", Change: "preserve"},
			}}}}, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)
			checked, err := check.Evaluate(context.Background(), result.Requests["proposal"], baseline)
			require.NoError(t, err)
			assert.Equal(t, check.Pass, checked.Status, "%+v", checked.Findings)
		})
	}
}

func TestProposedConstantValuesAndKinds(t *testing.T) {
	t.Parallel()
	baseline := loadProposalFixture(t, "type Existing int")
	cases := []struct {
		shape          string
		implementation string
	}{
		{"untyped float = 0.1", "const X = 0.1"},
		{"untyped float = -0.1", "const X = -0.1"},
		{"untyped float = 1", "const X = 1.0"},
		{"untyped complex = (0.1 - 0.2i)", "const X = complex(0.1,-0.2)"},
		{"untyped complex = 1", "const X = 1 + 0i"},
		{"untyped rune = 65", "const X = 'A'"},
	}
	for _, test := range cases {
		t.Run(test.shape, func(t *testing.T) {
			t.Parallel()
			result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "proposal", Declarations: []Declaration{
				{Symbol: "example/probe.X", Kind: "constant", Change: "add", After: field.ToOptional(test.shape)},
			}}}}, baseline)
			require.NoError(t, err)
			require.Equal(t, check.Pass, result.Status, "%+v", result.Findings)
			implemented := loadProposalFixture(t, test.implementation)
			checked, err := check.Evaluate(context.Background(), result.Requests["proposal"], implemented)
			require.NoError(t, err)
			assert.Equal(t, check.Pass, checked.Status, "%+v", checked.Findings)
		})
	}
}

func TestRejectMismatchedConstantKinds(t *testing.T) {
	t.Parallel()
	baseline := loadProposalFixture(t, "type Existing int")
	for _, shape := range []string{"untyped rune = 1.5", "untyped int = 1.0", "untyped bool = 1", "untyped float = 1i", "untyped invented = 1"} {
		t.Run(shape, func(t *testing.T) {
			result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "proposal", Declarations: []Declaration{
				{Symbol: "example/probe.X", Kind: "constant", Change: "add", After: field.ToOptional(shape)},
			}}}}, baseline)
			require.NoError(t, err)
			assert.Equal(t, check.Error, result.Status, "%+v", result.Findings)
		})
	}
}
