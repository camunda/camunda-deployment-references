package utils

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func GetEnv(key, fallback string) string {
	value, exists := os.LookupEnv(key)
	if !exists {
		value = fallback
	}
	return value
}

func IncrementMinorVersionTwoParts(version string) (string, error) {
	parts := strings.Split(version, ".")

	if len(parts) != 2 {
		return "", fmt.Errorf("invalid version format, expected 2 parts got %d", len(parts))
	}

	minor, err := strconv.Atoi(parts[1])
	if err != nil {
		return "", err
	}

	newVersion := fmt.Sprintf("%s.%d", parts[0], minor+1)

	return newVersion, nil
}
