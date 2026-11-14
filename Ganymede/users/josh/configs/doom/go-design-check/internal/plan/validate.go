package plan

import (
	"context"
	"crypto/sha256"
	"fmt"
	"go/token"
	"slices"
	"strings"

	"github.com/ARM-software/golang-utils/utils/field"
	"github.com/ARM-software/golang-utils/utils/parallelisation"

	"go-design-check/internal/analysis"
	"go-design-check/internal/check"
)

func shapeHash(value string) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte(value)))
}

func Validate(ctx context.Context, document Document, baseline *analysis.Graph) (result Result, err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}

	result = Result{Status: check.Pass, Findings: []check.Finding{}, Requests: map[string]check.Request{}}
	if baseline == nil || len(baseline.Errors) > 0 {
		result.Status = check.Unknown
		result.Findings = append(result.Findings, check.Finding{Status: check.Unknown, Message: "baseline analysis is unavailable or incomplete"})
		return
	}

	reject := func(id, message string) {
		result.Status = check.Error
		result.Findings = append(result.Findings, check.Finding{ID: id, Status: check.Error, Message: message})
	}
	declarations := map[string]Declaration{}
	blocks := map[string]bool{}
	var proposal design
	for _, graph := range document.Graphs {
		if strings.TrimSpace(graph.ID) == "" || blocks[graph.ID] {
			reject(graph.ID, "graph IDs must be non-empty and unique")
		}

		blocks[graph.ID] = true
		if len(graph.Roots) == 0 && len(graph.Declarations) == 0 {
			reject(graph.ID, "graph must contain roots or declarations")
		}

		for _, declaration := range graph.Declarations {
			declaration.ID = declaration.Symbol
			pkg, name, receiver := declaration.Parts()
			if pkg == "" || !token.IsIdentifier(name) || name == "_" || name == "init" || ((declaration.Kind == "method" || declaration.Kind == "field") != (receiver != "")) {
				reject(graph.ID, fmt.Sprintf("invalid declaration identity %q", declaration.Symbol))
				continue
			}

			if _, duplicate := declarations[declaration.Symbol]; duplicate {
				reject(graph.ID, fmt.Sprintf("declaration %s is defined more than once", declaration.Symbol))
				continue
			}

			old, exists := baseline.Nodes[declaration.Symbol]
			if !slices.Contains([]string{"add", "modify", "remove", "preserve"}, declaration.Change) || !slices.Contains([]string{"function", "method", "type", "interface", "field", "variable", "constant"}, declaration.Kind) {
				reject(graph.ID, "unsupported declaration change or kind")
				continue
			}

			if (declaration.Change == "add") == exists || (exists && (old.External || old.Kind != declaration.Kind)) {
				reject(graph.ID, fmt.Sprintf("%s %s contradicts the baseline declaration", declaration.Change, declaration.Symbol))
				continue
			}

			if declaration.Change == "remove" {
				if declaration.After != nil {
					reject(graph.ID, "removed declarations must not specify a target signature")
				}
			} else {
				if declaration.Change == "preserve" && declaration.After == nil {
					declaration.After = field.ToOptional(old.Signature)
				}
			}

			declarations[declaration.Symbol] = declaration
			proposal.Declarations = append(proposal.Declarations, declaration)
		}
	}

	if result.Status == check.Error {
		return
	}

	shapes, _, findings := declarationShapes(proposal, baseline)
	for _, finding := range findings {
		result.Findings = append(result.Findings, finding)
		if result.Status != check.Error {
			result.Status = finding.Status
		}
	}

	if result.Status != check.Pass {
		return
	}

	links := map[string]string{}
	for _, graph := range document.Graphs {
		if err = parallelisation.DetermineContextError(ctx); err != nil {
			return
		}

		request := check.Request{Rules: []check.Rule{}}
		for _, authored := range graph.Declarations {
			declaration := declarations[authored.Symbol]
			rule := check.Rule{ID: declaration.Symbol, Symbol: declaration.Symbol, Kind: "signature", Signature: shapes[declaration.Symbol]}
			if declaration.Change == "remove" {
				rule.Kind, rule.Signature = "absent", ""
			} else if declaration.Change == "preserve" && rule.Signature != baseline.Nodes[declaration.Symbol].Signature {
				reject(graph.ID, fmt.Sprintf("preserve changes the signature of %s", declaration.Symbol))
			}

			request.Rules = append(request.Rules, rule)
		}

		var visit func(Node, string, string)
		visit = func(node Node, parent, path string) {
			id := fmt.Sprintf("%s:%s", graph.ID, path)
			name := strings.TrimPrefix(node.Symbol, "*")
			old, exists := baseline.Nodes[name]
			declaration, proposed := declarations[name]
			if !exists && !proposed {
				reject(id, fmt.Sprintf("unknown symbol %s; declare additions explicitly", node.Symbol))
				return
			}

			if !slices.Contains([]string{"", "add", "remove", "preserve"}, node.Change) {
				reject(id, "tree changes must be add, remove, preserve or empty for context")
				return
			}

			if parent == "" {
				if node.Relation != "" {
					reject(id, "root nodes must not specify a relationship")
				}

				if node.Change != "" {
					if node.Change != "preserve" && (!proposed || declaration.Change != node.Change) {
						reject(id, "add/remove roots require a matching declaration")
					} else if node.Change == "preserve" {
						if !exists || (proposed && declaration.Change == "remove") {
							reject(id, "preserved root must exist in baseline and target")
						} else {
							request.Rules = append(request.Rules, check.Rule{ID: id, Kind: "exists", Symbol: name})
						}
					}
				}
			} else {
				if !slices.Contains([]string{"direct_call", "reaches", "implements", "member"}, node.Relation) {
					reject(id, "child nodes require direct_call, reaches, implements or member")
					return
				}

				parentName := strings.TrimPrefix(parent, "*")
				parentDeclaration := declarations[parentName]
				fromKind, toKind := baseline.Nodes[parentName].Kind, old.Kind
				if parentDeclaration.Kind != "" {
					fromKind = parentDeclaration.Kind
				}

				if proposed {
					toKind = declaration.Kind
				}

				callable := func(kind string) bool { return kind == "function" || kind == "method" || kind == "closure" }
				if ((node.Relation == "direct_call" || node.Relation == "reaches") && (!callable(fromKind) || !callable(toKind))) ||
					(node.Relation == "implements" && (fromKind != "type" || toKind != "interface")) ||
					(node.Relation == "member" && ((fromKind != "type" && fromKind != "interface") || (toKind != "field" && toKind != "method"))) {
					reject(id, "relationship does not match its declaration kinds")
					return
				}
				if node.Change == "add" || node.Change == "preserve" {
					if declaration.Change == "remove" || parentDeclaration.Change == "remove" {
						reject(id, "retained relationship references a removed declaration")
					}
				}

				kind := node.Relation
				negative := map[string]string{"direct_call": "forbid_call", "reaches": "forbid_path", "implements": "forbid_implements", "member": "forbid_member"}[kind]
				precondition := check.Rule{ID: id, Kind: kind, From: parent, To: node.Symbol}
				if node.Change == "add" {
					precondition.Kind = negative
				}

				newEndpoint := declaration.Change == "add" || parentDeclaration.Change == "add"
				if newEndpoint && node.Change != "add" {
					reject(id, "relationships involving new declarations must be marked add")
				} else if !newEndpoint {
					checked, subErr := check.Evaluate(ctx, check.Request{Rules: []check.Rule{precondition}}, baseline)
					if subErr != nil {
						reject(id, subErr.Error())
					} else if checked.Status != check.Pass {
						finding := checked.Findings[0]
						if finding.Status == check.Fail {
							finding.Status = check.Error
						}

						result.Findings = append(result.Findings, finding)
						if result.Status != check.Error {
							result.Status = finding.Status
						}
					}
				}

				if node.Change != "" {
					key := fmt.Sprintf("%s|%s|%s", parent, kind, node.Symbol)
					if previous, seen := links[key]; seen && previous != node.Change {
						reject(id, "contradictory changes for the same relationship")
					}

					links[key] = node.Change
					if node.Change == "remove" {
						kind = negative
					}

					if node.Change != "remove" || parentDeclaration.Change != "remove" {
						request.Rules = append(request.Rules, check.Rule{ID: id, Kind: kind, From: parent, To: node.Symbol})
					}
				}
			}

			if exists && old.External && len(node.Children) > 0 {
				reject(id, "external dependencies are terminal nodes")
			}

			for i, child := range node.Children {
				visit(child, node.Symbol, fmt.Sprintf("%s.%d", path, i))
			}
		}

		for i, root := range graph.Roots {
			visit(root, "", fmt.Sprint(i))
		}

		result.Requests[graph.ID] = request
	}

	if result.Status != check.Pass {
		result.Requests = nil
	}

	return
}
