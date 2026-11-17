package analysis

import (
	"context"
	"fmt"
	"go/token"
	"maps"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
	"github.com/ARM-software/golang-utils/utils/parallelisation"
	"golang.org/x/tools/go/packages"
)

type Options struct {
	CGOEnabled *bool
	Root       string
	Patterns   []string
	Tags       []string
	GOOS       string
	GOARCH     string
}

func Load(ctx context.Context, opts Options) (graph *Graph, err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}

	graph = New()
	opts.Root, err = filepath.Abs(opts.Root)
	if err != nil {
		return
	}

	if len(opts.Patterns) == 0 {
		opts.Patterns = []string{"./..."}
	}

	if opts.GOOS == "" {
		opts.GOOS = runtime.GOOS
	}

	if opts.GOARCH == "" {
		opts.GOARCH = runtime.GOARCH
	}

	cfg := &packages.Config{Context: ctx, Dir: opts.Root, Mode: packages.LoadAllSyntax | packages.NeedModule, Tests: false,
		Env: append(os.Environ(), buildEnvironmentOverrides(opts)...)}
	if len(opts.Tags) > 0 {
		cfg.BuildFlags = []string{fmt.Sprintf("-tags=%s", strings.Join(opts.Tags, ","))}
	}

	roots, err := packages.Load(cfg, opts.Patterns...)
	if err != nil {
		return
	}

	all := map[string]*packages.Package{}
	graph.SourcePackages = map[string]*packages.Package{}
	packages.Visit(roots, nil, func(pkg *packages.Package) {
		graph.SourcePackages[pkg.PkgPath] = pkg
		if graph.TypesSizes == nil && pkg.TypesSizes != nil {
			graph.TypesSizes = pkg.TypesSizes
		}
		for _, problem := range pkg.Errors {
			graph.Errors = append(graph.Errors, problem.Error())
		}

		if pkg.Module != nil && pkg.Module.Main && len(pkg.Syntax) > 0 {
			all[pkg.ID] = pkg
		}

	})
	if len(roots) == 0 {
		graph.Errors = append(graph.Errors, "no packages matched the selected scope")
	}

	if len(all) == 0 && len(graph.Errors) == 0 {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "no production packages in a main Go module matched the scope")
		return
	}

	if graph.TypesSizes == nil && len(graph.Errors) == 0 {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "target type sizes are unavailable")
		return
	}

	objects, err := collectDeclarations(ctx, graph, all, opts.Root)
	if err != nil {
		return
	}
	graph.Objects = objects

	if err = collectRelationships(ctx, graph, all, objects, opts.Root); err != nil {
		return
	}

	if err = addSSA(ctx, graph, roots, opts.Root); err != nil {
		return
	}

	slices.Sort(graph.Errors)
	graph.Errors = slices.Compact(graph.Errors)

	slices.SortFunc(graph.Edges, func(a, b Edge) int {
		return strings.Compare(fmt.Sprintf("%s|%s|%s|%s:%d:%d:%d", a.From, a.To, a.Kind, a.Location.File, a.Location.Line, a.Location.Column, a.Location.EndLine), fmt.Sprintf("%s|%s|%s|%s:%d:%d:%d", b.From, b.To, b.Kind, b.Location.File, b.Location.Line, b.Location.Column, b.Location.EndLine))
	})
	graph.Edges = slices.Compact(graph.Edges)
	slices.SortFunc(graph.Gaps, func(a, b Gap) int {
		return strings.Compare(fmt.Sprintf("%s|%s|%s:%d:%d:%d", a.From, a.Reason, a.Location.File, a.Location.Line, a.Location.Column, a.Location.EndLine), fmt.Sprintf("%s|%s|%s:%d:%d:%d", b.From, b.Reason, b.Location.File, b.Location.Line, b.Location.Column, b.Location.EndLine))
	})
	graph.Gaps = slices.Compact(graph.Gaps)
	for _, id := range slices.Sorted(maps.Keys(graph.Nodes)) {
		node := graph.Nodes[id]
		node.Location.File = relative(opts.Root, node.Location.File)
		graph.Nodes[id] = node
	}

	return
}

func location(fset *token.FileSet, pos token.Pos, root string) Location {
	p := fset.Position(pos)
	return Location{File: relative(root, p.Filename), Line: p.Line, Column: p.Column}
}

func relative(root, path string) string {
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return path
	}

	return filepath.ToSlash(rel)
}
