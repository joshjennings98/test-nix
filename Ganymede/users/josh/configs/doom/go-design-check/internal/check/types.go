// Package check evaluates explicit requirements against an observed Go graph.
package check

import "go-design-check/internal/analysis"

type Status string

const (
	Pass    Status = "PASS"
	Fail    Status = "FAIL"
	Unknown Status = "UNKNOWN"
	Error   Status = "ERROR"
)

type Rule struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"`
	From      string `json:"from,omitempty"`
	To        string `json:"to,omitempty"`
	Symbol    string `json:"symbol,omitempty"`
	Signature string `json:"signature,omitempty"`
}

type Request struct {
	Rules []Rule `json:"rules"`
}

type Finding struct {
	Review    *ReviewContext      `json:"review,omitempty"`
	ID        string              `json:"id"`
	Status    Status              `json:"status"`
	Message   string              `json:"message"`
	Witness   []string            `json:"witness,omitempty"`
	Locations []analysis.Location `json:"locations,omitempty"`
	Gaps      []analysis.Gap      `json:"gaps,omitempty"`
}

type ReviewContext struct {
	Kind        string          `json:"kind"`
	Requirement Rule            `json:"requirement"`
	Caller      analysis.Node   `json:"caller"`
	Target      analysis.Node   `json:"target"`
	Candidates  []analysis.Node `json:"candidates,omitempty"`
	Guidance    []string        `json:"guidance"`
	Diagnostics []string        `json:"diagnostics,omitempty"`
}

type Result struct {
	Status   Status    `json:"status"`
	Findings []Finding `json:"findings"`
	Errors   []string  `json:"analysis_errors,omitempty"`
}
