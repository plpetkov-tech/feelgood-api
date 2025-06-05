#!/bin/bash
set -euo pipefail

# Runtime Testing Script for VEX Analysis
# This script generates realistic application traffic during runtime analysis

APP_HOST="${1:-localhost}"
APP_PORT="${2:-30080}"
BASE_URL="http://${APP_HOST}:${APP_PORT}"

echo "🚀 Starting runtime testing for VEX analysis"
echo "📍 Target: ${BASE_URL}"
echo "⏰ Start time: $(date)"

# Counters for reporting
SUCCESS_COUNT=0
ERROR_COUNT=0
TOTAL_REQUESTS=0

# Function to make a request and track stats
make_request() {
    local url="$1"
    local expected_code="${2:-200}"
    local description="$3"
    
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
    
    echo "🔍 Testing: $description"
    echo "   URL: $url"
    
    if response=$(curl -s -w "%{http_code}" -o /dev/null --max-time 10 "$url" 2>/dev/null); then
        if [[ "$response" =~ ^[45][0-9][0-9]$ ]] && [[ "$expected_code" =~ ^[45][0-9][0-9]$ ]]; then
            # Expected error response
            echo "   ✅ Expected $expected_code, got $response"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        elif [[ "$response" == "$expected_code" ]]; then
            # Expected success response
            echo "   ✅ Success ($response)"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "   ⚠️  Unexpected response: $response (expected $expected_code)"
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
    else
        echo "   ❌ Request failed"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    
    # Small delay between requests
    sleep 0.5
}

echo ""
echo "📋 Starting test suite..."
echo ""

# Test 1: Basic health and functionality tests (10 requests)
echo "🏥 Phase 1: Health and Core Functionality Tests"
for i in {1..3}; do
    make_request "${BASE_URL}/health" "200" "Health check #$i"
done

for i in {1..2}; do
    make_request "${BASE_URL}/" "200" "Root endpoint #$i"
done

for i in {1..3}; do
    make_request "${BASE_URL}/phrase" "200" "Get random phrase #$i"
done

make_request "${BASE_URL}/phrases/categories" "200" "Get categories"
make_request "${BASE_URL}/security" "200" "Security info"

echo ""
echo "🎯 Phase 2: API Exploration Tests"
# Test 2: Different phrase categories
CATEGORIES=("motivation" "confidence" "success" "wellness" "invalid_category")
for category in "${CATEGORIES[@]}"; do
    if [[ "$category" == "invalid_category" ]]; then
        make_request "${BASE_URL}/phrase?category=${category}" "400" "Invalid category test"
    else
        make_request "${BASE_URL}/phrase?category=${category}" "200" "Category: $category"
    fi
done

echo ""
echo "🔍 Phase 3: Security Endpoint Tests"
# Test 3: Security endpoints
make_request "${BASE_URL}/security/sbom" "404" "SBOM endpoint (expected 404 in runtime)"
make_request "${BASE_URL}/security/vex" "404" "VEX endpoint (expected 404 in runtime)"
make_request "${BASE_URL}/security/provenance" "200" "Provenance endpoint"

echo ""
echo "🎭 Phase 4: Fuzzing and Error Generation Tests"
# Test 4: Fuzzing - Generate 404s and various errors
FUZZ_PATHS=(
    "/nonexistent"
    "/admin"
    "/api/v1/secret"
    "/config"
    "/status"
    "/.env"
    "/backup"
    "/test"
    "/debug"
    "/metrics"
    "/internal"
    "/private"
    "/../../../etc/passwd"
    "/phrase/../admin"
    "/phrase?category=../../../etc"
    "/phrase?category=" # Empty parameter
)

echo "🔮 Fuzzing with ${#FUZZ_PATHS[@]} different paths..."
for path in "${FUZZ_PATHS[@]}"; do
    make_request "${BASE_URL}${path}" "404" "Fuzz test: $path"
done

echo ""
echo "⚡ Phase 5: Load and Stress Patterns"
# Test 5: Rapid fire requests to simulate load
echo "🔥 Rapid fire requests (5 quick bursts)..."
for burst in {1..5}; do
    echo "   💥 Burst $burst/5"
    for i in {1..3}; do
        make_request "${BASE_URL}/phrase" "200" "Load burst $burst-$i" &
    done
    wait
    sleep 1
done

echo ""
echo "🎪 Phase 6: Edge Case Testing"
# Test 6: Edge cases and malformed requests
EDGE_CASES=(
    "/phrase?category=motivation&extra=param"
    "/phrase?CATEGORY=MOTIVATION" # Case sensitivity
    "/phrase?category=motivation%20wellness" # URL encoded
    "/phrase?category=motivation&category=confidence" # Duplicate params
    "/HEALTH" # Case sensitivity
    "/Phrase" # Case sensitivity
)

echo "🎪 Testing edge cases..."
for edge_case in "${EDGE_CASES[@]}"; do
    make_request "${BASE_URL}${edge_case}" "200" "Edge case: $edge_case"
done

# Final statistics
echo ""
echo "========================================"
echo "🎯 Runtime Testing Complete!"
echo "========================================"
echo "⏰ End time: $(date)"
echo "📊 Statistics:"
echo "   🎯 Total Requests: $TOTAL_REQUESTS"
echo "   ✅ Successful: $SUCCESS_COUNT"
echo "   ❌ Errors: $ERROR_COUNT"
echo "   📈 Success Rate: $((SUCCESS_COUNT * 100 / TOTAL_REQUESTS))%"
echo ""
echo "🔍 Runtime behavior patterns generated for VEX analysis:"
echo "   - API endpoint coverage"
echo "   - Error handling patterns" 
echo "   - Security boundary testing"
echo "   - Load simulation"
echo "   - Edge case exploration"
echo ""
echo "✨ VEX analysis should now have comprehensive runtime data!"