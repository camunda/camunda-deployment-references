// Review-loop orchestration: the stateful `gh` choreography that used to live as
// copy-pasteable bash inside .github/skills/review-loop/SKILL.md.
//
// Two things belong in code rather than in a markdown fence:
//
//   - the pure string logic (PR-reference parsing, ` [ready]` tag add/strip),
//     because "idempotent" is a claim a test can check and a shell snippet cannot;
//   - the `skip_all` lifecycle, because a stranded `skip_all` silences the PR's
//     own CI. `review ready` refuses to tag a PR that still carries the label, so
//     the invariant is enforced instead of restated in prose.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
)

// readySuffix is the exact marker AGENTS.md defines: one leading space, appended
// to the end of the title, never a prefix.
const readySuffix = " [ready]"

const skipAllLabel = "skip_all"

// ─────────────────────────────────────────────────────────────────────────────
// pure helpers (unit-tested in review_test.go)
// ─────────────────────────────────────────────────────────────────────────────

// prRefPattern strips a `.../pull/<n>` URL prefix and any trailing path/query
// fragment, so both `123`, `#123` and a full PR URL reduce to the number.
var prRefPattern = regexp.MustCompile(`^(?:.*/pull/)?#?(\d+)(?:[/?#].*)?$`)

// parsePRRefs turns user-supplied PR references into numbers. Anything that is
// not a bare number after normalisation (a version tag like `v8.7.0`, a branch
// name) is rejected and reported, never silently truncated into a stray PR.
func parsePRRefs(args []string) (prs []int, rejected []string) {
	for _, a := range args {
		m := prRefPattern.FindStringSubmatch(strings.TrimSpace(a))
		if m == nil {
			rejected = append(rejected, a)
			continue
		}
		n, err := strconv.Atoi(m[1])
		if err != nil || n <= 0 {
			rejected = append(rejected, a)
			continue
		}
		prs = append(prs, n)
	}
	return dedupe(prs), rejected
}

func dedupe(in []int) []int {
	if len(in) == 0 {
		return nil
	}
	seen := map[int]bool{}
	out := make([]int, 0, len(in))
	for _, n := range in {
		if !seen[n] {
			seen[n] = true
			out = append(out, n)
		}
	}
	sort.Ints(out)
	return out
}

// withReadyTag appends the ready marker at most once.
func withReadyTag(title string) string {
	if strings.HasSuffix(title, readySuffix) {
		return title
	}
	return title + readySuffix
}

// withoutReadyTag removes a trailing ready marker if present. Applying it to an
// untagged title is a no-op.
func withoutReadyTag(title string) string {
	return strings.TrimSuffix(title, readySuffix)
}

// ─────────────────────────────────────────────────────────────────────────────
// gh-backed helpers
// ─────────────────────────────────────────────────────────────────────────────

