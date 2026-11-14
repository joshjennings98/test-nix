package check

import (
	"context"
	"fmt"
	"strings"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
	"github.com/ARM-software/golang-utils/utils/parallelisation"

	"go-design-check/internal/analysis"
)

func (request Request) Validate() (err error) {
	if len(request.Rules) == 0 {
		return commonerrors.Newf(commonerrors.ErrInvalid, "at least one rule is required")
	}

	seen := map[string]bool{}
	for _, rule := range request.Rules {
		if strings.TrimSpace(rule.ID) == "" || seen[rule.ID] {
			return commonerrors.Newf(commonerrors.ErrInvalid, "rule IDs must be non-empty and unique: %q", rule.ID)
		}

		seen[rule.ID] = true
		switch rule.Kind {
		case "exists", "absent", "signature":
			if rule.Symbol == "" || rule.From != "" || rule.To != "" || (rule.Kind == "signature") != (rule.Signature != "") {
				return commonerrors.Newf(commonerrors.ErrInvalid, "rule %q requires a symbol, and only signature rules accept a signature", rule.ID)
			}

		case "direct_call", "reaches", "forbid_call", "forbid_path", "implements", "forbid_implements", "member", "forbid_member":
			if rule.From == "" || rule.To == "" || rule.Symbol != "" || rule.Signature != "" {
				return commonerrors.Newf(commonerrors.ErrInvalid, "rule %q requires from/to", rule.ID)
			}

		default:
			return commonerrors.Newf(commonerrors.ErrInvalid, "unsupported rule kind %q", rule.Kind)
		}
	}

	return
}

func Evaluate(ctx context.Context, request Request, graph *analysis.Graph) (result Result, err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}

	if graph == nil {
		err = commonerrors.UndefinedVariable("graph")
		return
	}

	if err = request.Validate(); err != nil {
		return
	}

	result.Status = Pass
	result.Errors = graph.Errors
	if len(graph.Errors) > 0 {
		result.Status = Unknown
	}

	for _, rule := range request.Rules {
		if err = parallelisation.DetermineContextError(ctx); err != nil {
			return
		}

		finding := evaluateRule(graph, rule)
		result.Findings = append(result.Findings, finding)
		if finding.Status == Fail || (finding.Status == Unknown && result.Status != Fail) {
			result.Status = finding.Status
		}
	}

	return
}

func evaluateRule(graph *analysis.Graph, rule Rule) (finding Finding) {
	finding = Finding{ID: rule.ID, Status: Pass}
	if rule.Symbol != "" {
		return declaration(graph, rule)
	}

	if len(graph.Errors) > 0 {
		finding.Status = Unknown
		finding.Message = "package loading or analysis failed; structural evidence is incomplete"
		return
	}

	from := strings.TrimPrefix(rule.From, "*")
	node, exists := graph.Nodes[from]
	if !exists {
		finding.Status = Fail
		finding.Message = "required source symbol is absent from the analysed scope"
		return
	}

	if node.External {
		finding.Status = Unknown
		finding.Message = "dependency bodies are outside the analysed scope"
		return
	}

	var definite, possible []string
	gap := graph.RelationshipGap(from, rule.Kind)
	switch rule.Kind {
	case "reaches", "forbid_path":
		definite = graph.Path(rule.From, rule.To, false)
		possible = graph.Path(rule.From, rule.To, true)
	default:
		kind := rule.Kind
		switch kind {
		case "forbid_call":
			kind = "direct_call"
		case "forbid_implements":
			kind = "implements"
		case "forbid_member":
			kind = "member"
		}

		for _, edge := range graph.Edges {
			if edge.From != rule.From || edge.To != rule.To {
				continue
			}

			if edge.Kind == kind {
				definite = []string{rule.From, rule.To}
			} else if kind == "direct_call" && edge.Kind == "possible_call" {
				possible = []string{rule.From, rule.To}
			}
		}
	}

	negative := strings.HasPrefix(rule.Kind, "forbid_")
	switch {
	case len(definite) > 0:
		finding.Message, finding.Witness = "required relationship found", definite
		if negative {
			finding.Status, finding.Message = Fail, "prohibited relationship found"
		}
	case len(possible) > 0 || gap:
		finding.Status, finding.Message, finding.Witness = Unknown, "possible or unresolved calls could change the finding", possible
	case negative:
		finding.Message = "prohibited relationship absent in the analysed graph"
	default:
		finding.Status, finding.Message = Fail, "required relationship is absent"
	}

	for i, symbol := range finding.Witness {
		if i == 0 {
			continue
		}

		for _, edge := range graph.Edges {
			if edge.From == finding.Witness[i-1] && edge.To == symbol && edge.Location.File != "" {
				finding.Locations = append(finding.Locations, edge.Location)
				break
			}
		}
	}

	if finding.Status == Unknown {
		for _, item := range graph.Gaps {
			if item.From == from || ((rule.Kind == "reaches" || rule.Kind == "forbid_path") && len(graph.Path(from, item.From, true)) > 0) {
				finding.Gaps = append(finding.Gaps, item)
			}
		}
	}

	return
}

func declaration(graph *analysis.Graph, rule Rule) (finding Finding) {
	finding = Finding{ID: rule.ID, Status: Pass, Message: "declaration matches requirement"}
	if len(graph.Errors) > 0 {
		finding.Status, finding.Message = Unknown, "declaration evidence is incomplete"
		return
	}

	node, exists := graph.Nodes[rule.Symbol]
	if exists {
		finding.Locations = []analysis.Location{node.Location}
	}

	switch {
	case rule.Kind == "absent" && exists:
		finding.Status, finding.Message = Fail, "declaration is still present"
	case rule.Kind != "absent" && !exists:
		finding.Status, finding.Message = Fail, "required declaration is absent"
	case rule.Kind == "signature" && node.Signature != rule.Signature:
		finding.Status, finding.Message = Fail, fmt.Sprintf("observed signature: %s", node.Signature)
	}

	return
}
