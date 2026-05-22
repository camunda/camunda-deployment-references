// Command ci-feedback is a small Go CLI that wraps the `gh` CLI to support
// a debug feedback loop on GitHub Actions runs (list runs, summarize failures,
// fetch failed-job logs, list/download artifacts).
//
// All downloaded data lands under <repo-root>/debug/ci/<run_id>/ which is
// already covered by the repository .gitignore (debug/**).
package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

const debugRoot = "debug/ci"

func main() {
	root := &cobra.Command{
		Use:   "ci-feedback",
		Short: "Feedback loop for GitHub Actions: locate / summarize / logs / artifacts",
	}
	root.AddCommand(locateCmd(), summarizeCmd(), logsCmd(), artifactsCmd())
	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// gh wrapper helpers
// ─────────────────────────────────────────────────────────────────────────────

func gh(args ...string) ([]byte, error) {
	cmd := exec.Command("gh", args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("gh %s: %w\n%s", strings.Join(args, " "), err, stderr.String())
	}
	return stdout.Bytes(), nil
}

func currentBranch() (string, error) {
	out, err := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func ensureDebugDir(runID string) (string, error) {
	dir := filepath.Join(debugRoot, runID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// locate
// ─────────────────────────────────────────────────────────────────────────────

type runEntry struct {
	DatabaseID   int64  `json:"databaseId"`
	DisplayTitle string `json:"displayTitle"`
	WorkflowName string `json:"workflowName"`
	Status       string `json:"status"`
	Conclusion   string `json:"conclusion"`
	HeadSha      string `json:"headSha"`
	URL          string `json:"url"`
}

func listRuns(branch string, limit int) ([]runEntry, error) {
	out, err := gh("run", "list", "--branch", branch, "--limit", fmt.Sprint(limit),
		"--json", "databaseId,displayTitle,workflowName,status,conclusion,headSha,url")
	if err != nil {
		return nil, err
	}
	var runs []runEntry
	if err := json.Unmarshal(out, &runs); err != nil {
		return nil, err
	}
	return runs, nil
}

func locateCmd() *cobra.Command {
	var (
		latest      bool
		wait        bool
		waitTimeout int
		limit       int
	)
	cmd := &cobra.Command{
		Use:   "locate [run-id]",
		Short: "List runs for the current branch, resolve the latest, or wait on one",
		Long: `List runs for the current branch, resolve the latest, or wait on one.

By default, locate is NON-blocking: it returns immediately even when runs are
in progress. Pass --wait to block until every queued/in-progress run on the
branch reaches a terminal state, with a hard timeout (default 30 min) so the
calling agent can never hang indefinitely.`,
		Args: cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			branch, err := currentBranch()
			if err != nil {
				return err
			}

			// Explicit run id: optionally wait on just this run, then print.
			if len(args) == 1 {
				runID := args[0]
				if wait {
					if err := waitForSingleRun(runID, waitTimeout); err != nil {
						fmt.Fprintf(os.Stderr, "wait: %v (continuing)\n", err)
					}
				}
				fmt.Printf("RUN_ID=%s\n", runID)
				return nil
			}

			if wait {
				if err := waitForBranchRuns(branch, waitTimeout); err != nil {
					fmt.Fprintf(os.Stderr, "wait: %v (continuing)\n", err)
				}
			}

			runs, err := listRuns(branch, limit)
			if err != nil {
				return err
			}
			if len(runs) == 0 {
				return fmt.Errorf("no runs found for branch %s", branch)
			}

			if latest {
				fmt.Printf("RUN_ID=%d\n", runs[0].DatabaseID)
				return nil
			}

			fmt.Printf("Recent runs for branch: %s\n\n", branch)
			fmt.Printf("%-12s  %-10s  %-12s  %-50s  %s\n", "RUN_ID", "STATUS", "CONCLUSION", "WORKFLOW", "TITLE")
			pending := 0
			for _, r := range runs {
				if r.Status != "completed" {
					pending++
				}
				fmt.Printf("%-12d  %-10s  %-12s  %-50s  %s\n",
					r.DatabaseID, r.Status, orDash(r.Conclusion), trunc(r.WorkflowName, 50), r.DisplayTitle)
			}
			fmt.Println()
			if pending > 0 {
				fmt.Printf("⏳ %d run(s) still in progress. Re-run with --wait to block, or check back later.\n", pending)
			}
			fmt.Println("Next: ci-feedback summarize <RUN_ID>")
			return nil
		},
	}
	cmd.Flags().BoolVar(&latest, "latest", false, "print only the most recent RUN_ID")
	cmd.Flags().BoolVar(&wait, "wait", false, "block until every in-progress run on the branch finishes")
	cmd.Flags().IntVar(&waitTimeout, "wait-timeout", 1800, "max seconds to wait when --wait is set (hard cap, prevents hangs)")
	cmd.Flags().IntVar(&limit, "limit", 10, "number of runs to list")
	return cmd
}

// waitForBranchRuns polls every 30s until no run on the branch is in progress,
// or the timeout is reached. Prints a single status line per poll (no streaming).
func waitForBranchRuns(branch string, timeoutSec int) error {
	deadline := time.Now().Add(time.Duration(timeoutSec) * time.Second)
	for {
		runs, err := listRuns(branch, 20)
		if err != nil {
			return err
		}
		var pending []runEntry
		for _, r := range runs {
			if r.Status != "completed" {
				pending = append(pending, r)
			}
		}
		if len(pending) == 0 {
			fmt.Fprintln(os.Stderr, "✓ all runs completed")
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("timeout after %ds with %d run(s) still pending", timeoutSec, len(pending))
		}
		names := make([]string, 0, len(pending))
		for _, r := range pending {
			names = append(names, fmt.Sprintf("%d(%s)", r.DatabaseID, r.Status))
		}
		fmt.Fprintf(os.Stderr, "[%s] %d pending: %s\n",
			time.Now().Format("15:04:05"), len(pending), strings.Join(names, " "))
		time.Sleep(30 * time.Second)
	}
}

// waitForSingleRun polls one specific run until it finishes or times out.
func waitForSingleRun(runID string, timeoutSec int) error {
	deadline := time.Now().Add(time.Duration(timeoutSec) * time.Second)
	for {
		rd, err := fetchRun(runID)
		if err != nil {
			return err
		}
		if rd.Status == "completed" {
			fmt.Fprintf(os.Stderr, "✓ run %s completed (%s)\n", runID, rd.Conclusion)
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("timeout after %ds, run still %s", timeoutSec, rd.Status)
		}
		fmt.Fprintf(os.Stderr, "[%s] run %s: %s\n", time.Now().Format("15:04:05"), runID, rd.Status)
		time.Sleep(30 * time.Second)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// summarize
// ─────────────────────────────────────────────────────────────────────────────

type stepInfo struct {
	Number     int    `json:"number"`
	Name       string `json:"name"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
}

type jobInfo struct {
	Name       string     `json:"name"`
	Status     string     `json:"status"`
	Conclusion string     `json:"conclusion"`
	URL        string     `json:"url"`
	Steps      []stepInfo `json:"steps"`
}

type runDetail struct {
	DisplayTitle string    `json:"displayTitle"`
	WorkflowName string    `json:"workflowName"`
	HeadSha      string    `json:"headSha"`
	HeadBranch   string    `json:"headBranch"`
	Conclusion   string    `json:"conclusion"`
	Status       string    `json:"status"`
	URL          string    `json:"url"`
	CreatedAt    string    `json:"createdAt"`
	Jobs         []jobInfo `json:"jobs"`
}

func fetchRun(runID string) (*runDetail, error) {
	out, err := gh("run", "view", runID,
		"--json", "displayTitle,workflowName,headSha,headBranch,conclusion,status,url,createdAt,jobs")
	if err != nil {
		return nil, err
	}
	var rd runDetail
	if err := json.Unmarshal(out, &rd); err != nil {
		return nil, err
	}
	return &rd, nil
}

func summarizeCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "summarize <run-id>",
		Short: "Print a compact summary of a run (failed jobs and steps only)",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			rd, err := fetchRun(args[0])
			if err != nil {
				return err
			}
			sha := rd.HeadSha
			if len(sha) > 8 {
				sha = sha[:8]
			}
			fmt.Printf("Workflow:  %s\n", rd.WorkflowName)
			fmt.Printf("Title:     %s\n", rd.DisplayTitle)
			fmt.Printf("Branch:    %s\n", rd.HeadBranch)
			fmt.Printf("SHA:       %s\n", sha)
			fmt.Printf("Status:    %s / %s\n", rd.Status, orDash(rd.Conclusion))
			fmt.Printf("Created:   %s\n", rd.CreatedAt)
			fmt.Printf("URL:       %s\n", rd.URL)
			fmt.Println()
			fmt.Println("Jobs (failed/cancelled only):")

			any := false
			for _, j := range rd.Jobs {
				if j.Conclusion != "failure" && j.Conclusion != "cancelled" {
					continue
				}
				any = true
				fmt.Printf("\n  ── %s [%s]\n", j.Name, j.Conclusion)
				fmt.Printf("     URL: %s\n", j.URL)
				fmt.Println("     Failing steps:")
				for _, s := range j.Steps {
					if s.Conclusion == "failure" || s.Conclusion == "cancelled" {
						fmt.Printf("       • #%d %s [%s]\n", s.Number, s.Name, s.Conclusion)
					}
				}
			}
			if !any {
				fmt.Println("  (none)")
			}
			fmt.Printf("\nNext: ci-feedback logs %s   |   ci-feedback artifacts %s\n", args[0], args[0])
			return nil
		},
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// logs
// ─────────────────────────────────────────────────────────────────────────────

func downloadLogArchive(runID, dest string) (string, error) {
	zipPath := filepath.Join(dest, "_run.zip")
	if fi, err := os.Stat(zipPath); err == nil && fi.Size() > 0 {
		return zipPath, nil
	}
	fmt.Fprintf(os.Stderr, "Downloading log archive for run %s...\n", runID)
	out, err := gh("api", fmt.Sprintf("repos/{owner}/{repo}/actions/runs/%s/logs", runID))
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(zipPath, out, 0o644); err != nil {
		return "", err
	}
	return zipPath, nil
}

func extractZip(zipPath, dest string) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer r.Close()
	for _, f := range r.File {
		// guard against path traversal
		target := filepath.Join(dest, f.Name)
		if !strings.HasPrefix(target, filepath.Clean(dest)+string(os.PathSeparator)) {
			continue
		}
		if f.FileInfo().IsDir() {
			_ = os.MkdirAll(target, 0o755)
			continue
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		out, err := os.Create(target)
		if err != nil {
			rc.Close()
			return err
		}
		if _, err := io.Copy(out, rc); err != nil {
			rc.Close()
			out.Close()
			return err
		}
		rc.Close()
		out.Close()
	}
	return nil
}

func logsCmd() *cobra.Command {
	var (
		filter   string
		tailN    int
		ctxLines int
	)
	cmd := &cobra.Command{
		Use:   "logs <run-id>",
		Short: "Download logs for failed jobs and print tail + first error context",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			runID := args[0]
			runDir, err := ensureDebugDir(runID)
			if err != nil {
				return err
			}
			logsDir := filepath.Join(runDir, "logs")
			if err := os.MkdirAll(logsDir, 0o755); err != nil {
				return err
			}

			zipPath, err := downloadLogArchive(runID, runDir)
			if err != nil {
				return err
			}
			marker := filepath.Join(logsDir, ".extracted")
			if _, err := os.Stat(marker); err != nil {
				if err := extractZip(zipPath, logsDir); err != nil {
					return err
				}
				_ = os.WriteFile(marker, nil, 0o644)
			}

			rd, err := fetchRun(runID)
			if err != nil {
				return err
			}
			var failed []string
			for _, j := range rd.Jobs {
				if j.Conclusion == "failure" || j.Conclusion == "cancelled" {
					if filter == "" || strings.Contains(j.Name, filter) {
						failed = append(failed, j.Name)
					}
				}
			}
			if len(failed) == 0 {
				fmt.Println("No failed jobs to display.")
				return nil
			}

			files, err := walkLogs(logsDir)
			if err != nil {
				return err
			}
			errRe := regexp.MustCompile(`(?i)error|fail|fatal|panic`)

			for _, job := range failed {
				fmt.Println()
				fmt.Println(strings.Repeat("═", 70))
				fmt.Printf("FAILED JOB: %s\n", job)
				fmt.Println(strings.Repeat("═", 70))
				logFile := pickLogFile(files, job)
				if logFile == "" {
					fmt.Println("(no log file located in archive)")
					continue
				}
				fmt.Printf("Log file: %s\n\n", logFile)
				fmt.Printf("── Last %d lines ─────────────────────────────────\n", tailN)
				printTail(logFile, tailN)
				fmt.Printf("\n── First error context (%d lines) ───────────────\n", ctxLines)
				printErrorContext(logFile, errRe, ctxLines)
			}
			fmt.Printf("\nFull extracted logs: %s\n", logsDir)
			return nil
		},
	}
	cmd.Flags().StringVar(&filter, "job", "", "only show failed jobs whose name contains this substring")
	cmd.Flags().IntVar(&tailN, "tail", 200, "number of trailing lines to print per job")
	cmd.Flags().IntVar(&ctxLines, "context", 80, "max lines of error-context output per job")
	return cmd
}

func walkLogs(root string) ([]string, error) {
	var files []string
	err := filepath.Walk(root, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() && strings.HasSuffix(p, ".txt") {
			files = append(files, p)
		}
		return nil
	})
	return files, err
}

// pickLogFile returns the largest .txt file matching the job name (or its prefix).
func pickLogFile(files []string, job string) string {
	matchers := []string{job}
	if len(job) > 30 {
		matchers = append(matchers, job[:30])
	}
	type entry struct {
		path string
		size int64
	}
	var matched []entry
	for _, m := range matchers {
		for _, f := range files {
			if strings.Contains(f, m) {
				if fi, err := os.Stat(f); err == nil {
					matched = append(matched, entry{f, fi.Size()})
				}
			}
		}
		if len(matched) > 0 {
			break
		}
	}
	if len(matched) == 0 {
		return ""
	}
	sort.Slice(matched, func(i, j int) bool { return matched[i].size > matched[j].size })
	return matched[0].path
}

func printTail(path string, n int) {
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Println("(read error)")
		return
	}
	lines := strings.Split(string(data), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	fmt.Println(strings.Join(lines, "\n"))
}

func printErrorContext(path string, re *regexp.Regexp, maxLines int) {
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Println("(read error)")
		return
	}
	lines := strings.Split(string(data), "\n")
	const before, after = 2, 20
	printed := 0
	lastEnd := -1
	for i, l := range lines {
		if !re.MatchString(l) {
			continue
		}
		start := i - before
		if start < 0 {
			start = 0
		}
		if start <= lastEnd {
			start = lastEnd + 1
		}
		end := i + after
		if end >= len(lines) {
			end = len(lines) - 1
		}
		for k := start; k <= end; k++ {
			if printed >= maxLines {
				fmt.Println("(... truncated, see full log file ...)")
				return
			}
			fmt.Printf("%d: %s\n", k+1, lines[k])
			printed++
		}
		lastEnd = end
	}
	if printed == 0 {
		fmt.Println("(no error keywords matched)")
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// artifacts
// ─────────────────────────────────────────────────────────────────────────────

type artifact struct {
	ID          int64  `json:"id"`
	Name        string `json:"name"`
	SizeInBytes int64  `json:"size_in_bytes"`
	Expired     bool   `json:"expired"`
}

type artifactsList struct {
	Artifacts []artifact `json:"artifacts"`
}

func listArtifacts(runID string) ([]artifact, error) {
	out, err := gh("api", "--paginate",
		fmt.Sprintf("repos/{owner}/{repo}/actions/runs/%s/artifacts", runID))
	if err != nil {
		return nil, err
	}
	// --paginate concatenates JSON objects; split & merge
	var all []artifact
	dec := json.NewDecoder(bytes.NewReader(out))
	for {
		var page artifactsList
		if err := dec.Decode(&page); err != nil {
			if err == io.EOF {
				break
			}
			return nil, err
		}
		all = append(all, page.Artifacts...)
	}
	return all, nil
}

func artifactsCmd() *cobra.Command {
	var filter string
	cmd := &cobra.Command{
		Use:   "artifacts <run-id>",
		Short: "List artifacts for a run; with --name, download matching ones",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			runID := args[0]
			arts, err := listArtifacts(runID)
			if err != nil {
				return err
			}
			fmt.Printf("Artifacts for run %s:\n\n", runID)
			if len(arts) == 0 {
				fmt.Println("(none)")
				return nil
			}
			fmt.Printf("%-12s  %-60s  %-12s  %s\n", "ID", "NAME", "SIZE_BYTES", "EXPIRED")
			for _, a := range arts {
				fmt.Printf("%-12d  %-60s  %-12d  %v\n", a.ID, trunc(a.Name, 60), a.SizeInBytes, a.Expired)
			}

			if filter == "" {
				fmt.Printf("\nRe-run with --name <substring> to download, e.g.: ci-feedback artifacts %s --name cluster-dump\n", runID)
				return nil
			}

			runDir, err := ensureDebugDir(runID)
			if err != nil {
				return err
			}
			dest := filepath.Join(runDir, "artifacts")
			if err := os.MkdirAll(dest, 0o755); err != nil {
				return err
			}

			matched := 0
			for _, a := range arts {
				if a.Expired || !strings.Contains(a.Name, filter) {
					continue
				}
				matched++
				target := filepath.Join(dest, a.Name)
				if entries, _ := os.ReadDir(target); len(entries) > 0 {
					fmt.Printf("  ✓ already present: %s\n", target)
					continue
				}
				if err := os.MkdirAll(target, 0o755); err != nil {
					return err
				}
				fmt.Printf("  ↓ %s → %s\n", a.Name, target)
				dl := exec.Command("gh", "run", "download", runID, "--name", a.Name, "--dir", target)
				dl.Stdout = os.Stderr
				dl.Stderr = os.Stderr
				if err := dl.Run(); err != nil {
					fmt.Fprintf(os.Stderr, "    (download failed: %v)\n", err)
				}
			}
			if matched == 0 {
				return fmt.Errorf("no artifacts matched %q", filter)
			}
			fmt.Printf("\nDownloaded under: %s\n", dest)
			return nil
		},
	}
	cmd.Flags().StringVar(&filter, "name", "", "download artifacts whose name contains this substring")
	return cmd
}

// ─────────────────────────────────────────────────────────────────────────────
// utils
// ─────────────────────────────────────────────────────────────────────────────

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func trunc(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-1] + "…"
}
