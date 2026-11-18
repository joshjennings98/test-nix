package app

import (
	"bytes"
	"context"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCLI(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example/app\ngo 1.26\n"), 0600))
	source := `package app
import ("reflect"; "sort"; "strings")
func Start() { Validate() }
func Validate() {}
func Unknown(f func()) { f() }
func Closure(f func()) { func() { f() }() }
func KnownClosure() { func() { Validate() }() }
func ClosureReflect(f any) { func() { reflect.ValueOf(f).Call(nil) }() }
func ClosureCallback(xs []int) { func() { sort.Slice(xs, func(i,j int) bool { Validate(); return false }) }() }
func NestedCallback(xs []int) { func() { func() { sort.Slice(xs, func(i,j int) bool { Validate(); return false }) }() }() }
func DeferredCallback(xs []int) { defer func() { sort.Slice(xs, func(i,j int) bool { Validate(); return false }) }() }
func ConcurrentCallback(xs []int) { go func() { sort.Slice(xs, func(i,j int) bool { Validate(); return false }) }() }
func PureClosure(s string) { func() { _ = len(strings.TrimSpace(s)) }() }
type Worker struct{}
func (Worker) Run() {}
func (*Worker) Stop() {}
`
	require.NoError(t, filesystem.WriteFile(filepath.Join(root, "app.go"), []byte(source), 0600))

	tests := []struct {
		name    string
		request string
		code    int
		status  string
	}{
		{"pass", `{"rules":[{"id":"x","kind":"direct_call","from":"example/app.Start","to":"example/app.Validate"}]}`, 0, "PASS"},
		{"fail", `{"rules":[{"id":"x","kind":"exists","symbol":"example/app.Missing"}]}`, 3, "FAIL"},
		{"unknown", `{"rules":[{"id":"x","kind":"forbid_call","from":"example/app.Unknown","to":"example/app.Validate"}]}`, 4, "UNKNOWN"},
		{"unresolved closure", `{"rules":[{"id":"x","kind":"forbid_path","from":"example/app.Closure","to":"example/app.Validate"}]}`, 4, "UNKNOWN"},
		{"known closure", `{"rules":[{"id":"x","kind":"reaches","from":"example/app.KnownClosure","to":"example/app.Validate"}]}`, 0, "PASS"},
		{"closure reflection", `{"rules":[{"id":"x","kind":"forbid_path","from":"example/app.ClosureReflect","to":"example/app.Validate"}]}`, 4, "UNKNOWN"},
		{"closure external callback", `{"rules":[{"id":"x","kind":"forbid_path","from":"example/app.ClosureCallback","to":"example/app.Validate"}]}`, 4, "UNKNOWN"},
		{"nested external callback", `{"rules":[{"id":"x","kind":"forbid_path","from":"example/app.NestedCallback","to":"example/app.Validate"}]}`, 4, "UNKNOWN"},
		{"deferred external callback", `{"rules":[{"id":"x","kind":"forbid_path","from":"example/app.DeferredCallback","to":"example/app.Validate"}]}`, 4, "UNKNOWN"},
		{"concurrent external callback", `{"rules":[{"id":"x","kind":"forbid_path","from":"example/app.ConcurrentCallback","to":"example/app.Validate"}]}`, 4, "UNKNOWN"},
		{"closure without callback", `{"rules":[{"id":"x","kind":"forbid_path","from":"example/app.PureClosure","to":"example/app.Validate"}]}`, 0, "PASS"},
		{"value method membership", `{"rules":[{"id":"x","kind":"member","from":"example/app.Worker","to":"example/app.(Worker).Run"}]}`, 0, "PASS"},
		{"pointer method membership", `{"rules":[{"id":"x","kind":"member","from":"example/app.Worker","to":"example/app.(*Worker).Stop"}]}`, 0, "PASS"},
		{"typo", `{"rulez":[]}`, 5, "ERROR"},
		{"trailing value", `{"rules":[]} {}`, 5, "ERROR"},
		{"removed rule", `{"rules":[{"id":"x","kind":"all_paths_via","from":"a","to":"b","via":"c"}]}`, 5, "ERROR"},
		{"empty rules", `{"rules":[]}`, 5, "ERROR"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			var output, diagnostics bytes.Buffer
			code := Run(context.Background(), []string{"check", "--root", root}, strings.NewReader(test.request), &output, &diagnostics)
			assert.Equal(t, test.code, code, output.String())
			var result struct {
				Status string `json:"status"`
			}
			require.NoError(t, json.Unmarshal(output.Bytes(), &result))
			assert.Equal(t, test.status, result.Status)
		})
	}

}

func TestCLIArgumentErrors(t *testing.T) {
	t.Parallel()
	for _, args := range [][]string{{"nope"}, {"check", "extra"}, {"check", "--cgo", "maybe"}, {"diff"}, {"inspect"}, {"check", "--packages", ""}, {"check", "--timeout", "0"}} {
		var output, diagnostics bytes.Buffer
		code := Run(context.Background(), args, strings.NewReader(""), &output, &diagnostics)
		assert.Equal(t, 5, code, "%v: %s", args, output.String())
	}
}
