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
