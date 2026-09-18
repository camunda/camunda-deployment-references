package test

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPartitioningValuesRequireSourceBuiltChart(t *testing.T) {
	err := validatePartitioningChart("camunda/camunda-platform", "14.8.0")

	assert.ErrorContains(t, err, "HELM_CHART_NAME must point to a source-built chart")
}

func TestPartitioningValuesAcceptSourceBuiltChart(t *testing.T) {
	err := validatePartitioningChart("/workspace/camunda-platform-8.10", "15-dev-latest")

	assert.NoError(t, err)
}

func TestPartitioningValuesAcceptPublicChartVersion15(t *testing.T) {
	err := validatePartitioningChart("camunda/camunda-platform", "15.0.0")

	assert.NoError(t, err)
}
