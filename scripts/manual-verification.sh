#!/bin/bash
# debug-attestations.sh - Debug what attestations are actually on an image
# Usage: ./debug-attestations.sh <image-reference>

set -euo pipefail

IMAGE="${1:-}"
COSIGN_PUBLIC_KEY="${COSIGN_PUBLIC_KEY:-cosign.pub}"

if [ -z "$IMAGE" ]; then
    echo "❌ Usage: $0 <image-reference>"
    echo "   Example: $0 ghcr.io/your-org/your-repo@sha256:abc123..."
    exit 1
fi

echo "🔍 Debug Analysis for Image: $IMAGE"
echo "=================================================="

# 1. Check if cosign can verify the signature
echo ""
echo "🔐 Signature Verification:"
if cosign verify --key "$COSIGN_PUBLIC_KEY" "$IMAGE" 2>/dev/null; then
    echo "✅ Signature verification passed"
else
    echo "❌ Signature verification failed"
fi

echo ""
echo "🎯 Testing Specific Attestation Types:"

ATTESTATION_TYPES=(
#    "https://slsa.dev/provenance/v0.2"
#    "https://in-toto.io/Statement/v0.1"
    "openvex"
#    "https://openvex.dev/ns/v0.2.0"
#    "vuln"
#    "custom"
)

for att_type in "${ATTESTATION_TYPES[@]}"; do
    echo -n "  Checking '$att_type': "
    if cosign verify-attestation --key "$COSIGN_PUBLIC_KEY" --type="$att_type" "$IMAGE" >/dev/null 2>&1; then
        echo "✅ FOUND"
        
        # Show VEX summary instead of full content
        echo "    VEX Summary:"
        PAYLOAD=$(cosign verify-attestation --key "$COSIGN_PUBLIC_KEY" --type "$att_type" "$IMAGE" -o json 2>/dev/null | jq -r 'if type == "array" then .[0].payload else .payload end | @base64d | fromjson' 2>/dev/null)
        if echo "$PAYLOAD" | jq -e '.predicate.statements' >/dev/null 2>&1; then
            STMT_COUNT=$(echo "$PAYLOAD" | jq '.predicate.statements | length' 2>/dev/null || echo "0")
            NOT_AFFECTED=$(echo "$PAYLOAD" | jq '.predicate.statements | map(select(.status == "not_affected")) | length' 2>/dev/null || echo "0")
            AFFECTED=$(echo "$PAYLOAD" | jq '.predicate.statements | map(select(.status == "affected")) | length' 2>/dev/null || echo "0")
            AUTHOR=$(echo "$PAYLOAD" | jq -r '.predicate.author // "unknown"' 2>/dev/null)
            echo "      📊 Total statements: $STMT_COUNT"
            echo "      ✅ Not affected: $NOT_AFFECTED"
            echo "      ⚠️  Affected: $AFFECTED"
            echo "      👤 Author: $AUTHOR"
            
            # Show sample vulnerabilities (first 3)
            echo "      🔍 Sample vulnerabilities:"
            echo "$PAYLOAD" | jq -r '.predicate.statements[0:3][] | "        - \(.vulnerability."@id" // .vulnerability.name): \(.status)"' 2>/dev/null || echo "        (Could not extract sample vulnerabilities)"
        else
            echo "      ⚠️  Could not parse VEX statements"
        fi 
    else
        echo "❌ Not found"
    fi
done

# 4. Raw attestation data inspection
echo ""
echo "🔍 Raw Attestation Data:"
echo "Attempting to get raw attestation JSON..."

RAW_ATTESTATIONS=$(cosign verify-attestation --type=openvex --key "$COSIGN_PUBLIC_KEY" "$IMAGE" -o json 2>/dev/null || echo "null")

