package helpers

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// Environment variables that the procedures require but that are produced by
// another procedure at run time rather than supplied by the caller, so the Go
// harness is not expected to provide them.
var envProducedAtRuntime = map[string]bool{
	// Emitted by generate-zeebe-helm-values.sh, which the deploy wrapper sources.
	"CAMUNDA_CLUSTER_INITIALCONTACTPOINTS": true,
	"CAMUNDA_MULTIREGION_ZONES":            true,
	// Defaulted by export-terraform-outputs.sh itself.
	"TF_DIR": true,
}

// requiredEnvPattern matches the `: "${VAR:?...}"` guard the procedures use to
// declare a mandatory input.
var requiredEnvPattern = regexp.MustCompile(`^: "\$\{([A-Z0-9_]+):\?`)

// TestProcedureEnvContractIsComplete asserts that every variable the shell
// procedures declare as mandatory is actually supplied by Env.Vars().
//
// The harness deliberately builds the environment itself instead of sourcing
// export_environment_prerequisites.sh, because a sourced shell cannot export
// back into the Go process. That duplication is the risk: a procedure gaining a
// new required variable will otherwise fail in CI only once the run reaches it,
// which for this suite is twenty minutes and two EKS clusters later. This test
// turns that into an immediate, free failure.
func TestProcedureEnvContractIsComplete(t *testing.T) {
	procedureDir := ProcedureDir(t)

	provided := map[string]bool{}
	for _, kv := range (Env{}).Vars() {
		if name, _, found := strings.Cut(kv, "="); found {
			provided[name] = true
		}
	}

	required := map[string][]string{}
	err := filepath.Walk(procedureDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || !strings.HasSuffix(path, ".sh") {
			return nil
		}

		content, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}

		rel, _ := filepath.Rel(procedureDir, path)
		for _, line := range strings.Split(string(content), "\n") {
			match := requiredEnvPattern.FindStringSubmatch(strings.TrimSpace(line))
			if match == nil {
				continue
			}
			name := match[1]
			if envProducedAtRuntime[name] {
				continue
			}
			required[name] = append(required[name], rel)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("cannot scan the procedure directory: %v", err)
	}

	if len(required) == 0 {
		t.Fatal("no required environment variables found; the scan is broken, not the contract")
	}

	var missing []string
	for name, scripts := range required {
		if !provided[name] {
			sort.Strings(scripts)
			missing = append(missing, name+" (required by "+strings.Join(scripts, ", ")+")")
		}
	}

	if len(missing) > 0 {
		sort.Strings(missing)
		t.Fatalf("Env.Vars() does not supply %d variable(s) the procedures require:\n  %s",
			len(missing), strings.Join(missing, "\n  "))
	}
}
