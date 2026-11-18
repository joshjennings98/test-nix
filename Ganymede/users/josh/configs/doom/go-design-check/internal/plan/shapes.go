package plan

import (
	"bytes"
	"fmt"
	"go/ast"
	"go/format"
	"go/importer"
	"go/token"
	"go/types"
	"maps"
	"slices"
	"strconv"
	"strings"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
	"github.com/ARM-software/golang-utils/utils/field"

	"go-design-check/internal/analysis"
	"go-design-check/internal/check"
)

type proposalPackages struct {
	source            *analysis.Graph
	design            design
	fset              *token.FileSet
	groups            map[string][]Declaration
	checked           map[string]*types.Package
	checking          map[string]bool
	missingDependency bool
}

// declarationShapes type-checks the baseline/proposal union with function bodies ignored.
func declarationShapes(d design, source *analysis.Graph) (shapes map[string]string, parents map[string]string, findings []check.Finding) {
	shapes = map[string]string{}
	parents = map[string]string{}
	if len(d.Declarations) == 0 {
		return
	}

	packages := &proposalPackages{source: source, design: d, fset: token.NewFileSet(), groups: map[string][]Declaration{}, checked: map[string]*types.Package{}, checking: map[string]bool{}}
	for _, declaration := range d.Declarations {
		pkg, _, _ := declaration.Parts()
		packages.groups[pkg] = append(packages.groups[pkg], declaration)
	}

	if source != nil {
		for _, name := range slices.Sorted(maps.Keys(source.SourcePackages)) {
			if pkg := source.SourcePackages[name]; pkg.Fset != nil {
				packages.fset = pkg.Fset
				break
			}
		}
	}

	for _, name := range slices.Sorted(maps.Keys(packages.groups)) {
		pkg, err := packages.Import(name)
		if err != nil {
			status := check.Error
			if commonerrors.Any(err, commonerrors.ErrNotFound) || packages.missingDependency || (source != nil && len(source.Errors) > 0) {
				status = check.Unknown
			}
			findings = append(findings, check.Finding{ID: name, Status: status, Message: err.Error()})
			continue
		}

		for _, declaration := range packages.groups[name] {
			_, _, receiverName := declaration.Parts()
			if declaration.Kind == "field" {
				receiverName = strings.TrimPrefix(receiverName, "*")
				if parent := pkg.Scope().Lookup(receiverName); parent != nil {
					parents[analysis.Symbol(parent)] = analysis.ObjectSignature(parent)
				}
			}

			if declaration.Change == "remove" {
				continue
			}

			_, objectName, receiver := declaration.Parts()
			object := pkg.Scope().Lookup(objectName)
			if receiver != "" {
				receiver = strings.TrimPrefix(receiver, "*")
				receiver, _, _ = strings.Cut(receiver, "[")
				parent := pkg.Scope().Lookup(receiver)
				if parent == nil {
					findings = append(findings, check.Finding{ID: declaration.ID, Status: check.Error, Message: "receiver type does not exist in the baseline/proposal union"})
					continue
				}

				receiverType := parent.Type()
				if _, isInterface := receiverType.Underlying().(*types.Interface); !isInterface {
					receiverType = types.NewPointer(receiverType)
				}

				object, _, _ = types.LookupFieldOrMethod(receiverType, true, pkg, objectName)
			}

			if object == nil {
				findings = append(findings, check.Finding{ID: declaration.ID, Status: check.Error, Message: "proposed declaration could not be resolved"})
				continue
			}

			actualKind := analysis.ObjectKind(object)
			if string(declaration.Kind) != actualKind && !(declaration.Kind == "type" && actualKind == "interface") {
				findings = append(findings, check.Finding{ID: declaration.ID, Status: check.Error, Message: "proposed declaration kind does not match its shape"})
				continue
			}

			shapes[declaration.ID] = analysis.ObjectSignature(object)
			if declaration.Kind == "constant" {
				kind, _, _ := strings.Cut(field.Optional(declaration.After, ""), "=")
				kind = strings.TrimSpace(kind)
				if strings.HasPrefix(kind, "untyped ") && types.TypeString(object.Type(), nil) != kind {
					findings = append(findings, check.Finding{ID: declaration.ID, Status: check.Error, Message: "constant expression does not match its declared untyped kind"})
				}
			}

			if declaration.Kind == "field" {
				parent := pkg.Scope().Lookup(receiver)
				if structure, ok := parent.Type().Underlying().(*types.Struct); ok {
					for i := range structure.NumFields() {
						if structure.Field(i).Name() == objectName && structure.Tag(i) != "" {
							shapes[declaration.ID] = fmt.Sprintf("%s %q", shapes[declaration.ID], structure.Tag(i))
						}
					}
				}
			}
		}
	}

	return
}

