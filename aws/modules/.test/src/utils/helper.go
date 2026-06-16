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
		return "", fmt.Errorf("invalid version format %q, expected 2 parts, got %d", version, len(parts))
	}

	minor, err := strconv.Atoi(parts[1])
	if err != nil {
		return "", err
	}

	newVersion := fmt.Sprintf("%s.%d", parts[0], minor+1)

	return newVersion, nil
}

func DecrementMinorVersionTwoParts(version string) (string, error) {
	parts := strings.Split(version, ".")

	if len(parts) != 2 {
		return "", fmt.Errorf("invalid version format %q, expected 2 parts, got %d", version, len(parts))
	}

	minor, err := strconv.Atoi(parts[1])
	if err != nil {
		return "", err
	}

	if minor <= 0 {
		return "", fmt.Errorf("cannot decrement minor version of %q: resulting minor version would be negative", version)
	}

	newVersion := fmt.Sprintf("%s.%d", parts[0], minor-1)

	return newVersion, nil
}
