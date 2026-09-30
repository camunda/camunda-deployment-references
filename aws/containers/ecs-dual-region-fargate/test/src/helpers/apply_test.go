package helpers

import (
	"os"
	"path/filepath"
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
