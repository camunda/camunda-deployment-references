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
//
// Release duty: this rejects the public chart too. Once 8.10 ships a released
// chart carrying orchestration.partitioning,
// `.github/actions/internal-multi-region-tests/action.yml` flips
// HELM_CHART_NAME to `camunda/camunda-platform` and this guard fails the suite
// on a chart that is in fact capable. Pull the reference into a temporary
// directory and validate the extracted schema there, rather than dropping the
// guard.
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
