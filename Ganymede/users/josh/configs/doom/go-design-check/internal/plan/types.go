// Package plan validates authored intent without requiring its implementation.
package plan

import "go-design-check/internal/check"

type Declaration struct {
	ID      string            `json:"-"`
	Symbol  string            `json:"symbol"`
	Kind    string            `json:"kind"`
	Change  string            `json:"change"`
	Before  *string           `json:"-"`
	After   *string           `json:"signature,omitempty"`
	Imports map[string]string `json:"imports,omitempty"`
}

type Node struct {
	Symbol      string `json:"symbol"`
	Relation    string `json:"relation,omitempty"`
	Change      string `json:"change,omitempty"`
	Description string `json:"description,omitempty"`
	Children    []Node `json:"children,omitempty"`
}

type Graph struct {
	ID           string        `json:"id"`
	Declarations []Declaration `json:"declarations,omitempty"`
	Roots        []Node        `json:"roots"`
}

type Document struct {
	Graphs []Graph `json:"graphs"`
}

type Result struct {
	Status   check.Status             `json:"status"`
	Findings []check.Finding          `json:"findings"`
	Requests map[string]check.Request `json:"requests"`
}

type design struct {
	Declarations []Declaration
}
