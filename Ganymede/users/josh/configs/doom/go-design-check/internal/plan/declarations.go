package plan

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/scanner"
	"go/token"
	"maps"
	"slices"
	"strings"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
)

func (d Declaration) Parts() (pkg, name, receiver string) {
	if index := strings.Index(d.Symbol, ".("); index >= 0 {
		pkg = d.Symbol[:index]
		rest := d.Symbol[index+2:]
		if end := strings.Index(rest, ")."); end >= 0 {
			receiver, name = rest[:end], rest[end+2:]
		}

		return
	}

	if index := strings.LastIndexByte(d.Symbol, '.'); index >= 0 {
		pkg, name = d.Symbol[:index], d.Symbol[index+1:]
	}

	return
}

// Parse validates a declaration shape without requiring the target code to exist.
func (d Declaration) Parse(fset *token.FileSet, shape string) (file *ast.File, err error) {
	pkg, name, receiver := d.Parts()
	shape = declarationAliases(shape, pkg, d.Imports)
	var declaration string
	switch d.Kind {
	case "function", "method":
		if !strings.HasPrefix(shape, "func") {
			return nil, commonerrors.Newf(commonerrors.ErrInvalid, "function shape must begin with func")
		}

		prefix := "func"
		if receiver != "" {
			prefix = fmt.Sprintf("func (receiver %s)", receiver)
		}

		declaration = fmt.Sprintf("%s %s%s", prefix, name, strings.TrimPrefix(shape, "func"))
	case "type", "interface":
		declaration = fmt.Sprintf("type %s %s", name, shape)
	case "variable":
		declaration = fmt.Sprintf("var %s %s", name, shape)
	case "constant":
		if strings.HasPrefix(shape, "untyped ") {
			kind, value, exists := strings.Cut(shape, "=")
			if !exists {
				return nil, commonerrors.Newf(commonerrors.ErrInvalid, "constant shape requires a value")
			}

			value = strings.TrimSpace(value)
			switch strings.TrimSpace(kind) {
			case "untyped float":
				value = fmt.Sprintf("(%s) + 0.0", value)
			case "untyped complex":
				value = fmt.Sprintf("(%s) + 0i", value)
			case "untyped rune":
				value = fmt.Sprintf("(%s) + '\\x00'", value)
			case "untyped int", "untyped bool", "untyped string":
			default:
				return nil, commonerrors.Newf(commonerrors.ErrInvalid, "unsupported constant kind %q", strings.TrimSpace(kind))
			}

			shape = fmt.Sprintf("= %s", value)
		}

		declaration = fmt.Sprintf("const %s %s", name, shape)
	case "field":
		declaration = fmt.Sprintf("type __field_%s struct { %s %s }", shapeHash(d.ID)[:12], name, shape)
	default:
		return nil, commonerrors.Newf(commonerrors.ErrInvalid, "declaration %s requires a supported kind", d.ID)
	}

	var source strings.Builder
	source.WriteString("package proposal\n")
	for _, alias := range slices.Sorted(maps.Keys(d.Imports)) {
		if !token.IsIdentifier(alias) || alias == "_" {
			return nil, commonerrors.Newf(commonerrors.ErrInvalid, "invalid import alias %q", alias)
		}

		fmt.Fprintf(&source, "import %s %q\n", alias, d.Imports[alias])
	}

	fmt.Fprintln(&source, declaration)
	file, err = parser.ParseFile(fset, fmt.Sprintf("proposal-%s.go", d.ID), source.String(), parser.AllErrors)
	if err != nil {
		return
	}

	if len(file.Decls) != len(d.Imports)+1 {
		return nil, commonerrors.Newf(commonerrors.ErrInvalid, "shape must describe exactly one declaration")
	}

	last := file.Decls[len(file.Decls)-1]
	if fn, ok := last.(*ast.FuncDecl); ok && fn.Body != nil {
		return nil, commonerrors.Newf(commonerrors.ErrInvalid, "function shape must not contain a body")
	}

	if d.Kind == "interface" {
		decl := last.(*ast.GenDecl)
		if _, ok := decl.Specs[0].(*ast.TypeSpec).Type.(*ast.InterfaceType); !ok {
			return nil, commonerrors.Newf(commonerrors.ErrInvalid, "interface shape must describe an interface")
		}
	}

	return
}

func declarationAliases(shape, pkg string, imports map[string]string) string {
	replacements := []string{fmt.Sprintf("%s.", pkg), ""}
	for _, alias := range slices.Sorted(maps.Keys(imports)) {
		replacements = append(replacements, fmt.Sprintf("%s.", imports[alias]), fmt.Sprintf("%s.", alias))
	}

	replacer := strings.NewReplacer(replacements...)
	var lexer scanner.Scanner
	file := token.NewFileSet().AddFile("shape", -1, len(shape))
	lexer.Init(file, []byte(shape), nil, 0)
	var result strings.Builder
	start := 0
	for {
		position, kind, literal := lexer.Scan()
		if kind == token.EOF {
			break
		}

		if kind != token.STRING && kind != token.CHAR {
			continue
		}

		offset := file.Offset(position)
		result.WriteString(replacer.Replace(shape[start:offset]))
		result.WriteString(literal)
		start = offset + len(literal)
	}

	result.WriteString(replacer.Replace(shape[start:]))
	return result.String()
}
