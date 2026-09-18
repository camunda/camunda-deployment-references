package test

import (
	"fmt"
	"strconv"
	"strings"
)

func validatePartitioningChart(chartName, chartVersion string) error {
	major, err := strconv.Atoi(strings.SplitN(chartVersion, ".", 2)[0])
	if chartName == "camunda/camunda-platform" && (err != nil || major < 15) {
		return fmt.Errorf("HELM_CHART_NAME must point to a source-built chart containing orchestration.partitioning; follow DEVELOPER.md")
	}
	return nil
}
