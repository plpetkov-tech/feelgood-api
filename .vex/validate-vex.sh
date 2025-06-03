#!/bin/bash

# Validate all VEX documents in the repository

set -e

VEX_DIR=$(dirname "$0")
ERRORS=0

echo "🔍 Validating VEX documents..."

# Function to validate a single VEX file
validate_vex_file() {
    local file="$1"
    echo "  📄 Validating: $(basename "$file")"
    
    # Check JSON syntax
    if ! jq empty "$file" 2>/dev/null; then
        echo "    ❌ Invalid JSON syntax"
        return 1
    fi
    
    # Check required OpenVEX fields
    local required_fields=("@context" "author" "timestamp" "statements")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$file" >/dev/null 2>&1; then
            echo "    ❌ Missing required field: $field"
            return 1
        fi
    done
    
    # Validate with vexctl if available
    if command -v vexctl >/dev/null 2>&1; then
        if vexctl validate "$file" >/dev/null 2>&1; then
            echo "    ✅ Valid VEX document"
        else
            echo "    ❌ vexctl validation failed"
            return 1
        fi
    else
        echo "    ✅ Basic validation passed (vexctl not available)"
    fi
    
    return 0
}

# Validate all VEX files
while IFS= read -r -d '' file; do
    if ! validate_vex_file "$file"; then
        ERRORS=$((ERRORS + 1))
    fi
done < <(find "$VEX_DIR" -name "*.vex.json" -not -path "*/archive/*" -print0)

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ All VEX documents are valid"
    exit 0
else
    echo "❌ $ERRORS VEX document(s) failed validation"
    exit 1
fi
