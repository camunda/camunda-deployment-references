#!/bin/bash

# =============================================================================
# Get Your Copy - Migration from Bitnami to Operators
# =============================================================================
# Creates a local copy of all migration scripts for customization
# =============================================================================

set -euo pipefail

TARGET_DIR="${1:-./camunda-migration}"

echo "============================================="
echo "Camunda Migration Scripts"
echo "============================================="
echo ""
echo "This will create a copy of all migration scripts at: $TARGET_DIR"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create target directory
mkdir -p "$TARGET_DIR"

# Copy all files
cp -r "$SCRIPT_DIR/"* "$TARGET_DIR/"

# Make scripts executable
find "$TARGET_DIR" -name "*.sh" -exec chmod +x {} \;

echo "✓ Migration scripts copied to: $TARGET_DIR"
echo ""
echo "Next steps:"
echo "  1. cd $TARGET_DIR"
echo "  2. Edit 0-set-environment.sh with your configuration"
echo "  3. Run ./1-prerequisites/check-prerequisites.sh"
echo "  4. Follow the README.md for the complete workflow"