func currentRepo() (string, error) {
	out, err := gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func currentBranchPR() (int, error) {
	out, err := gh("pr", "view", "--json", "number", "-q", ".number")
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(strings.TrimSpace(string(out)))
}

// backportsOf finds the sibling backport PRs of one seed. The backport action
// writes "Backport of #<n>" into each backport body, so the body is the reliable
// signal; a title search would match unrelated backports repo-wide.
func backportsOf(repo string, seed int) ([]int, error) {
	out, err := gh("pr", "list", "--repo", repo, "--state", "open",
		"--search", fmt.Sprintf("in:body \"Backport of #%d\"", seed),
		"--json", "number", "-q", ".[].number")
	if err != nil {
		return nil, err
	}
	var prs []int
	for _, l := range strings.Fields(string(out)) {
		if n, err := strconv.Atoi(l); err == nil {
			prs = append(prs, n)
		}
	}
	return prs, nil
}

// resolvePRSet expands the seeds with their open backports. With no args it
// falls back to the pull request of the current branch.
func resolvePRSet(repo string, args []string) ([]int, error) {
	seeds, rejected := parsePRRefs(args)
	for _, r := range rejected {
		fmt.Fprintf(os.Stderr, "warning: ignoring unrecognised PR argument: %s\n", r)
	}
	if len(args) == 0 {
		n, err := currentBranchPR()
		if err != nil {
			return nil, fmt.Errorf("no PR argument given and no PR for the current branch: %w", err)
		}
		seeds = []int{n}
	}
	if len(seeds) == 0 {
		return nil, fmt.Errorf("no valid PR number resolved from the arguments")
	}
	all := append([]int(nil), seeds...)
	for _, s := range seeds {
		bp, err := backportsOf(repo, s)
		if err != nil {
			return nil, err
		}
		all = append(all, bp...)
	}
	return dedupe(all), nil
}

func prTitle(repo string, pr int) (string, error) {
	out, err := gh("pr", "view", strconv.Itoa(pr), "--repo", repo, "--json", "title", "-q", ".title")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// prLabels returns the PR's label names. It decodes JSON rather than splitting
// text: label names contain spaces in this repo ("backport stable/8.9",
// "no merge"), so any whitespace split would shred them into fragments.
func prLabels(repo string, pr int) ([]string, error) {
	out, err := gh("pr", "view", strconv.Itoa(pr), "--repo", repo, "--json", "labels")
	if err != nil {
		return nil, err
	}
	var payload struct {
		Labels []struct {
			Name string `json:"name"`
		} `json:"labels"`
	}
	if err := json.Unmarshal(out, &payload); err != nil {
		return nil, err
	}
	names := make([]string, 0, len(payload.Labels))
	for _, l := range payload.Labels {
		names = append(names, l.Name)
	}
	return names, nil
}

func prHeadRef(repo string, pr int) (string, error) {
	out, err := gh("pr", "view", strconv.Itoa(pr), "--repo", repo, "--json", "headRefName", "-q", ".headRefName")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func setTitle(repo string, pr int, title string) error {
	_, err := gh("pr", "edit", strconv.Itoa(pr), "--repo", repo, "--title", title)
	return err
}

// runIDs lists this PR's runs on its own head branch filtered by status.
func runIDs(repo, headRef, status string, limit int) ([]string, error) {
	out, err := gh("run", "list", "--repo", repo, "--branch", headRef,
		"--status", status, "--limit", strconv.Itoa(limit),
		"--json", "databaseId", "-q", ".[].databaseId")
	if err != nil {
		return nil, err
	}
	return strings.Fields(string(out)), nil
}

// ─────────────────────────────────────────────────────────────────────────────
// commands
// ─────────────────────────────────────────────────────────────────────────────

func reviewCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "review",
		Short: "Review-loop orchestration: prs / pause / resume / state / findings / ready",
	}
	cmd.AddCommand(reviewPRsCmd(), reviewPauseCmd(), reviewResumeCmd(),
		reviewStateCmd(), reviewFindingsCmd(), reviewReadyCmd())
	return cmd
}

// withPRSet resolves the repo and the PR set once, then hands them to fn.
func withPRSet(args []string, fn func(repo string, prs []int) error) error {
	repo, err := currentRepo()
	if err != nil {
		return err
	}
	prs, err := resolvePRSet(repo, args)
	if err != nil {
		return err
	}
	return fn(repo, prs)
}

func reviewPRsCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "prs [pr-number|pr-url ...]",
		Short: "Resolve the PR set to drive (seeds + their open backports)",
		RunE: func(_ *cobra.Command, args []string) error {
			return withPRSet(args, func(_ string, prs []int) error {
				for _, n := range prs {
					fmt.Println(n)
				}
				return nil
			})
		},
	}
}

func reviewPauseCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "pause [pr-number|pr-url ...]",
		Short: "Add skip_all, strip any ` [ready]` tag, cancel in-progress runs",
		RunE: func(_ *cobra.Command, args []string) error {
			return withPRSet(args, func(repo string, prs []int) error {
				for _, n := range prs {
					if _, err := gh("pr", "edit", strconv.Itoa(n), "--repo", repo,
						"--add-label", skipAllLabel); err != nil {
						return err
					}
					// Pausing means the PR is no longer ready.
					title, err := prTitle(repo, n)
					if err != nil {
						return err
					}
					if stripped := withoutReadyTag(title); stripped != title {
						if err := setTitle(repo, n, stripped); err != nil {
							return err
						}
					}
					// Free the runners.
					headRef, err := prHeadRef(repo, n)
					if err != nil {
						return err
					}
					ids, err := runIDs(repo, headRef, "in_progress", 50)
					if err != nil {
						return err
					}
					for _, id := range ids {
						if _, err := gh("run", "cancel", "--repo", repo, id); err != nil {
							fmt.Fprintf(os.Stderr, "warning: could not cancel run %s: %v\n", id, err)
						}
					}
					fmt.Printf("PR #%d paused (%s added, %d run(s) cancelled)\n", n, skipAllLabel, len(ids))
				}
				return nil
			})
		},
	}
}

