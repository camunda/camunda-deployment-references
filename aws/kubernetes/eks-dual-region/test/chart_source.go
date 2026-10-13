package test

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

type chartSchema struct {
	Properties struct {
		Orchestration struct {
			Properties map[string]json.RawMessage `json:"properties"`
		} `json:"orchestration"`
	} `json:"properties"`
}

func validatePartitioningChart(chartName string) error {
	if chartName == "camunda/camunda-platform" {
		dir, err := os.MkdirTemp("", "partitioning-chart-")
		if err != nil {
			return fmt.Errorf("create chart directory: %w", err)
		}
		defer os.RemoveAll(dir)
		version := os.Getenv("HELM_CHART_VERSION")
		if version == "" {
			version = "15.1.0"
		}
		cmd := exec.Command("helm", "pull", "camunda-platform", "--repo", "https://helm.camunda.io", "--untar", "--untardir", dir, "--version", version)
		if output, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("pull chart schema: %w: %s", err, output)
		}
		chartName = filepath.Join(dir, "camunda-platform")
	}
	schemaBytes, err := os.ReadFile(filepath.Join(chartName, "values.schema.json"))
	if err != nil {
		return fmt.Errorf("cannot read chart schema: %q is not a local chart directory: %w", chartName, err)
	}
	var schema chartSchema
	if err := json.Unmarshal(schemaBytes, &schema); err != nil {
		return fmt.Errorf("cannot parse chart schema: %w", err)
	}
	if _, ok := schema.Properties.Orchestration.Properties["partitioning"]; !ok {
		return fmt.Errorf("chart does not expose orchestration.partitioning")
	}
	return nil
}
