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

func validatePartitioningChart(chartName string) error {
	schemaBytes, err := os.ReadFile(filepath.Join(chartName, "values.schema.json"))
	if err != nil {
		return fmt.Errorf("cannot read chart schema: %w", err)
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
