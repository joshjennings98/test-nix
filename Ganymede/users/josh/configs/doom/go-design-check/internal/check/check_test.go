package check

import (
	"context"
	"testing"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
	"github.com/ARM-software/golang-utils/utils/commonerrors/errortest"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go-design-check/internal/analysis"
)

func TestRules(t *testing.T) {
	t.Parallel()

	graph := analysis.New()
	for _, id := range []string{"example/app.Start", "example/app.Validate", "example/app.Save", "example/app.Dispatch", "example/app.Unknown", "example/app.Worker", "example/app.Runner"} {
		graph.Nodes[id] = analysis.Node{ID: id, Signature: "func()", Location: analysis.Location{File: "app.go", Line: 2}}
	}

	graph.Nodes["external.Call"] = analysis.Node{ID: "external.Call", External: true}
	graph.Edges = []analysis.Edge{
		{From: "example/app.Start", To: "example/app.Validate", Kind: "direct_call", Location: analysis.Location{File: "app.go", Line: 3}},
		{From: "example/app.Validate", To: "example/app.Save", Kind: "direct_call"},
		{From: "example/app.Dispatch", To: "example/app.Save", Kind: "possible_call"},
		{From: "*example/app.Worker", To: "example/app.Runner", Kind: "implements"},
	}
	graph.Gaps = []analysis.Gap{{From: "example/app.Unknown", Reason: "unresolved callback"}}

	tests := []struct {
		name   string
		rule   Rule
		status Status
	}{
		{"direct", Rule{Kind: "direct_call", From: "example/app.Start", To: "example/app.Validate"}, Pass},
		{"indirect is not direct", Rule{Kind: "direct_call", From: "example/app.Start", To: "example/app.Save"}, Fail},
		{"reachable", Rule{Kind: "reaches", From: "example/app.Start", To: "example/app.Save"}, Pass},
		{"forbidden direct", Rule{Kind: "forbid_call", From: "example/app.Start", To: "example/app.Validate"}, Fail},
		{"forbidden indirect", Rule{Kind: "forbid_path", From: "example/app.Start", To: "example/app.Save"}, Fail},
		{"absent direct", Rule{Kind: "forbid_call", From: "example/app.Start", To: "example/app.Save"}, Pass},
		{"possible required", Rule{Kind: "direct_call", From: "example/app.Dispatch", To: "example/app.Save"}, Unknown},
		{"possible prohibited", Rule{Kind: "forbid_call", From: "example/app.Dispatch", To: "example/app.Save"}, Unknown},
		{"unresolved prohibited", Rule{Kind: "forbid_path", From: "example/app.Unknown", To: "example/app.Save"}, Unknown},
		{"missing caller", Rule{Kind: "forbid_path", From: "example/app.Missing", To: "example/app.Save"}, Fail},
		{"dependency body", Rule{Kind: "forbid_path", From: "external.Call", To: "example/app.Save"}, Unknown},
		{"implements pointer", Rule{Kind: "implements", From: "*example/app.Worker", To: "example/app.Runner"}, Pass},
		{"value does not implement", Rule{Kind: "implements", From: "example/app.Worker", To: "example/app.Runner"}, Fail},
		{"exists", Rule{Kind: "exists", Symbol: "example/app.Start"}, Pass},
		{"absent", Rule{Kind: "absent", Symbol: "example/app.Missing"}, Pass},
		{"still exists", Rule{Kind: "absent", Symbol: "example/app.Start"}, Fail},
		{"signature", Rule{Kind: "signature", Symbol: "example/app.Start", Signature: "func()"}, Pass},
		{"signature mismatch", Rule{Kind: "signature", Symbol: "example/app.Start", Signature: "func() error"}, Fail},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			rule := test.rule
			rule.ID = "requirement"
			result, err := Evaluate(context.Background(), Request{Rules: []Rule{rule}}, graph)
			require.NoError(t, err)
			require.Len(t, result.Findings, 1)
			assert.Equal(t, test.status, result.Status)
			assert.Equal(t, test.status, result.Findings[0].Status)
		})
	}
}

func TestIncompleteEvidence(t *testing.T) {
	t.Parallel()
	graph := analysis.New()
	graph.Errors = []string{"package could not be loaded"}
	result, err := Evaluate(context.Background(), Request{Rules: []Rule{{ID: "removed", Kind: "absent", Symbol: "app.Old"}}}, graph)
	require.NoError(t, err)
	assert.Equal(t, Unknown, result.Status)
	assert.Equal(t, graph.Errors, result.Errors)
}

func TestValidation(t *testing.T) {
	t.Parallel()
	tests := []Request{
		{},
		{Rules: []Rule{{Kind: "exists", Symbol: "app.A"}}},
		{Rules: []Rule{{ID: "x", Kind: "unknown"}}},
		{Rules: []Rule{{ID: "x", Kind: "exists", Symbol: "app.A"}, {ID: "x", Kind: "exists", Symbol: "app.B"}}},
		{Rules: []Rule{{ID: "x", Kind: "all_paths_via", From: "a", To: "b"}}},
		{Rules: []Rule{{ID: "x", Kind: "require_package_dep", From: "a", To: "b"}}},
		{Rules: []Rule{{ID: "x", Kind: "forbid_package_dep", From: "a", To: "b"}}},
		{Rules: []Rule{{ID: "x", Kind: "signature", Symbol: "a"}}},
	}

	for _, request := range tests {
		errortest.AssertError(t, request.Validate(), commonerrors.ErrInvalid)
	}
}

func TestCancellation(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := Evaluate(ctx, Request{}, analysis.New())
	require.Error(t, err)
}
