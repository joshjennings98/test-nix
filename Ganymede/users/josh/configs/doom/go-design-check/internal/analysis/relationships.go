package analysis

import (
	"bytes"
	"context"
	"fmt"
	"go/ast"
	"go/format"
	"go/types"
	"maps"
	"slices"

	"github.com/ARM-software/golang-utils/utils/parallelisation"
	"golang.org/x/tools/go/packages"
)

func collectRelationships(ctx context.Context, graph *Graph, all map[string]*packages.Package, objects map[string]types.Object, root string) (err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}

	for _, key := range slices.Sorted(maps.Keys(all)) {
		if err = parallelisation.DetermineContextError(ctx); err != nil {
			return
		}

		pkg := all[key]
		if pkg.TypesInfo == nil {
			continue
		}

		for _, file := range pkg.Syntax {
			for _, decl := range file.Decls {
				fn, ok := decl.(*ast.FuncDecl)
				if !ok || fn.Body == nil {
					continue
				}

				obj := pkg.TypesInfo.Defs[fn.Name]
				if obj == nil {
					continue
				}

				from := Symbol(obj)
				ast.Inspect(fn.Body, func(n ast.Node) bool {
					if _, closure := n.(*ast.FuncLit); closure {
						return false
					}

					call, ok := n.(*ast.CallExpr)
					if !ok {
						return true
					}

					if tv, exists := pkg.TypesInfo.Types[call.Fun]; exists && tv.IsType() {
						return true
					}

					callee := callObject(pkg, call.Fun)
					if _, builtin := callee.(*types.Builtin); builtin {
						return true
					}

					loc := location(pkg.Fset, call.Lparen, root)
					firstGap := len(graph.Gaps)
					defer func() {
						if firstGap == len(graph.Gaps) {
							return
						}
						var expression bytes.Buffer
						if subErr := format.Node(&expression, pkg.Fset, call); subErr != nil {
							return
						}
						for i := firstGap; i < len(graph.Gaps); i++ {
							graph.Gaps[i].Expression = expression.String()
						}
					}()
					target, resolved := callee.(*types.Func)
					if !resolved {
						graph.Gaps = append(graph.Gaps, Gap{From: from, Reason: "unresolved function value or callback", Location: loc})
						return true
					}

					to := Symbol(target)
					if to == "" {
						graph.Gaps = append(graph.Gaps, interfaceGap(from, "dispatch through a predeclared interface", target, loc))
						return true
					}

					if target.Pkg() != nil && (target.Pkg().Path() == "reflect" || target.Pkg().Path() == "unsafe") {
						graph.Gaps = append(graph.Gaps, Gap{From: from, Reason: "reflection or unsafe operation", Location: loc})
					}

					kind := "direct_call"
					sig := target.Type().(*types.Signature)
					if sig.Recv() != nil {
						if _, isInterface := sig.Recv().Type().Underlying().(*types.Interface); isInterface {
							kind = "possible_call"
							graph.Gaps = append(graph.Gaps, interfaceGap(from, "interface dispatch has conservative candidate targets", target, loc))
						}
					}

					graph.Edges = append(graph.Edges, Edge{From: from, To: to, Kind: kind, Location: loc})
					if _, exists := graph.Nodes[to]; !exists {
						addObject(graph, pkg, target)
					}

					if graph.Nodes[to].External {
						for _, argument := range call.Args {
							typ := pkg.TypesInfo.TypeOf(argument)
							if typ == nil {
								continue
							}

							if _, callback := typ.Underlying().(*types.Signature); callback {
								graph.Gaps = append(graph.Gaps, Gap{From: from, Reason: "callback passed to external code; invocation is not analysed", Location: loc})
							}
						}
					}

					return true
				})
			}
		}
	}

	// go/types provides exact method-set conformance. Candidate interface calls remain possible.
	interfaces := map[string]*types.Interface{}
	for _, path := range slices.Sorted(maps.Keys(graph.SourcePackages)) {
		if err = parallelisation.DetermineContextError(ctx); err != nil {
			return
		}

		pkg := graph.SourcePackages[path]
		if pkg.Types == nil {
			continue
		}

		for _, name := range pkg.Types.Scope().Names() {
			object, isType := pkg.Types.Scope().Lookup(name).(*types.TypeName)
			if !isType {
				continue
			}

			if iface, ok := object.Type().Underlying().(*types.Interface); ok {
				interfaces[Symbol(object)] = iface
				addObject(graph, pkg, object)
			}
		}
	}

	for _, interfaceID := range slices.Sorted(maps.Keys(interfaces)) {
		if err = parallelisation.DetermineContextError(ctx); err != nil {
			return
		}

		iface := interfaces[interfaceID]

		for _, typeID := range slices.Sorted(maps.Keys(objects)) {
			object, isType := objects[typeID].(*types.TypeName)
			if !isType {
				continue
			}

			if _, isInterface := object.Type().Underlying().(*types.Interface); isInterface {
				continue
			}

			for _, typ := range []types.Type{object.Type(), types.NewPointer(object.Type())} {
				if !types.Implements(typ, iface) {
					continue
				}

				id := typeID
				if _, pointer := typ.(*types.Pointer); pointer {
					id = fmt.Sprintf("*%s", typeID)
				}

				graph.Edges = append(graph.Edges, Edge{From: id, To: interfaceID, Kind: "implements"})
				for i := range iface.NumMethods() {
					method := iface.Method(i)
					impl, _, _ := types.LookupFieldOrMethod(typ, true, method.Pkg(), method.Name())
					if impl == nil {
						continue
					}

					for _, edge := range slices.Clone(graph.Edges) {
						if edge.Kind == "possible_call" && edge.To == Symbol(method) {
							graph.Edges = append(graph.Edges, Edge{From: edge.From, To: Symbol(impl), Kind: "possible_call", Location: edge.Location})
						}
					}
				}
			}
		}
	}

	return
}

func callObject(pkg *packages.Package, expr ast.Expr) types.Object {
	switch x := expr.(type) {
	case *ast.Ident:
		return pkg.TypesInfo.Uses[x]
	case *ast.SelectorExpr:
		return pkg.TypesInfo.Uses[x.Sel]
	case *ast.IndexExpr:
		return callObject(pkg, x.X)
	case *ast.IndexListExpr:
		return callObject(pkg, x.X)
	case *ast.ParenExpr:
		return callObject(pkg, x.X)
	}

	return nil
}
