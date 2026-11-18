package analysis

import (
	"fmt"

	"github.com/ARM-software/golang-utils/utils/field"
)

func buildEnvironmentOverrides(opts Options) (env []string) {
	env = []string{fmt.Sprintf("GOOS=%s", opts.GOOS), fmt.Sprintf("GOARCH=%s", opts.GOARCH), "GOPACKAGESDRIVER=off"}
	if opts.CGOEnabled != nil {
		value := "0"
		if field.Optional(opts.CGOEnabled, false) {
			value = "1"
		}

		env = append(env, fmt.Sprintf("CGO_ENABLED=%s", value))
	}

	return
}
