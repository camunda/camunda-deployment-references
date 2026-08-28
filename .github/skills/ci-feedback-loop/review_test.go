package main

import (
	"reflect"
	"testing"
)

func TestParsePRRefs(t *testing.T) {
	cases := []struct {
		name     string
		in       []string
		want     []int
		rejected []string
	}{
		{"bare number", []string{"123"}, []int{123}, nil},
		{"hash prefix", []string{"#123"}, []int{123}, nil},
		{"pull url", []string{"https://github.com/o/r/pull/123"}, []int{123}, nil},
		{"pull url with files suffix", []string{"https://github.com/o/r/pull/123/files"}, []int{123}, nil},
		{"pull url with query", []string{"https://github.com/o/r/pull/123?w=1"}, []int{123}, nil},
		{"sorted and deduped", []string{"9", "3", "9"}, []int{3, 9}, nil},
		// The whole point of the guard: a version tag must never be truncated
		// into a stray PR number.
		{"version tag rejected", []string{"v8.7.0"}, nil, []string{"v8.7.0"}},
		{"branch name rejected", []string{"release-1.2.3"}, nil, []string{"release-1.2.3"}},
		{"empty rejected", []string{""}, nil, []string{""}},
		{"zero rejected", []string{"0"}, nil, []string{"0"}},
		{"mixed", []string{"12", "nope"}, []int{12}, []string{"nope"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, rejected := parsePRRefs(c.in)
			if !reflect.DeepEqual(got, c.want) {
				t.Errorf("parsePRRefs(%q) = %v, want %v", c.in, got, c.want)
			}
			if !reflect.DeepEqual(rejected, c.rejected) {
				t.Errorf("parsePRRefs(%q) rejected = %v, want %v", c.in, rejected, c.rejected)
			}
		})
	}
}

func TestReadyTagIsIdempotent(t *testing.T) {
	const base = "fix(ci): do the thing"
	tagged := withReadyTag(base)
	if tagged != base+" [ready]" {
		t.Fatalf("withReadyTag(%q) = %q", base, tagged)
	}
	if again := withReadyTag(tagged); again != tagged {
		t.Errorf("withReadyTag is not idempotent: %q -> %q", tagged, again)
	}
	if got := withoutReadyTag(tagged); got != base {
		t.Errorf("withoutReadyTag(%q) = %q, want %q", tagged, got, base)
	}
	if got := withoutReadyTag(base); got != base {
		t.Errorf("withoutReadyTag on an untagged title changed it: %q", got)
	}
}

func TestReadyTagIsASuffixNotAPrefix(t *testing.T) {
	// A title that merely mentions the marker somewhere else must not be
	// treated as already tagged.
	const odd = "fix: mention [ready] in the middle"
	got := withReadyTag(odd)
	if got != odd+" [ready]" {
		t.Errorf("withReadyTag(%q) = %q", odd, got)
	}
	if withoutReadyTag(odd) != odd {
		t.Errorf("withoutReadyTag stripped a non-suffix occurrence")
	}
}

func TestNotGreen(t *testing.T) {
	checks := []checkEntry{
		{Name: "lint", State: "SUCCESS"},
		{Name: "heavy", State: "SKIPPED"},
		{Name: "flaky", State: "FAILURE"},
		{Name: "slow", State: "PENDING"},
		{Name: "info", State: "NEUTRAL"},
	}
	bad := notGreen(checks)
	if len(bad) != 2 {
		t.Fatalf("notGreen returned %d entries: %v", len(bad), bad)
	}
	if bad[0].Name != "flaky" || bad[1].Name != "slow" {
		t.Errorf("notGreen picked the wrong checks: %v", bad)
	}
	if got := notGreen(nil); got != nil {
		t.Errorf("notGreen(nil) = %v, want nil", got)
	}
}

func TestIsCopilot(t *testing.T) {
	// The three spellings the GitHub APIs actually return.
	for _, login := range []string{"Copilot", "copilot-pull-request-reviewer", "copilot-pull-request-reviewer[bot]"} {
		if !isCopilot(login) {
			t.Errorf("isCopilot(%q) = false", login)
		}
	}
	for _, login := range []string{"leiicamundi", "renovate[bot]", ""} {
		if isCopilot(login) {
			t.Errorf("isCopilot(%q) = true", login)
		}
	}
}
