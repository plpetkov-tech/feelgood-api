#!/bin/bash

# Helper script to add production VEX documents with proper naming

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <environment> <vex-file>"
    echo "Example: $0 prod-cluster /path/to/runtime.vex.json"
    exit 1
fi

ENVIRONMENT="$1"
SOURCE_FILE="$2"
VEX_DIR=$(dirname "$0")

if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Source VEX file not found: $SOURCE_FILE"
    exit 1
fi

# Generate timestamp
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")

# Create destination filename
DEST_FILE="$VEX_DIR/production/${ENVIRONMENT}-${TIMESTAMP}.vex.json"

# Validate source file first
echo "🔍 Validating source VEX document..."
if command -v jq >/dev/null && ! jq empty "$SOURCE_FILE" 2>/dev/null; then
    echo "❌ Invalid JSON in source file"
    exit 1
fi

# Copy file
cp "$SOURCE_FILE" "$DEST_FILE"
echo "✅ Production VEX document added: $(basename "$DEST_FILE")"

# Validate the copied file
if [ -x "$VEX_DIR/validate-vex.sh" ]; then
    if ! "$VEX_DIR/validate-vex.sh"; then
        echo "⚠️  Validation warnings found - please review before committing"
    fi
fi

echo ""
echo "📝 Next steps:"
echo "1. Review the VEX document: $DEST_FILE"
echo "2. Commit and push to trigger VEX integration workflow"
echo "3. The workflow will consolidate and update container attestations"
