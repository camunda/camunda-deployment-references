package main

import (
	"encoding/json"
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

func TestInlineCommentHandlesNulls(t *testing.T) {
	// `line` is null on an outdated comment, `in_reply_to_id` on a thread
	// opener. Unmarshalling null into a non-pointer int is a silent no-op, so
	// both would render as 0 and read as "line 0" / "reply to 0".
	var got []inlineComment
	raw := `[{"id":1,"path":"a.go","line":null,"in_reply_to_id":null},
	         {"id":2,"path":"b.go","line":7,"in_reply_to_id":9}]`
	if err := json.Unmarshal([]byte(raw), &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got[0].location() != "a.go:(outdated)" {
		t.Errorf("null line rendered as %q", got[0].location())
	}
	if got[0].thread() != "new thread" {
		t.Errorf("null in_reply_to_id rendered as %q", got[0].thread())
	}
	if got[1].location() != "b.go:7" {
		t.Errorf("line rendered as %q", got[1].location())
	}
	if got[1].thread() != "reply to 9" {
		t.Errorf("in_reply_to_id rendered as %q", got[1].thread())
	}
}

func TestPRLabelsDecodesNamesWithSpaces(t *testing.T) {
	// Real labels in this repo contain spaces ("backport stable/8.9",
	// "no merge"). A whitespace split would shred them, and the skip_all gate
	// reads this list.
	var payload struct {
		Labels []struct {
			Name string `json:"name"`
		} `json:"labels"`
	}
	raw := `{"labels":[{"name":"backport stable/8.9"},{"name":"skip_all"},{"name":"no merge"}]}`
	if err := json.Unmarshal([]byte(raw), &payload); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(payload.Labels) != 3 {
		t.Fatalf("got %d labels, want 3", len(payload.Labels))
	}
	if payload.Labels[0].Name != "backport stable/8.9" {
		t.Errorf("label with spaces decoded as %q", payload.Labels[0].Name)
	}
}
