// Package app provides the JSON command-line protocol used by editor integrations.
package app

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
	"github.com/ARM-software/golang-utils/utils/field"
	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/ARM-software/golang-utils/utils/parallelisation"

	"go-design-check/internal/analysis"
	"go-design-check/internal/check"
	"go-design-check/internal/plan"
)

const usage = `go-design-check <validate|check> [flags]

check:   evaluate a JSON request from stdin (or --request FILE)
validate: validate graph proposals against the selected baseline; compile checks

Analysis flags: --root DIR --packages ./... --tags TAGS --goos OS --goarch ARCH
                --cgo auto|on|off --timeout 2m
Exit codes: 0 complete/PASS, 3 FAIL, 4 UNKNOWN, 5 ERROR.
All commands emit JSON; help goes to stderr.
`

func Run(ctx context.Context, args []string, input io.Reader, output, diagnostics io.Writer) (code int) {
	value, status, err := execute(ctx, args, input, diagnostics)
	if err != nil {
		value = struct {
			Status check.Status `json:"status"`
			Error  string       `json:"error"`
		}{check.Error, err.Error()}
		status = check.Error
	}

	if value != nil {
		encoder := json.NewEncoder(output)
		encoder.SetIndent("", "  ")
		if subErr := encoder.Encode(value); subErr != nil {
			fmt.Fprintln(diagnostics, subErr)
			return 5
		}
	}

	switch status {
	case check.Fail:
		return 3
	case check.Unknown:
		return 4
	case check.Error:
		return 5
	}

	return
}

func execute(ctx context.Context, args []string, input io.Reader, diagnostics io.Writer) (value any, status check.Status, err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}

	status = check.Pass
	if len(args) == 0 || args[0] == "--help" || args[0] == "help" || args[0] == "-h" {
		_, err = fmt.Fprint(diagnostics, usage)
		return
	}

	command := args[0]
	if command != "check" && command != "validate" {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "unknown command %q", command)
		return
	}

	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(diagnostics)
	var opts analysis.Options
	var patterns, tags, cgo, requestPath string
	var timeout time.Duration
	flags.DurationVar(&timeout, "timeout", 2*time.Minute, "analysis timeout")
	flags.StringVar(&opts.Root, "root", ".", "Go module or workspace directory")
	flags.StringVar(&patterns, "packages", "./...", "comma-separated Go package patterns")
	flags.StringVar(&tags, "tags", "", "comma-separated build tags")
	flags.StringVar(&opts.GOOS, "goos", "", "target OS (default: host)")
	flags.StringVar(&opts.GOARCH, "goarch", "", "target architecture (default: host)")
	flags.StringVar(&cgo, "cgo", "auto", "auto, on or off")
	flags.StringVar(&requestPath, "request", "-", "JSON request path, or - for stdin")

	if err = flags.Parse(args[1:]); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			err = nil
		}

		return
	}

	if flags.NArg() != 0 || timeout <= 0 {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "unexpected positional arguments or non-positive timeout")
		return
	}

	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	switch cgo {
	case "auto":
	case "on", "off":
		opts.CGOEnabled = field.ToOptional(cgo == "on")
	default:
		err = commonerrors.Newf(commonerrors.ErrInvalid, "--cgo must be auto, on or off")
		return
	}

	opts.Root, err = filepath.Abs(opts.Root)
	if err != nil {
		return
	}

	opts.Patterns = splitList(patterns)
	opts.Tags = splitList(tags)
	if len(opts.Patterns) == 0 {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "--packages must not be empty")
		return
	}

	var request check.Request
	var document plan.Document
	if command == "validate" {
		if err = readJSON(requestPath, input, &document); err != nil {
			return
		}
	}
	if command == "check" {
		if err = readJSON(requestPath, input, &request); err != nil {
			return
		}

		if err = request.Validate(); err != nil {
			return
		}
	}

	graph, err := analysis.Load(ctx, opts)
	if err != nil {
		return
	}

	if command == "validate" {
		result, subErr := plan.Validate(ctx, document, graph)
		value, status, err = result, result.Status, subErr
		return
	}

	result, err := check.Evaluate(ctx, request, graph)
	value, status = result, result.Status
	return
}

func readJSON(path string, input io.Reader, target any) (err error) {
	if path != "-" {
		data, subErr := filesystem.ReadFile(path)
		if subErr != nil {
			err = subErr
			return
		}

		input = bytes.NewReader(data)
	}

	decoder := json.NewDecoder(input)
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(target); err != nil {
		return
	}

	var extra any
	if subErr := decoder.Decode(&extra); !errors.Is(subErr, io.EOF) {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "expected exactly one JSON value")
	}

	return
}

func splitList(value string) (items []string) {
	for _, item := range strings.Split(value, ",") {
		if item = strings.TrimSpace(item); item != "" {
			items = append(items, item)
		}
	}

	slices.Sort(items)
	items = slices.Compact(items)
	return
}
