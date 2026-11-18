package analysis

import (
	"context"
	"fmt"
	"go/ast"
	"go/constant"
	"go/types"
	"maps"
	"slices"
	"strings"

	"github.com/ARM-software/golang-utils/utils/parallelisation"
	"golang.org/x/tools/go/packages"
)

func ObjectKind(obj types.Object) string {
	switch item := obj.(type) {
	case *types.Func:
		if item.Type().(*types.Signature).Recv() != nil {
			return "method"
		}
		return "function"
	case *types.TypeName:
		if _, ok := item.Type().Underlying().(*types.Interface); ok {
			return "interface"
		}
		return "type"
	case *types.Const:
		return "constant"
	case *types.Var:
		if item.IsField() {
			return "field"
		}
	}

	return "variable"
}

func ObjectSignature(obj types.Object) string {
	qualifier := func(pkg *types.Package) string { return pkg.Path() }
	signature := types.TypeString(obj.Type(), qualifier)
	if _, ok := obj.(*types.TypeName); ok {
		signature = types.TypeString(obj.Type().Underlying(), qualifier)
		var parameters *types.TypeParamList
		switch item := obj.Type().(type) {
		case *types.Named:
			parameters = item.TypeParams()
		case *types.Alias:
			parameters = item.TypeParams()
			signature = fmt.Sprintf("= %s", types.TypeString(item.Rhs(), qualifier))
		}

		if parameters != nil && parameters.Len() > 0 {
			var parts []string
			for i := range parameters.Len() {
				parameter := parameters.At(i)
				parts = append(parts, fmt.Sprintf("%s %s", parameter.Obj().Name(), types.TypeString(parameter.Constraint(), qualifier)))
			}
			signature = fmt.Sprintf("[%s] %s", strings.Join(parts, ", "), signature)
		}
	}

	if item, ok := obj.(*types.Const); ok {
		signature = fmt.Sprintf("%s = %s", signature, ConstantExpression(item.Val()))
	}

	return signature
}

// ConstantExpression preserves exact values using valid Go arithmetic.
func ConstantExpression(value constant.Value) string {
	switch value.Kind() {
	case constant.Float:
		exact := value.ExactString()
		if numerator, denominator, fraction := strings.Cut(exact, "/"); fraction {
			return fmt.Sprintf("(%s.0 / %s.0)", numerator, denominator)
		}

		if strings.ContainsAny(exact, ".pPeE") {
			return exact
		}

		return fmt.Sprintf("%s.0", exact)
	case constant.Complex:
		return fmt.Sprintf("(%s + (%s) * 1i)", ConstantExpression(constant.ToFloat(constant.Real(value))), ConstantExpression(constant.ToFloat(constant.Imag(value))))
	}

	return value.ExactString()
}

func Symbol(obj types.Object) string {
	if obj == nil || obj.Pkg() == nil {
		return ""
	}

	if fn, ok := obj.(*types.Func); ok {
		sig := fn.Origin().Type().(*types.Signature)
		if sig.Recv() != nil {
			recv := types.TypeString(sig.Recv().Type(), func(*types.Package) string { return "" })
			return fmt.Sprintf("%s.(%s).%s", obj.Pkg().Path(), recv, obj.Name())
		}
	}

	return fmt.Sprintf("%s.%s", obj.Pkg().Path(), obj.Name())
}

func collectDeclarations(ctx context.Context, graph *Graph, all map[string]*packages.Package, root string) (objects map[string]types.Object, err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}
	// Analyse production packages; test execution and review belong to the caller.
	objects = map[string]types.Object{}
	for _, key := range slices.Sorted(maps.Keys(all)) {
		if err = parallelisation.DetermineContextError(ctx); err != nil {
			return
		}

		pkg := all[key]
		if pkg.Types == nil || pkg.TypesInfo == nil {
			graph.Errors = append(graph.Errors, fmt.Sprintf("type information unavailable for %s", pkg.PkgPath))
			continue
		}

		for _, name := range pkg.Types.Scope().Names() {
			obj := pkg.Types.Scope().Lookup(name)
			objects[Symbol(obj)] = obj
			addObject(graph, pkg, obj)
			if named, ok := obj.(*types.TypeName); ok {
				if structure, isStruct := named.Type().Underlying().(*types.Struct); isStruct {
					for i := range structure.NumFields() {
						field := structure.Field(i)
						id := fmt.Sprintf("%s.(%s).%s", pkg.PkgPath, named.Name(), field.Name())
						signature := ObjectSignature(field)
						if tag := structure.Tag(i); tag != "" {
							signature = fmt.Sprintf("%s %q", signature, tag)
						}

						graph.Nodes[id] = Node{ID: id, Kind: "field", Signature: signature, Location: Location{File: pkg.Fset.Position(field.Pos()).Filename, Line: pkg.Fset.Position(field.Pos()).Line}}
						graph.Edges = append(graph.Edges, Edge{From: Symbol(obj), To: id, Kind: "member", Location: location(pkg.Fset, field.Pos(), root)})
					}
				}

				if iface, isInterface := named.Type().Underlying().(*types.Interface); isInterface {
					for i := range iface.NumExplicitMethods() {
						method := iface.ExplicitMethod(i)
						id := fmt.Sprintf("%s.(%s).%s", pkg.PkgPath, named.Name(), method.Name())
						graph.Nodes[id] = Node{ID: id, Kind: "method", Signature: ObjectSignature(method), Location: location(pkg.Fset, method.Pos(), root)}
						graph.Edges = append(graph.Edges, Edge{From: Symbol(obj), To: id, Kind: "member", Location: location(pkg.Fset, method.Pos(), root)})
					}
				}
			}
		}

		for _, file := range pkg.Syntax {

			for _, decl := range file.Decls {

				fn, ok := decl.(*ast.FuncDecl)
				if !ok {
					continue
				}

				obj := pkg.TypesInfo.Defs[fn.Name]
				if obj == nil {
					continue
				}

				id := Symbol(obj)
				objects[id] = obj
				addObject(graph, pkg, obj)

				if signature, ok := obj.Type().(*types.Signature); ok && signature.Recv() != nil {
					receiver := signature.Recv().Type()
					if pointer, ok := receiver.(*types.Pointer); ok {
						receiver = pointer.Elem()
					}

					if named, ok := receiver.(*types.Named); ok {
						graph.Edges = append(graph.Edges, Edge{From: Symbol(named.Obj()), To: id, Kind: "member", Location: location(pkg.Fset, fn.Pos(), root)})
					}
				}

				if fn.Body == nil {
					graph.Gaps = append(graph.Gaps, Gap{From: id, Reason: "function body unavailable (assembly or external implementation)", Location: location(pkg.Fset, fn.Pos(), root)})
				}
			}
		}
	}

	return
}

func addObject(g *Graph, pkg *packages.Package, obj types.Object) {
	id := Symbol(obj)
	if id == "" {
		return
	}

	kind := ObjectKind(obj)
	signature := ObjectSignature(obj)

	pos := pkg.Fset.Position(obj.Pos())
	dependency := g.SourcePackages[obj.Pkg().Path()]
	external := dependency == nil || dependency.Module == nil || !dependency.Module.Main
	node := Node{ID: id, External: external, Kind: kind, Signature: signature, Location: Location{File: pos.Filename, Line: pos.Line, Column: pos.Column}}

	g.Nodes[id] = node
}
