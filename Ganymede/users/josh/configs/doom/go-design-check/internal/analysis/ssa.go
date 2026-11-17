package analysis

import (
	"context"
	"fmt"
	"go/types"
	"maps"
	"slices"
	"strings"

	"github.com/ARM-software/golang-utils/utils/parallelisation"
	"golang.org/x/tools/go/callgraph/vta"
	"golang.org/x/tools/go/packages"
	"golang.org/x/tools/go/ssa"
	"golang.org/x/tools/go/ssa/ssautil"
)

// addSSA resolves function values and closures while preserving possible dispatch.
// An analyser panic becomes an explicit gap, never a successful absence check.
func addSSA(ctx context.Context, g *Graph, roots []*packages.Package, root string) (err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}

	defer func() {
		if recovered := recover(); recovered != nil {
			g.Errors = append(g.Errors, fmt.Sprintf("SSA analysis unavailable: %v", recovered))
		}
	}()
	if len(g.Errors) > 0 {
		return
	}

	program, _ := ssautil.AllPackages(roots, ssa.InstantiateGenerics)
	program.Build()
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}

	funcs := ssautil.AllFunctions(program)
	calls := vta.CallGraph(funcs, nil)
	functions := slices.SortedFunc(maps.Keys(calls.Nodes), func(a, b *ssa.Function) int {
		return strings.Compare(fmt.Sprintf("%s:%d", ssaID(a), a.Pos()), fmt.Sprintf("%s:%d", ssaID(b), b.Pos()))
	})

	for _, fn := range functions {
		node := calls.Nodes[fn]
		if err = parallelisation.DetermineContextError(ctx); err != nil {
			return
		}

		from := ssaID(fn)
		if from == "" {
			continue
		}

		if g.Nodes[from].External {
			continue
		}

		if _, exists := g.Nodes[from]; !exists {
			if fn.Parent() == nil {
				continue
			}

			ancestor := fn.Parent()
			for ancestor.Parent() != nil {
				ancestor = ancestor.Parent()
			}

			parent := ssaID(ancestor)
			parentNode, ok := g.Nodes[parent]
			if !ok || parentNode.External {
				continue
			}

			parentNode.ID = from
			parentNode.Kind = "closure"
			parentNode.Location = location(program.Fset, fn.Pos(), root)
			g.Nodes[from] = parentNode
		}

		// Inspect instructions as well as graph edges: unresolved calls may
		// have no edge, and closure bodies bypass the AST uncertainty checks.
		for _, block := range fn.Blocks {
			for _, instruction := range block.Instrs {
				call, ok := instruction.(ssa.CallInstruction)
				if !ok {
					continue
				}

				if _, builtin := call.Common().Value.(*ssa.Builtin); builtin {
					continue
				}

				loc := location(program.Fset, call.Common().Pos(), root)
				callee := call.Common().StaticCallee()
				if callee == nil {
					if call.Common().IsInvoke() {
						g.Gaps = append(g.Gaps, interfaceGap(from, "interface dispatch has conservative candidate targets", call.Common().Method, loc))
					} else {
						g.Gaps = append(g.Gaps, Gap{From: from, Reason: "unresolved function value or callback", Location: loc})
					}
					continue
				}

				if callee.Pkg == nil {
					continue
				}

				pkg := callee.Pkg.Pkg.Path()
				if pkg == "reflect" || pkg == "unsafe" {
					g.Gaps = append(g.Gaps, Gap{From: from, Reason: "reflection or unsafe operation", Location: loc})
				}

				dependency := g.SourcePackages[pkg]
				if dependency != nil && dependency.Module != nil && dependency.Module.Main {
					continue
				}

				for _, argument := range call.Common().Args {
					if _, callback := argument.Type().Underlying().(*types.Signature); callback {
						g.Gaps = append(g.Gaps, Gap{From: from, Reason: "callback passed to external code; invocation is not analysed", Location: loc})
						break
					}
				}
			}
		}

		for _, edge := range node.Out {
			if edge.Site == nil {
				continue
			}

			to := ssaID(edge.Callee.Func)
			if to == "" {
				continue
			}

			kind := "possible_call"
			if edge.Site.Common().StaticCallee() != nil {
				kind = "direct_call"
			}

			loc := location(program.Fset, edge.Site.Common().Pos(), root)
			g.Edges = append(g.Edges, Edge{From: from, To: to, Kind: kind, Location: loc})
			if kind == "direct_call" {
				g.Gaps = slices.DeleteFunc(g.Gaps, func(gap Gap) bool {
					return gap.From == from && gap.Location == loc && gap.Reason == "unresolved function value or callback"
				})
			}

			if _, ok := g.Nodes[to]; !ok && edge.Callee.Func.Parent() == nil {
				callee := edge.Callee.Func
				if callee.Pkg != nil {
					pkg := callee.Pkg.Pkg.Path()
					dependency := g.SourcePackages[pkg]
					if dependency == nil || dependency.Module == nil || !dependency.Module.Main {
						g.Nodes[to] = Node{ID: to, Kind: "function", External: true}
						continue
					}
				}

				g.Gaps = append(g.Gaps, Gap{From: from, Reason: "repository or synthetic call target has no inspected body", Location: loc})
			}
		}
	}

	return
}

func ssaID(fn *ssa.Function) string {
	if fn == nil {
		return ""
	}

	if obj := fn.Object(); obj != nil {
		return Symbol(obj)
	}

	if fn.Parent() != nil {
		return fmt.Sprintf("%s$%s", ssaID(fn.Parent()), fn.Name())
	}

	if fn.Pkg != nil {
		return fmt.Sprintf("%s.%s", fn.Pkg.Pkg.Path(), fn.Name())
	}

	return strings.TrimSpace(fn.String())
}
