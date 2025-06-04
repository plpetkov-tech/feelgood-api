#!/bin/bash
# Use Make, this thing is just for visibility
# Do not use!
set -euo pipefail

echo "🔒 Enhanced lock file generation with security checks..."

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Security audit before lock generation
echo "🛡️ Running security audit..."
poetry run pip-audit --format=json --output=pre-audit.json || echo "Pre-audit completed with findings"

# Clear caches and regenerate
echo "📦 Clearing Poetry cache..."
poetry cache clear pypi --all -n

# Generate locks with integrity verification
echo "🔐 Generating poetry.lock..."
poetry lock 

# Export with hashes for integrity
echo "📄 Generating requirements with integrity hashes..."
poetry export -f requirements.txt --output requirements-lock.txt 
poetry export -f requirements.txt --output requirements.txt --without-hashes
poetry export -f requirements.txt --output requirements-dev.txt --with dev --without-hashes

# Post-generation security audit
echo "🛡️ Running post-generation security audit..."
poetry run pip-audit --format=json --output=post-audit.json

# Verify lock integrity
echo "✅ Verifying lock file integrity..."
poetry check

# Generate SBOM for dependency analysis
echo "📋 Generating dependency SBOM..."
poetry run cyclonedx-py poetry -o sbom-deps.json --of json

echo "✨ Enhanced lock files generated with security validation!"