func (p *proposalPackages) Import(path string) (pkg *types.Package, err error) {
	if cached := p.checked[path]; cached != nil {
		return cached, nil
	}

	declarations, proposed := p.groups[path]
	if !proposed {
		local := false
		if p.source != nil {
			if original := p.source.SourcePackages[path]; original != nil && original.Types != nil && original.Types.Complete() {
				if original.Module == nil || !original.Module.Main || len(original.Syntax) == 0 {
					return original.Types, nil
				}
				local = true
			}
		}

		if !local {
			pkg, err = importer.Default().Import(path)
			if err != nil {
				p.missingDependency = true
				err = commonerrors.WrapErrorf(commonerrors.ErrNotFound, err, "proposal dependency %s is unavailable", path)
			}
			return
		}
	}

	if p.checking[path] {
		return nil, commonerrors.Newf(commonerrors.ErrInvalid, "proposal import cycle at %s", path)
	}

	p.checking[path] = true
	defer delete(p.checking, path)
	var files []*ast.File
	imports := map[string]string{}
	packageName := "proposal"
	if p.source != nil {
		if original := p.source.SourcePackages[path]; original != nil {
			packageName = original.Name
			for _, source := range original.Syntax {
				file := *source
				file.Decls = nil
				for _, item := range source.Decls {
					filtered := filterDeclaration(path, item, declarations)
					if filtered != nil {
						file.Decls = append(file.Decls, filtered)
					}
				}

				files = append(files, &file)
				for _, item := range source.Imports {
					importPath, subErr := strconv.Unquote(item.Path.Value)
					if subErr != nil {
						continue
					}

					alias := ""
					if item.Name != nil {
						alias = item.Name.Name
					} else if imported := original.Imports[importPath]; imported != nil {
						alias = imported.Name
					}

					if alias != "" && alias != "_" && alias != "." {
						if previous, exists := imports[alias]; exists && previous != importPath {
							imports[alias] = ""
						} else {
							imports[alias] = importPath
						}
					}
				}
			}
		}
	}

	// Build proposed types before applying edits to their members.
	declarations = slices.Clone(declarations)
	slices.SortStableFunc(declarations, func(a, b Declaration) int {
		aMember := a.Kind == "field" || a.Kind == "method"
		bMember := b.Kind == "field" || b.Kind == "method"
		if aMember == bMember {
			return 0
		}

		if aMember {
			return 1
		}

		return -1
	})

	for _, declaration := range declarations {
		declaration.Imports = maps.Clone(declaration.Imports)
		if declaration.Imports == nil {
			declaration.Imports = map[string]string{}
		}

		for _, alias := range slices.Sorted(maps.Keys(imports)) {
			if imports[alias] == "" {
				continue
			}
			if _, explicit := declaration.Imports[alias]; !explicit {
				declaration.Imports[alias] = imports[alias]
			}
		}

		if declaration.Kind == "field" || declaration.Kind == "method" {
			handled, subErr := p.changeMember(files, declaration)
			if subErr != nil {
				return nil, subErr
			}

			if handled {
				continue
			}
		}

		if declaration.Change == "remove" {
			continue
		}

		file, subErr := declaration.Parse(p.fset, field.Optional(declaration.After, ""))
		if subErr != nil {
			return nil, subErr
		}

		file.Name.Name = packageName
		for _, item := range file.Decls {
			if fn, ok := item.(*ast.FuncDecl); ok {
				fn.Body = &ast.BlockStmt{Lbrace: fn.End(), Rbrace: fn.End()}
			}
		}

		files = append(files, file)
	}

	configuration := types.Config{Importer: p, Sizes: p.source.TypesSizes, IgnoreFuncBodies: true, DisableUnusedImportCheck: true}
	pkg, err = configuration.Check(path, p.fset, files, nil)
	if err != nil {
		return nil, commonerrors.WrapErrorf(commonerrors.ErrInvalid, err, "invalid proposal declarations in %s", path)
	}

	p.checked[path] = pkg
	return
}

