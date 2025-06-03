#!/bin/bash

# Fix VEX Document Timestamps Script
# This script fixes timestamp format issues in existing VEX documents

set -e

echo "🔧 Fixing VEX document timestamps..."

# Function to fix timestamps in a VEX file
fix_vex_timestamps() {
    local file="$1"
    local backup_file="${file}.backup"
    
    echo "📄 Processing: $(basename "$file")"
    
    # Create backup
    cp "$file" "$backup_file"
    
    # Check if file has timestamp issues
    if jq -r '.timestamp' "$file" | grep -E '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+$' >/dev/null 2>&1; then
        echo "  🔧 Fixing document timestamp (missing timezone)"
        
        # Fix timestamps by adding 'Z' for UTC timezone
        jq '
        # Fix main document timestamp
        .timestamp = (if (.timestamp | test("Z$|[+-]\\d{2}:\\d{2}$")) then .timestamp else (.timestamp + "Z") end) |
        
        # Fix statement timestamps  
        .statements = (.statements | map(
            .timestamp = (if (.timestamp | test("Z$|[+-]\\d{2}:\\d{2}$")) then .timestamp else (.timestamp + "Z") end)
        ))
        ' "$backup_file" > "$file"
        
        echo "  ✅ Timestamps fixed"
    else
        echo "  ✅ Timestamps already in correct format"
        rm "$backup_file"  # Remove backup if no changes needed
        return 0
    fi
    
    # Validate the fixed file
    if jq empty "$file" 2>/dev/null; then
        echo "  ✅ Fixed file is valid JSON"
        
        # Test with vexctl if available
        if command -v vexctl >/dev/null 2>&1; then
            if vexctl validate "$file" >/dev/null 2>&1; then
                echo "  ✅ VEX validation passed"
                rm "$backup_file"  # Remove backup after successful validation
            else
                echo "  ⚠️  VEX validation failed - backup preserved"
            fi
        else
            echo "  ℹ️  vexctl not available for validation"
            rm "$backup_file"  # Remove backup anyway
        fi
    else
        echo "  ❌ Fixed file is invalid JSON - restoring backup"
        mv "$backup_file" "$file"
        return 1
    fi
}

# Find and fix all VEX documents
echo "🔍 Finding VEX documents..."
vex_files_found=0

# Look for VEX files in common locations
while IFS= read -r -d '' file; do
    if [[ "$file" == *"vex.json" ]]; then
        fix_vex_timestamps "$file"
        vex_files_found=$((vex_files_found + 1))
    fi
done < <(find . -name "*vex.json" -type f -print0 2>/dev/null)

# Also check for any JSON files that might be VEX documents
while IFS= read -r -d '' file; do
    if [[ "$file" == *".json" ]] && ! [[ "$file" == *"vex.json" ]]; then
        # Check if it's a VEX document by looking for VEX-specific fields
        if jq -e '.["@context"] and .statements' "$file" >/dev/null 2>&1; then
            context=$(jq -r '.["@context"]' "$file" 2>/dev/null || echo "")
            if [[ "$context" == *"openvex"* ]] || [[ "$context" == *"vex"* ]]; then
                echo "📄 Found VEX document: $(basename "$file")"
                fix_vex_timestamps "$file"
                vex_files_found=$((vex_files_found + 1))
            fi
        fi
    fi
done < <(find . -name "*.json" -type f -not -name "*vex.json" -print0 2>/dev/null)

echo ""
if [ $vex_files_found -eq 0 ]; then
    echo "📄 No VEX documents found"
else
    echo "✅ Processed $vex_files_found VEX document(s)"
    echo ""
    echo "🚀 Next steps:"
    echo "1. Test the fixed VEX documents with: vexctl validate your-filevex.json"
    echo "2. Try merging again with: vexctl merge doc1vex.json doc2vex.json"
    echo "3. Commit the fixed documents if everything works"
fi

# Show vexctl usage examples
if command -v vexctl >/dev/null 2>&1; then
    echo ""
    echo "💡 vexctl commands you can try:"
    echo "  # Validate a VEX document:"
    echo "  vexctl validate your-filevex.json"
    echo ""
    echo "  # Merge two VEX documents:"
    echo "  vexctl merge doc1vex.json doc2vex.json > mergedvex.json"
    echo ""
    echo "  # Apply VEX to filter scan results:"
    echo "  vexctl filter scan-results.sarif your-vex.json > filtered-results.sarif"
else
    echo ""
    echo "💡 Install vexctl to validate and work with VEX documents:"
    echo "  # Using Go:"
    echo "  go install github.com/openvex/vexctl@latest"
    echo ""
    echo "  # Using GitHub Action:"
    echo "  - uses: openvex/setup-vexctl@main"
fi
