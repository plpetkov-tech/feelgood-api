.PHONY: help install lock test lint security-check build run clean

help:
	@echo "Available commands:"
	@echo "  make install        Install dependencies"
	@echo "  make lock          Generate lock files"
	@echo "  make refresh-locks  Refresh lock files"
	@echo "  make update-deps"
	@echo "  make verify-lock"
	@echo "  make test          Run tests"
	@echo "  make lint          Run linters"
	@echo "  make security-check Run security checks"
	@echo "  make build         Build Docker image"
	@echo "  make sbom          Generate SBOM"
	@echo "  make vex           Generate VEX document"

install:
	poetry install

# Generate all lock files
lock:
	@echo "🔒 Generating lock files..."
	poetry lock 
	poetry export -f requirements.txt --output requirements.txt --without-hashes
	poetry export -f requirements.txt --output requirements-lock.txt 
	poetry export -f requirements.txt --output requirements-dev.txt --with dev --without-hashes
	@echo "✅ Lock files generated"

# Verify lock file integrity
verify-lock:
	poetry check
	@echo "✅ Lock file verified"

# Update dependencies and regenerate locks
update-deps:
	@echo "📦 Updating dependencies..."
	poetry update
	$(MAKE) lock
	@echo "✅ Dependencies updated"

# Clear caches and regenerate everything
refresh-locks:
	@echo "🧹 Clearing caches..."
	poetry cache clear pypi --all -n
	rm -f poetry.lock requirements*.txt
	poetry lock
	$(MAKE) lock
	@echo "✅ Lock files refreshed"

test:
	poetry run pytest tests/ -v

lint:
	poetry run black src/ tests/
	poetry run ruff src/ tests/
	poetry run mypy src/

security-check:
	poetry run pip-audit
	@echo "Checking for known vulnerabilities in dependencies..."

build:
	docker build -t feelgood-api:latest .

sbom:
	poetry run cyclonedx-py -p -o sbom.json --format json
	@echo "SBOM generated: sbom.json"

vex:
	python scripts/generate_vex.py > vex.json
	@echo "VEX document generated: vex.json"

run:
	docker run -p 8000:8000 feelgood-api:latest

clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
