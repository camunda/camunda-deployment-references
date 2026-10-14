package helpers

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

type BrokerLogs struct {
	Profile  string
	Region   string
	LogGroup string
	Start    time.Time
}

// Defer before apply so partial deployments are captured before t.Cleanup runs.
func CaptureBrokerLogsOnFailure(t *testing.T, logs BrokerLogs) {
	t.Helper()
	if !t.Failed() {
		return
	}
	dir := os.Getenv("TEST_DIAGNOSTICS_DIR")
	if dir == "" {
		dir = "debug/ecs-failover-diagnostics"
	}
	dir = filepath.Join(dir, strings.ReplaceAll(t.Name(), "/", "-"))
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Logf("Cannot create broker diagnostics directory: %v", err)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	path := filepath.Join(dir, "surviving-brokers.log")
	if err := logs.capture(ctx, path, time.Now()); err != nil {
		t.Logf("Broker log capture failed (teardown will continue): %v", err)
	}
	t.Logf("Broker diagnostics: %s", path)
}

func (logs BrokerLogs) capture(ctx context.Context, path string, end time.Time) error {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return fmt.Errorf("create broker log file: %w", err)
	}
	args := []string{"logs", "filter-log-events", "--log-group-name", logs.LogGroup,
		"--start-time", strconv.FormatInt(logs.Start.UnixMilli(), 10),
		"--end-time", strconv.FormatInt(end.UnixMilli(), 10),
		"--region", logs.Region, "--output", "json", "--no-cli-pager"}
	if logs.Profile != "" {
		args = append(args, "--profile", logs.Profile)
	}
	cmd := exec.CommandContext(ctx, "aws", args...)
	cmd.Stdout, cmd.Stderr = file, file
	runErr := cmd.Run()
	closeErr := file.Close()
	if runErr != nil {
		return fmt.Errorf("filter broker log events: %w", runErr)
	}
	return closeErr
}
