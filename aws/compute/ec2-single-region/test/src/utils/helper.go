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

func LowerVersion(version string) (string, error) {
	parts := strings.Split(version, ".")
	if len(parts) != 3 {
		return "", fmt.Errorf("invalid version format: %s", version)
	}

	major, err := strconv.Atoi(parts[0])
	if err != nil {
		return "", err
	}
	minor, err := strconv.Atoi(parts[1])
	if err != nil {
		return "", err
	}

	patch := 0
	if !strings.Contains(parts[2], "SNAPSHOT") {
		patch, err = strconv.Atoi(parts[2])
		if err != nil {
			return "", err
		}
	}

	if patch > 0 {
		patch--
	} else if patch == 0 {
		minor--
	} else {
		return "", fmt.Errorf("cannot lower version further")
	}

	return fmt.Sprintf("%d.%d.%d", major, minor, patch), nil
}
