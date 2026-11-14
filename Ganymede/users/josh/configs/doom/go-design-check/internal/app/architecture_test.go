package app

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go-design-check/internal/check"
	"go-design-check/internal/plan"
)

func TestProposalUsesSelectedArchitecture(t *testing.T) {
	t.Parallel()
	for _, test := range []struct {
		arch string
		size int
	}{{"386", 4}, {"amd64", 8}} {
		t.Run(test.arch, func(t *testing.T) {
			t.Parallel()
			root := t.TempDir()
			require.NoError(t, filesystem.WriteFile(filepath.Join(root, "go.mod"), []byte("module example/probe\ngo 1.26\n"), 0600))
			source := "package probe\nimport \"unsafe\"\nconst N=unsafe.Sizeof(int(0))\n"
			require.NoError(t, filesystem.WriteFile(filepath.Join(root, "app.go"), []byte(source), 0600))
			options := []string{"--root", root, "--goarch", test.arch, "--goos", "linux", "--cgo", "off"}
			var output, diagnostics bytes.Buffer
			code := Run(context.Background(), append([]string{"validate"}, options...), strings.NewReader(`{"graphs":[{"id":"layout","declarations":[{"symbol":"example/probe.Buf","kind":"variable","change":"add","signature":"[N]byte"}]}]}`), &output, &diagnostics)
			require.Equal(t, 0, code, output.String())
			var proposal plan.Result
			require.NoError(t, json.Unmarshal(output.Bytes(), &proposal))
			require.Len(t, proposal.Requests["layout"].Rules, 1)
			assert.Equal(t, fmt.Sprintf("[%d]byte", test.size), proposal.Requests["layout"].Rules[0].Signature)
			request, err := json.Marshal(proposal.Requests["layout"])
			require.NoError(t, err)
			require.NoError(t, filesystem.WriteFile(filepath.Join(root, "app.go"), []byte(fmt.Sprintf("%svar Buf [N]byte\n", source)), 0600))
			output.Reset()
			code = Run(context.Background(), append([]string{"check"}, options...), bytes.NewReader(request), &output, &diagnostics)
			require.Equal(t, 0, code, output.String())
			var result check.Result
			require.NoError(t, json.Unmarshal(output.Bytes(), &result))
			assert.Equal(t, check.Pass, result.Status)
		})
	}
}
