package test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPartitioningValuesRequireLocalChart(t *testing.T) {
	err := validatePartitioningChart("camunda/camunda-platform")

	assert.ErrorContains(t, err, "cannot read chart schema")
}

func TestPartitioningValuesRejectChartWithoutPartitioning(t *testing.T) {
	chart := t.TempDir()
	assert.NoError(t, os.WriteFile(filepath.Join(chart, "values.schema.json"), []byte(`{"properties":{"orchestration":{"properties":{}}}}`), 0o600))

	err := validatePartitioningChart(chart)

	assert.ErrorContains(t, err, "does not expose orchestration.partitioning")
}

func TestPartitioningValuesAcceptCapableChart(t *testing.T) {
	chart := t.TempDir()
	assert.NoError(t, os.WriteFile(filepath.Join(chart, "values.schema.json"), []byte(`{"properties":{"orchestration":{"properties":{"partitioning":{}}}}}`), 0o600))

	err := validatePartitioningChart(chart)

	assert.NoError(t, err)
}
