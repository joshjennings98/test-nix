// Package analysis extracts a typed, evidence-bearing Go graph.
package analysis

import (
	"go/types"
	"maps"
	"slices"

	"golang.org/x/tools/go/packages"
)

type Location struct {
	File    string `json:"file"`
	Line    int    `json:"line"`
	Column  int    `json:"column,omitempty"`
	EndLine int    `json:"end_line,omitempty"`
}

type Node struct {
	External  bool     `json:"external,omitempty"`
	ID        string   `json:"id"`
	Kind      string   `json:"kind"`
	Signature string   `json:"signature,omitempty"`
	Location  Location `json:"location"`
}

type Edge struct {
	From     string   `json:"from"`
	To       string   `json:"to"`
	Kind     string   `json:"kind"`
	Location Location `json:"location"`
}

type Gap struct {
	From     string   `json:"from"`
	Reason   string   `json:"reason"`
	Location Location `json:"location"`
}

type Graph struct {
	TypesSizes     types.Sizes                  `json:"-"`
	SourcePackages map[string]*packages.Package `json:"-"`
	Nodes          map[string]Node              `json:"nodes"`
	Edges          []Edge                       `json:"edges"`
	Gaps           []Gap                        `json:"gaps"`
	Errors         []string                     `json:"errors,omitempty"`
}

func New() *Graph { return &Graph{Nodes: map[string]Node{}} }

// Path returns a shortest witness using a deterministic breadth-first search.
func (g *Graph) Path(from, to string, possible bool) (path []string) {
	queue := []string{from}
	parents := map[string]string{from: ""}
	for len(queue) > 0 {
		current := queue[0]
		queue = queue[1:]
		if g.Nodes[current].External {
			continue
		}

		neighbours := map[string]bool{}

		for _, edge := range g.Edges {
			if edge.From != current {
				continue
			}

			if edge.Kind != "direct_call" && !(possible && edge.Kind == "possible_call") {
				continue
			}

			neighbours[edge.To] = true
		}

		for _, next := range slices.Sorted(maps.Keys(neighbours)) {
			if next == to {
				path = []string{to}
				for at := current; at != ""; at = parents[at] {
					path = append(path, at)
				}

				slices.Reverse(path)
				return
			}

			if _, seen := parents[next]; seen {
				continue
			}

			parents[next] = current
			queue = append(queue, next)
		}
	}

	return
}

func (g *Graph) RelevantGap(from string) bool {
	if len(g.Errors) > 0 {
		return true
	}

	for _, gap := range g.Gaps {
		if g.Nodes[gap.From].External {
			continue
		}

		if gap.From == from || len(g.Path(from, gap.From, true)) > 0 {
			return true
		}
	}

	return false
}

// RelationshipGap limits direct relationships to uncertainty at their own call
// site. Reachability can depend on unresolved dispatch further down a repo path.
func (g *Graph) RelationshipGap(from, kind string) bool {
	if len(g.Errors) > 0 {
		return true
	}

	if kind == "reaches" || kind == "forbid_path" {
		return g.RelevantGap(from)
	}

	if kind != "direct_call" && kind != "forbid_call" && kind != "possible_call" {
		return false
	}

	return slices.ContainsFunc(g.Gaps, func(gap Gap) bool {
		return gap.From == from && !g.Nodes[from].External
	})
}
