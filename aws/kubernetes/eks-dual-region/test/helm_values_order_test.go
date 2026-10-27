package test

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestHelmValuesFiles_appliesFinalOverridesAfterRegionValues(t *testing.T) {
	// Given
	base := []string{"base.yml", "credentials.yml"}
	final := []string{"multi-tenancy.yml"}

	// When
	got := helmValuesFiles(base, "region.yml", final[0])

	// Then
	require.Equal(t, []string{"base.yml", "credentials.yml", "region.yml", "multi-tenancy.yml"}, got)
}
