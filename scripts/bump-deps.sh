#!/bin/bash
# 
# Simple wrapper script for bump-all-deps.py
# 
# Usage: ./scripts/bump-deps.sh [options]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if poetry is installed
if ! command -v poetry &> /dev/null; then
    echo "❌ Poetry is not installed. Please install it first:"
    echo "   curl -sSL https://install.python-poetry.org | python3 -"
    exit 1
fi

# Check if we're in a poetry project
if [[ ! -f "$PROJECT_ROOT/pyproject.toml" ]]; then
    echo "❌ pyproject.toml not found. Are you in the right directory?"
    exit 1
fi

# Install requests and toml if not available
echo "🔧 Installing required dependencies..."
poetry run python -c "import requests, toml" 2>/dev/null || \
    poetry run pip install requests toml

echo "🚀 Running dependency updater..."
cd "$PROJECT_ROOT"
poetry run python scripts/bump-all-deps.py "$@"