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

func TestIsolatedStatePathsIncludesFixture(t *testing.T) {
	// Given
	paths := IsolatedStatePaths(t, "..")
	// When
	fixture := paths.Fixture
	// Then
	want := filepath.Join(paths.VPC, "..", "..", "..", "..", "test-fixtures", "byo-vpcs")
	if fixture != want {
		t.Fatalf("fixture = %q, want copied path %q", fixture, want)
	}
	if _, err := os.Stat(filepath.Join(fixture, "main.tf")); err != nil {
		t.Fatal(err)
	}
}

// The cleanup workflows reclaim these states with aws-generic-terraform-cleanup,
// which rebuilds each key as `<prefix>tfstate-<id>/<module>.tfstate`. Keep the
// layout the tests write and the one the action reads in step.
func TestBackendKeyPrefixMatchesTheCleanupLayout(t *testing.T) {
	t.Setenv("TEST_RUN_ID", "")
	const cleanupPrefix = "aws/containers/ecs-dual-region-fargate/"
	for _, tc := range []struct{ runID, group string }{
		{"", "e2e-fo-planned-abc123"},
		{"36689383933", "e2e-fo-planned-abc123-run36689383933"},
	} {
		t.Run("run="+tc.runID, func(t *testing.T) {
			// Given
			t.Setenv("TEST_RUN_ID", tc.runID)
			// When
			prefix := BackendKeyPrefix("e2e-fo-planned-abc123")
			// Then
			for _, layer := range []string{"app", "infra", "vpc", "fixture"} {
				written := prefix + layer + "/terraform.tfstate"
				rebuilt := cleanupPrefix + "tfstate-" + tc.group + "/" + layer + "/terraform.tfstate"
				if written != rebuilt {
					t.Errorf("state key %q, cleanup looks for %q", written, rebuilt)
				}
			}
			if tc.runID != "" && !strings.Contains(prefix, "run"+tc.runID+"/") {
				t.Fatal("cleanup target does not match the key")
			}
		})
	}
}

func TestRunTagUsesRunIDSuffix(t *testing.T) {
	// Given
	t.Setenv("TEST_RUN_ID", "36689383933")
	// When
	tag := RunTag()
	// Then
	if tag != "383933" {
		t.Fatalf("RunTag() = %q, want the last six digits", tag)
	}
}
