#!/bin/bash
set -euo pipefail

echo "🔒 Generating lock files..."

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Clear any existing caches to ensure fresh resolution
echo "📦 Clearing Poetry cache..."
poetry cache clear pypi --all -n

# Generate poetry.lock
echo "🔐 Generating poetry.lock..."
poetry lock --no-update

# Generate requirements files
echo "📄 Generating requirements.txt..."
poetry export -f requirements.txt --output requirements.txt --without-hashes

echo "📄 Generating requirements-lock.txt with hashes..."
poetry export -f requirements.txt --output requirements-lock.txt --with-hashes

echo "📄 Generating requirements-dev.txt..."
poetry export -f requirements.txt --output requirements-dev.txt --with dev --without-hashes

# Verify the lock file
echo "✅ Verifying lock file integrity..."
poetry lock --check

# Show outdated packages
echo "📊 Checking for outdated packages..."
poetry show --outdated || true

echo "✨ Lock files generated successfully!"
echo ""
echo "Files created:"
echo "  - poetry.lock"
echo "  - requirements.txt"
echo "  - requirements-lock.txt"
echo "  - requirements-dev.txt"
