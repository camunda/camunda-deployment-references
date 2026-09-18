package test

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPartitioningValuesRequireSourceBuiltChart(t *testing.T) {
	err := validatePartitioningChart("camunda/camunda-platform")

	assert.ErrorContains(t, err, "HELM_CHART_NAME must point to a source-built chart")
}

func TestPartitioningValuesAcceptSourceBuiltChart(t *testing.T) {
	err := validatePartitioningChart("/workspace/camunda-platform-8.10")

	assert.NoError(t, err)
}
