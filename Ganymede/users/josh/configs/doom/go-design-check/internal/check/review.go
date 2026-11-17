package check

import (
	"slices"
	"strings"

	"go-design-check/internal/analysis"
)

func reviewContext(graph *analysis.Graph, rule Rule, gaps []analysis.Gap) *ReviewContext {
	context := &ReviewContext{Kind: "review_needed", Requirement: rule,
		Caller: graph.Nodes[rule.From], Target: graph.Nodes[rule.To]}
	if len(graph.Errors) > 0 {
		context.Kind = "analysis_blocked"
		context.Diagnostics = slices.Clone(graph.Errors)
		context.Guidance = []string{"Resolve the package-loading or analysis diagnostics and rerun the check. Agent judgement cannot repair missing analysis evidence."}
		return context
	}

	for _, gap := range gaps {
		guidance := "Inspect the unavailable implementation or call target; record the evidence and limits of your assessment."
		switch {
		case gap.Method != "":
			guidance = "Inspect the receiver's construction and assignments at this call site. Determine whether an implementation relevant to the prohibited or required target can reach it. Compatible candidates are not proof of execution."
		case strings.Contains(gap.Reason, "callback"), strings.Contains(gap.Reason, "function value"):
			guidance = "Inspect how the function value is supplied and invoked; record any remaining uncertainty about its target."
		case strings.Contains(gap.Reason, "reflection"):
			guidance = "Inspect the reflected operation and whether it can affect this particular requirement."
		}
		if !slices.Contains(context.Guidance, guidance) {
			context.Guidance = append(context.Guidance, guidance)
		}
	}

	for _, edge := range graph.Edges {
		if edge.Kind != "possible_call" {
			continue
		}
		relevant := edge.From == rule.From && edge.To == rule.To
		for _, gap := range gaps {
			relevant = relevant || (edge.From == gap.From && edge.Location == gap.Location)
		}
		if !relevant {
			continue
		}
		node := graph.Nodes[edge.To]
		node.ID = edge.To
		if !slices.ContainsFunc(context.Candidates, func(candidate analysis.Node) bool { return candidate.ID == node.ID }) {
			context.Candidates = append(context.Candidates, node)
		}
	}
	slices.SortFunc(context.Candidates, func(a, b analysis.Node) int { return strings.Compare(a.ID, b.ID) })
	if len(context.Guidance) == 0 {
		context.Guidance = []string{"Inspect the possible targets and source evidence for this requirement; possible dispatch is not proof of a call."}
	}
	if rule.Kind == "reaches" || rule.Kind == "forbid_path" {
		context.Guidance = append(context.Guidance, "This is a transitive relationship. A method with a different signature may still call the target indirectly.")
	}
	return context
}