func reviewResumeCmd() *cobra.Command {
	var rerun bool
	cmd := &cobra.Command{
		Use:   "resume [pr-number|pr-url ...]",
		Short: "Remove skip_all and (optionally) re-run the latest completed run",
		Long: "Removing the label does not re-trigger anything on its own: `unlabeled` is not\n" +
			"a workflow trigger. Use --rerun, or push a commit.",
		RunE: func(_ *cobra.Command, args []string) error {
			return withPRSet(args, func(repo string, prs []int) error {
				for _, n := range prs {
					if _, err := gh("pr", "edit", strconv.Itoa(n), "--repo", repo,
						"--remove-label", skipAllLabel); err != nil {
						return err
					}
					fmt.Printf("PR #%d resumed (%s removed)\n", n, skipAllLabel)
					if !rerun {
						continue
					}
					headRef, err := prHeadRef(repo, n)
					if err != nil {
						return err
					}
					// Only a completed run can be re-run; a full re-run is wanted
					// because the heavy jobs were skipped, not failed.
					ids, err := runIDs(repo, headRef, "completed", 1)
					if err != nil {
						return err
					}
					for _, id := range ids {
						if _, err := gh("run", "rerun", "--repo", repo, id); err != nil {
							return err
						}
						fmt.Printf("PR #%d: re-ran run %s\n", n, id)
					}
				}
				return nil
			})
		},
	}
	cmd.Flags().BoolVar(&rerun, "rerun", false, "re-run the latest completed run of each PR")
	return cmd
}

type reviewEntry struct {
	State string `json:"state"`
	Body  string `json:"body"`
	User  struct {
		Login string `json:"login"`
	} `json:"user"`
}

func isCopilot(login string) bool {
	return strings.HasPrefix(strings.ToLower(login), "copilot")
}

// copilotReviews returns Copilot's reviews on a PR, oldest first.
func copilotReviews(repo string, pr int) ([]reviewEntry, error) {
	out, err := gh("api", fmt.Sprintf("/repos/%s/pulls/%d/reviews", repo, pr), "--paginate")
	if err != nil {
		return nil, err
	}
	var all []reviewEntry
	if err := json.Unmarshal(out, &all); err != nil {
		return nil, err
	}
	var mine []reviewEntry
	for _, r := range all {
		if isCopilot(r.User.Login) {
			mine = append(mine, r)
		}
	}
	return mine, nil
}

func reviewStateCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "state [pr-number|pr-url ...]",
		Short: "Print the latest Copilot review state per PR (NONE if it has not landed)",
		RunE: func(_ *cobra.Command, args []string) error {
			return withPRSet(args, func(repo string, prs []int) error {
				for _, n := range prs {
					rs, err := copilotReviews(repo, n)
					if err != nil {
						return err
					}
					state := "NONE"
					if len(rs) > 0 {
						state = rs[len(rs)-1].State
					}
					fmt.Printf("PR #%d %s\n", n, state)
				}
				return nil
			})
		},
	}
}

// inlineComment mirrors one review comment. `line` is null on an outdated
// comment and `in_reply_to_id` is null on a thread opener; both are pointers so
// "absent" stays distinguishable from a genuine 0 rather than silently
// rendering as `path:0`.
type inlineComment struct {
	ID        int64  `json:"id"`
	Path      string `json:"path"`
	Line      *int   `json:"line"`
	Body      string `json:"body"`
	InReplyTo *int64 `json:"in_reply_to_id"`
	User      struct {
		Login string `json:"login"`
	} `json:"user"`
}

// location renders the comment's anchor, flagging the outdated case explicitly.
func (c inlineComment) location() string {
	if c.Line == nil {
		return c.Path + ":(outdated)"
	}
	return fmt.Sprintf("%s:%d", c.Path, *c.Line)
}