if [ "$RAW_ATTESTATIONS" != "null" ] && [ -n "$RAW_ATTESTATIONS" ]; then
    echo "✅ Raw attestation data retrieved"
    
    # Count attestations
    ATT_COUNT=$(echo "$RAW_ATTESTATIONS" | jq -r 'if type == "array" then length else 1 end' 2>/dev/null || echo "0")
    echo "📊 Total attestations found: $ATT_COUNT"
    
    # Show structure
    echo ""
    echo "📋 Attestation Structure:"
    echo "$RAW_ATTESTATIONS" | jq -r 'if type == "array" then .[0] else . end | keys[]' 2>/dev/null | sed 's/^/  - /' || echo "  (Could not parse structure)"
    # Show predicate types
    echo ""
    echo "🎯 Predicate Types Found:"
    echo "$RAW_ATTESTATIONS" | jq -r 'if type == "array" then .[].payload else .payload end | @base64d | fromjson | .predicateType' 2>/dev/null | sort -u | sed 's/^/  - /' || echo "  (Could not extract predicate types)"
    
    # Show subjects
    echo ""
    echo "🎯 Subjects (what the attestations are about):"
    echo "$RAW_ATTESTATIONS" | jq -r 'if type == "array" then .[].payload else .payload end | @base64d | fromjson | .subject[]?.name // empty' 2>/dev/null | sort -u | sed 's/^/  - /' || echo "  (Could not extract subjects)"
    
else
    echo "❌ No raw attestation data available"
fi

# 5. Check GitHub CLI for native attestations
echo ""
echo "🐙 GitHub Native Attestations:"
if command -v gh >/dev/null 2>&1; then
    REPO_FROM_IMAGE=$(echo "$IMAGE" | sed 's|ghcr.io/||' | cut -d':' -f1 | cut -d'@' -f1)
    echo "Checking repository: $REPO_FROM_IMAGE"
    
    gh attestation verify oci://$IMAGE --repo $REPO_FROM_IMAGE 
else
    echo "❌ GitHub CLI not available"
fi

# 6. Image manifest inspection
echo ""
echo "📦 Image Manifest Analysis:"
if command -v crane >/dev/null 2>&1; then
    echo "✅ Using crane to inspect manifest"
    
    echo "Image digest:"
    crane digest "$IMAGE" 2>/dev/null | sed 's/^/  /' || echo "  (Could not get digest)"
    
    echo "Image config:"
    crane config "$IMAGE" 2>/dev/null | jq -r '.created // "unknown"' | sed 's/^/  Created: /'
    
elif command -v docker >/dev/null 2>&1; then
    echo "ℹ️  Using docker to inspect image"
    docker manifest inspect "$IMAGE" 2>/dev/null | jq -r '.config.digest // "unknown"' | sed 's/^/  Config digest: /' || echo "  (Could not inspect with docker)"
else
    echo "❌ No image inspection tools available (crane, docker)"
fi

# 7. Cosign triangulate to find signatures
echo ""
echo "🔺 Cosign Triangulation (finding signature location):"
SIGNATURE_REF=$(cosign triangulate "$IMAGE" 2>/dev/null || echo "")
if [ -n "$SIGNATURE_REF" ]; then
    echo "✅ Signature reference: $SIGNATURE_REF"
    
    # Try to inspect the signature manifest
    if command -v crane >/dev/null 2>&1; then
        echo "Signature manifest layers:"
        crane manifest "$SIGNATURE_REF" 2>/dev/null | jq -r '.layers[]?.annotations?"org.opencontainers.image.title" // empty' | sed 's/^/  - /' || echo "  (Could not inspect signature manifest)"
    fi
else
    echo "❌ Could not triangulate signature location"
fi

echo ""
echo "=================================================="
echo "🎯 Summary:"
echo "This debug information should help identify:"
echo "  1. Whether signatures and attestations exist"
echo "  2. What types of attestations are present"
echo "  3. The structure of the attestation data"
echo "  4. Whether GitHub's native attestation system is being used"
echo ""
echo "If no SLSA attestations are found, check:"
echo "  • The slsa-provenance job in your GitHub Actions workflow"
echo "  • Whether the SLSA generator is actually running"
echo "  • Network/permissions issues during the build"
