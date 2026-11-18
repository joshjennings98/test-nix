package plan

import (
	"go/ast"
	"go/token"
	"slices"
	"strconv"
	"strings"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
	"github.com/ARM-software/golang-utils/utils/field"
)

func (p *proposalPackages) changeMember(files []*ast.File, declaration Declaration) (handled bool, err error) {
	_, name, receiver := declaration.Parts()
	pointerReceiver := strings.HasPrefix(receiver, "*")
	receiver = strings.TrimPrefix(receiver, "*")
	for _, file := range files {
		for i, item := range file.Decls {
			group, ok := item.(*ast.GenDecl)
			if !ok || group.Tok != token.TYPE {
				continue
			}

			copyGroup := *group
			copyGroup.Specs = slices.Clone(group.Specs)
			for j, entry := range group.Specs {
				typ := entry.(*ast.TypeSpec)
				if typ.Name.Name != receiver {
					continue
				}

				var original *ast.FieldList
				copyType := *typ
				switch body := typ.Type.(type) {
				case *ast.StructType:
					if declaration.Kind != "field" {
						return false, nil
					}
					copyStruct := *body
					copyType.Type = &copyStruct
					original = body.Fields
				case *ast.InterfaceType:
					if declaration.Kind != "method" || pointerReceiver {
						return false, commonerrors.Newf(commonerrors.ErrInvalid, "interface member %s requires a non-pointer method receiver", declaration.ID)
					}
					copyInterface := *body
					copyType.Type = &copyInterface
					original = body.Methods
				default:
					if declaration.Kind == "method" {
						return false, nil
					}
					return false, commonerrors.Newf(commonerrors.ErrInvalid, "field %s requires a struct receiver", declaration.ID)
				}

				fields := *original
				fields.List = nil
				embedded := false
				position := -1
				for _, old := range original.List {
					if declaration.Kind == "field" && len(old.Names) == 0 && embeddedFieldName(old.Type) == name {
						embedded = true
						position = len(fields.List)
						continue
					}

					if len(old.Names) == 0 {
						fields.List = append(fields.List, old)
						continue
					}

					for _, oldName := range old.Names {
						if oldName.Name == name {
							position = len(fields.List)
							continue
						}

						copyField := *old
						copyField.Names = []*ast.Ident{oldName}
						fields.List = append(fields.List, &copyField)
					}
				}

				if declaration.Change != "remove" {
					parsed, subErr := declaration.Parse(p.fset, field.Optional(declaration.After, ""))
					if subErr != nil {
						return false, subErr
					}

					var added *ast.Field
					last := parsed.Decls[len(parsed.Decls)-1]
					if declaration.Kind == "method" {
						method := last.(*ast.FuncDecl)
						added = &ast.Field{Names: []*ast.Ident{method.Name}, Type: method.Type}
					} else {
						added = last.(*ast.GenDecl).Specs[0].(*ast.TypeSpec).Type.(*ast.StructType).Fields.List[0]
						if embedded && embeddedFieldName(added.Type) == name {
							added.Names = nil
						}
					}
					if position >= 0 {
						fields.List = slices.Insert(fields.List, position, added)
					} else {
						fields.List = append(fields.List, added)
					}
					for _, imported := range parsed.Imports {
						found := false
						importPath, _ := strconv.Unquote(imported.Path.Value)
						for _, existing := range file.Imports {
							existingPath, _ := strconv.Unquote(existing.Path.Value)
							alias := ""
							if existing.Name != nil {
								alias = existing.Name.Name
							} else if dependency := p.source.SourcePackages[existingPath]; dependency != nil {
								alias = dependency.Name
							}

							if existingPath == importPath && alias == imported.Name.Name {
								found = true
							}
						}

						if !found {
							file.Imports = append(file.Imports, imported)
							file.Decls = append(file.Decls, &ast.GenDecl{Tok: token.IMPORT, Specs: []ast.Spec{imported}})
						}
					}
				}

				switch body := copyType.Type.(type) {
				case *ast.StructType:
					body.Fields = &fields
				case *ast.InterfaceType:
					body.Methods = &fields
				}
				copyGroup.Specs[j] = &copyType
				file.Decls[i] = &copyGroup
				return true, nil
			}
		}
	}

	if declaration.Kind == "method" {
		return false, nil
	}

	return false, commonerrors.Newf(commonerrors.ErrInvalid, "field %s receiver is absent from the baseline/proposal union", declaration.ID)
}

func embeddedFieldName(expression ast.Expr) string {
	switch value := expression.(type) {
	case *ast.Ident:
		return value.Name
	case *ast.SelectorExpr:
		return value.Sel.Name
	case *ast.StarExpr:
		return embeddedFieldName(value.X)
	case *ast.IndexExpr:
		return embeddedFieldName(value.X)
	case *ast.IndexListExpr:
		return embeddedFieldName(value.X)
	}

	return ""
}