// thread reports whether the comment opens a thread or replies to one.
func (c inlineComment) thread() string {
	if c.InReplyTo == nil {
		return "new thread"
	}
	return fmt.Sprintf("reply to %d", *c.InReplyTo)
}

func reviewFindingsCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "findings [pr-number|pr-url ...]",
		Short: "Print Copilot's review summaries and inline findings per PR",
		RunE: func(_ *cobra.Command, args []string) error {
			return withPRSet(args, func(repo string, prs []int) error {
				for _, n := range prs {
					fmt.Printf("===== PR #%d =====\n", n)
					rs, err := copilotReviews(repo, n)
					if err != nil {
						return err
					}
					for _, r := range rs {
						fmt.Printf("[summary] %s\n%s\n", r.State, r.Body)
					}
					out, err := gh("api", fmt.Sprintf("/repos/%s/pulls/%d/comments", repo, n), "--paginate")
					if err != nil {
						return err
					}
					var all []inlineComment
					if err := json.Unmarshal(out, &all); err != nil {
						return err
					}
					for _, c := range all {
						if !isCopilot(c.User.Login) {
							continue
						}
						fmt.Printf("[finding id=%d] %s (%s)\n%s\n",
							c.ID, c.location(), c.thread(), c.Body)
					}
				}
				return nil
			})
		},
	}
}

type checkEntry struct {
	Name  string `json:"name"`
	State string `json:"state"`
}

// notGreen returns the checks that block readiness. SUCCESS, SKIPPED and
// NEUTRAL do not block: a skipped heavy suite is the normal state for a PR that
// cannot affect it. Everything else — failing, pending, queued — does.
func notGreen(checks []checkEntry) []checkEntry {
	var bad []checkEntry
	for _, c := range checks {
		switch strings.ToUpper(c.State) {
		case "SUCCESS", "SKIPPED", "NEUTRAL":
		default:
			bad = append(bad, c)
		}
	}
	return bad
}

func reviewReadyCmd() *cobra.Command {
	var force bool
	cmd := &cobra.Command{
		Use:   "ready [pr-number|pr-url ...]",
		Short: "Append the exact ` [ready]` tag, once, after verifying the PR really is ready",
		Long: "Refuses while the PR still carries " + skipAllLabel + " (its CI is silenced) or\n" +
			"while any check is failing or pending. Appending is idempotent.\n\n" +
			"This command never merges: tagging is where the agent stops.",
		RunE: func(_ *cobra.Command, args []string) error {
			return withPRSet(args, func(repo string, prs []int) error {
				for _, n := range prs {
					labels, err := prLabels(repo, n)
					if err != nil {
						return err
					}
					for _, l := range labels {
						if l == skipAllLabel && !force {
							return fmt.Errorf("PR #%d still carries %s: its CI is silenced, so it is not ready (run `review resume` first)", n, skipAllLabel)
						}
					}
					// A checks query that fails is not evidence of green. Refuse,
					// rather than tagging on the strength of an error.
					out, err := gh("pr", "checks", strconv.Itoa(n), "--repo", repo, "--json", "name,state")
					if err != nil {
						if !force {
							return fmt.Errorf("PR #%d: cannot read the checks, so readiness is unproven: %w", n, err)
						}
					} else {
						var checks []checkEntry
						if err := json.Unmarshal(out, &checks); err != nil {
							return err
						}
						if bad := notGreen(checks); len(bad) > 0 && !force {
							names := make([]string, 0, len(bad))
							for _, c := range bad {
								names = append(names, fmt.Sprintf("%s=%s", c.Name, c.State))
							}
							return fmt.Errorf("PR #%d is not green: %s", n, strings.Join(names, ", "))
						}
					}
					title, err := prTitle(repo, n)
					if err != nil {
						return err
					}
					tagged := withReadyTag(title)
					if tagged == title {
						fmt.Printf("PR #%d already tagged\n", n)
						continue
					}
					if err := setTitle(repo, n, tagged); err != nil {
						return err
					}
					fmt.Printf("PR #%d tagged ready\n", n)
				}
				return nil
			})
		},
	}
	cmd.Flags().BoolVar(&force, "force", false, "tag even if skip_all is present or checks are not green")
	return cmd
}
