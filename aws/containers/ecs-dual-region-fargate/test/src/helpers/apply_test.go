package helpers

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestIsolatedStatePathsKeepsToolVersions(t *testing.T) {
	paths := IsolatedStatePaths(t, "..")
	for dir := paths.VPC; dir != filepath.Dir(dir); dir = filepath.Dir(dir) {
		if _, err := os.Stat(filepath.Join(dir, ".tool-versions")); err == nil {
			return
		}
	}
	t.Fatalf("no .tool-versions above %s, asdf cannot pick a terraform version", paths.VPC)
}

// The cleanup workflows reclaim these states with aws-generic-terraform-cleanup,
// which rebuilds each key as `<prefix>tfstate-<id>/<module>.tfstate`. Keep the
// layout the tests write and the one the action reads in step.
func TestBackendKeyPrefixMatchesTheCleanupLayout(t *testing.T) {
	const cleanupPrefix = "aws/containers/ecs-dual-region-fargate/"
	for _, layer := range []string{"app", "infra", "vpc"} {
		written := BackendKeyPrefix("e2e-fo-planned-abc123") + layer + "/terraform.tfstate"
		rebuilt := cleanupPrefix + "tfstate-e2e-fo-planned-abc123/" + layer + "/terraform" + ".tfstate"
		if written != rebuilt {
			t.Errorf("state key %q, cleanup looks for %q", written, rebuilt)
		}
	}
}

func TestBackendKeyPrefixCarriesTheRunID(t *testing.T) {
	t.Setenv("TEST_RUN_ID", "36689383933")
	got := BackendKeyPrefix("e2e-fo-planned-383933")
	if want := "aws/containers/ecs-dual-region-fargate/tfstate-e2e-fo-planned-383933-run36689383933/"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
	if !strings.Contains(got+"app/terraform.tfstate", "run36689383933/") {
		t.Fatal("the workflow's cleanup target run<id>/ does not match the key")
	}
	if tag := RunTag(); tag != "383933" {
		t.Fatalf("RunTag() = %q, want the last six digits", tag)
	}
}
