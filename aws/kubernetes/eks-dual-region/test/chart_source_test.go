package test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPartitioningValuesAcceptPublishedChart(t *testing.T) {
	bin := t.TempDir()
	helm := "#!/bin/sh\nmkdir -p \"$7/camunda-platform\"\nprintf '%s' '{\"properties\":{\"orchestration\":{\"properties\":{\"partitioning\":{}}}}}' > \"$7/camunda-platform/values.schema.json\"\n"
	assert.NoError(t, os.WriteFile(filepath.Join(bin, "helm"), []byte(helm), 0o700))
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	assert.NoError(t, validatePartitioningChart("camunda/camunda-platform"))
}

func TestPartitioningValuesRejectOCIReference(t *testing.T) {
	err := validatePartitioningChart("oci://ghcr.io/camunda/helm/camunda-platform")

	assert.ErrorContains(t, err, "is not a local chart directory")
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
