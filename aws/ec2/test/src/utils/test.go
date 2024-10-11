package utils

import (
	"fmt"
	"os"
	"strings"
)

func OverwriteTerraformLifecycle(filePath string) {
	content, err := os.ReadFile(filePath)
	if err != nil {
		fmt.Println("Error reading file:", err)
		return
	}

	fileContent := string(content)
	updatedContent := strings.Replace(fileContent, "prevent_destroy       = true", "prevent_destroy       = false", 1)

	// Write the updated content back to the file
	err = os.WriteFile(filePath, []byte(updatedContent), 0644)
	if err != nil {
		fmt.Println("Error writing to file:", err)
		return
	}
}
