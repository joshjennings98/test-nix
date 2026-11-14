package plan

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go-design-check/internal/check"
)

func TestRelationshipIdentities(t *testing.T) {
	t.Parallel()
	baseline := loadProposalFixture(t, `import "io"
func Start(){ Save() }
func Save(){}
type A struct{ X int }
type B struct{}
func (*A) Read(p []byte)(int,error){ return 0,nil }
var _ io.Reader = (*A)(nil)
type Box[T any] struct{}
func (Box[T]) Run(){}
`)
	tests := []struct {
		name     string
		from     string
		to       string
		relation string
		change   string
		status   check.Status
	}{
		{"correct field owner", "example/probe.A", "example/probe.(A).X", "member", "preserve", check.Pass},
		{"correct pointer method owner", "example/probe.A", "example/probe.(*A).Read", "member", "preserve", check.Pass},
		{"correct generic method owner", "example/probe.Box", "example/probe.(Box[T]).Run", "member", "preserve", check.Pass},
		{"pointer implements", "*example/probe.A", "io.Reader", "implements", "preserve", check.Pass},
		{"existing external implementation is not an addition", "*example/probe.A", "io.Reader", "implements", "add", check.Error},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			result, err := Validate(context.Background(), Document{Graphs: []Graph{{ID: "graph", Roots: []Node{
				{Symbol: test.from, Children: []Node{{Symbol: test.to, Relation: test.relation, Change: test.change}}},
			}}}}, baseline)
			require.NoError(t, err)
			require.Equal(t, test.status, result.Status, "%+v", result.Findings)
			if test.status != check.Pass {
				assert.Empty(t, result.Requests)
				return
			}
			checked, err := check.Evaluate(context.Background(), result.Requests["graph"], baseline)
			require.NoError(t, err)
			assert.Equal(t, check.Pass, checked.Status, "%+v", checked.Findings)
		})
	}
}
