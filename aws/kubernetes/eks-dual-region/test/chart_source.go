package test

import "fmt"

func validatePartitioningChart(chartName string) error {
	if chartName == "camunda/camunda-platform" {
		return fmt.Errorf("HELM_CHART_NAME must point to a source-built chart containing orchestration.partitioning; follow DEVELOPER.md")
	}
	return nil
}
