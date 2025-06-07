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

# Test 1: Basic health and functionality tests
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
echo "📚 Phase 1.5: Documentation Endpoints Tests"
# Documentation endpoints
make_request "${BASE_URL}/docs" "200" "OpenAPI docs (Swagger UI)"
make_request "${BASE_URL}/openapi.json" "200" "OpenAPI JSON schema"
make_request "${BASE_URL}/docs/oauth2-redirect" "200" "OAuth2 redirect page"
make_request "${BASE_URL}/redoc" "200" "ReDoc documentation"

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
# Test 3: Security endpoints - comprehensive testing
make_request "${BASE_URL}/security" "200" "Security headers info"
make_request "${BASE_URL}/security/sbom" "200" "SBOM endpoint"
make_request "${BASE_URL}/security/vex" "200" "VEX endpoint"  
make_request "${BASE_URL}/security/provenance" "200" "Provenance endpoint"

# Test security endpoints with different methods and headers
echo ""
echo "🛡️ Phase 3.5: HTTP Middleware and Headers Tests"
# Test various HTTP scenarios to trigger middleware
curl -s -H "User-Agent: TestBot/1.0" -H "X-Forwarded-For: 192.168.1.100" -w "Status: %{http_code}, Time: %{time_total}s\n" -o /dev/null "${BASE_URL}/" || true
curl -s -H "Accept: application/json" -H "Content-Type: application/json" -w "Status: %{http_code}, Time: %{time_total}s\n" -o /dev/null "${BASE_URL}/health" || true
curl -s -H "Origin: https://example.com" -w "Status: %{http_code}, Time: %{time_total}s\n" -o /dev/null "${BASE_URL}/security" || true

# Test CORS preflight requests
curl -s -X OPTIONS -H "Origin: https://example.com" -H "Access-Control-Request-Method: GET" -w "CORS Status: %{http_code}\n" -o /dev/null "${BASE_URL}/phrase" || true

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
    "/docs/hidden"
    "/security/admin"
    "/security/config"
    "/security/internal"
    "/phrases/admin"
    "/health/debug"
    "/api"
    "/v1"
    "/swagger"
    "/swagger.json"
    "/api-docs"
)

echo "🔮 Fuzzing with ${#FUZZ_PATHS[@]} different paths..."
for path in "${FUZZ_PATHS[@]}"; do
    make_request "${BASE_URL}${path}" "404" "Fuzz test: $path"
done

echo ""
echo "⚡ Phase 5: Load and Stress Patterns"
# Test 5: Rapid fire requests to simulate load across all endpoints
echo "🔥 Rapid fire requests (5 quick bursts across all endpoints)..."
ENDPOINTS=("/health" "/" "/phrase" "/phrases/categories" "/security" "/docs" "/security/sbom" "/security/vex" "/security/provenance")

for burst in {1..5}; do
    echo "   💥 Burst $burst/5"
    for endpoint in "${ENDPOINTS[@]}"; do
        make_request "${BASE_URL}${endpoint}" "200" "Load burst $burst - $endpoint" &
    done
    wait
    sleep 1
done

echo ""
echo "🎯 Phase 5.5: Endpoint-Specific Load Testing"
# Test each main endpoint with focused load
for endpoint in "${ENDPOINTS[@]}"; do
    echo "🏹 Focused load test on $endpoint"
    for i in {1..5}; do
        make_request "${BASE_URL}${endpoint}" "200" "Focused load $endpoint #$i" &
    done
    wait
    sleep 0.5
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
    "/DOCS" # Case sensitivity for docs
    "/Security" # Case sensitivity for security
    "/phrases/Categories" # Case sensitivity for categories
    "/docs?theme=dark" # Docs with query params
    "/docs/../docs" # Path traversal attempt on docs
    "/security?format=json" # Security with query params
    "/phrase?category=motivation%2Bconfidence" # URL encoded plus
    "/openapi.json?pretty=true" # OpenAPI with params
    "/redoc?theme=light" # ReDoc with params
)

echo "🎪 Testing edge cases..."
for edge_case in "${EDGE_CASES[@]}"; do
    make_request "${BASE_URL}${edge_case}" "200" "Edge case: $edge_case"
done

echo ""
echo "🌐 Phase 6.5: HTTP Method Testing"
# Test different HTTP methods on endpoints
echo "🔧 Testing different HTTP methods..."

# Test POST, PUT, DELETE on read-only endpoints (should return 405 Method Not Allowed)
HTTP_METHODS=("POST" "PUT" "DELETE" "PATCH")
TEST_ENDPOINTS=("/health" "/phrase" "/security" "/docs")

for method in "${HTTP_METHODS[@]}"; do
    for endpoint in "${TEST_ENDPOINTS[@]}"; do
        echo "🔧 Testing $method on $endpoint"
        curl -s -X "$method" -w "Method $method on $endpoint: %{http_code}\n" -o /dev/null "${BASE_URL}${endpoint}" || true
        sleep 0.2
    done
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
echo "   - Complete API endpoint coverage (/, /health, /phrase, /phrases/categories, /security/*)"
echo "   - Documentation endpoints testing (/docs, /openapi.json, /redoc, /docs/oauth2-redirect)"
echo "   - HTTP middleware interaction patterns"
echo "   - CORS and security headers validation"
echo "   - Error handling patterns (404s, 405s)"
echo "   - Security boundary testing"
echo "   - Load simulation across all endpoints"
echo "   - Edge case exploration (case sensitivity, malformed requests)"
echo "   - HTTP method variation testing"
echo "   - Path traversal and injection attempt simulation"
echo ""
echo "✨ VEX analysis should now have comprehensive runtime data covering all FastAPI endpoints and middleware!"