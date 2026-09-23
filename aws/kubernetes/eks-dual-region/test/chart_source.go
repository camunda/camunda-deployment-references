package test

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type chartSchema struct {
	Properties struct {
		Orchestration struct {
			Properties map[string]json.RawMessage `json:"properties"`
		} `json:"orchestration"`
	} `json:"properties"`
}

// validatePartitioningChart requires a chart that is already on disk and whose
// schema declares orchestration.partitioning. A remote reference -- the public
// `camunda/camunda-platform` repo, or an oci:// ref -- cannot be inspected
// without pulling it first, so it is rejected rather than trusted: installing a
// chart that predates the key makes Helm ignore the partitioning values and
// silently deploy the numbered topology these overlays exist to replace.
func validatePartitioningChart(chartName string) error {
	schemaBytes, err := os.ReadFile(filepath.Join(chartName, "values.schema.json"))
	if err != nil {
		return fmt.Errorf("cannot read chart schema: %q is not a local chart directory "+
			"(dual-region installs build the chart from source, see DEVELOPER.md): %w", chartName, err)
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