func filterDeclaration(pkg string, item ast.Decl, changes []Declaration) ast.Decl {
	changed := map[string]bool{}
	for _, change := range changes {
		if change.Kind != "field" {
			changed[change.Symbol] = true
		}
	}

	if fn, ok := item.(*ast.FuncDecl); ok {
		id := fmt.Sprintf("%s.%s", pkg, fn.Name.Name)
		if fn.Recv != nil {
			var receiver bytes.Buffer
			_ = format.Node(&receiver, token.NewFileSet(), fn.Recv.List[0].Type)
			id = fmt.Sprintf("%s.(%s).%s", pkg, receiver.String(), fn.Name.Name)
		}

		if changed[id] {
			return nil
		}

		return item
	}

	group, ok := item.(*ast.GenDecl)
	if !ok || group.Tok == token.IMPORT {
		return item
	}

	affected := false
	for _, entry := range group.Specs {
		switch value := entry.(type) {
		case *ast.TypeSpec:
			affected = affected || changed[fmt.Sprintf("%s.%s", pkg, value.Name.Name)]
		case *ast.ValueSpec:
			for _, name := range value.Names {
				affected = affected || changed[fmt.Sprintf("%s.%s", pkg, name.Name)]
			}
		}
	}

	if !affected {
		return item
	}

	copy := *group
	copy.Specs = nil
	var inherited *ast.ValueSpec
	for _, entry := range group.Specs {
		switch value := entry.(type) {
		case *ast.TypeSpec:
			if !changed[fmt.Sprintf("%s.%s", pkg, value.Name.Name)] {
				copy.Specs = append(copy.Specs, value)
			}
		case *ast.ValueSpec:
			if group.Tok == token.VAR {
				if retained := filterVariables(pkg, value, changed); retained != nil {
					copy.Specs = append(copy.Specs, retained)
				}
				continue
			}

			if len(value.Values) > 0 {
				inherited = value
			}

			copy.Specs = append(copy.Specs, filterConstants(pkg, value, inherited, changed))
		}
	}

	if group.Tok == token.CONST || group.Tok == token.VAR {
		retained := false
		for _, entry := range copy.Specs {
			for _, name := range entry.(*ast.ValueSpec).Names {
				if name.Name != "_" {
					retained = true
				}
			}
		}

		if !retained {
			return nil
		}
	}

	if len(copy.Specs) == 0 {
		return nil
	}

	return &copy
}

func filterConstants(pkg string, value, inherited *ast.ValueSpec, changed map[string]bool) *ast.ValueSpec {
	part := *value
	part.Type = inherited.Type
	part.Names = nil
	part.Values = nil
	for i, name := range value.Names {
		if changed[fmt.Sprintf("%s.%s", pkg, name.Name)] {
			continue
		}

		part.Names = append(part.Names, name)
		part.Values = append(part.Values, inherited.Values[i])
	}

	if len(part.Names) == 0 {
		// Keep the iota position without retaining deleted dependencies.
		// Surviving specs have their original inherited expressions made explicit.
		part.Type = nil
		part.Names = []*ast.Ident{{NamePos: value.Pos(), Name: "_"}}
		part.Values = []ast.Expr{&ast.BasicLit{ValuePos: value.Pos(), Kind: token.INT, Value: "0"}}
	}

	return &part
}

func filterVariables(pkg string, value *ast.ValueSpec, changed map[string]bool) *ast.ValueSpec {
	part := *value
	part.Names = nil
	part.Values = nil
	tuple := len(value.Values) > 0 && len(value.Values) != len(value.Names)
	retained := false
	for i, name := range value.Names {
		if changed[fmt.Sprintf("%s.%s", pkg, name.Name)] {
			if tuple {
				part.Names = append(part.Names, &ast.Ident{NamePos: name.Pos(), Name: "_"})
			}
			continue
		}

		retained = true
		part.Names = append(part.Names, name)
		if !tuple && len(value.Values) > 0 {
			part.Values = append(part.Values, value.Values[i])
		}
	}

	if !retained {
		return nil
	}

	if tuple {
		part.Values = value.Values
	}

	return &part
}
