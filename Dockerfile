# Multi-stage build for security and minimal size
FROM python:3.11-slim@sha256:0ce77749ac83174a31d5e107ce0cfa6b28a2fd6b0615e029d9d84b39c48976ee AS builder

# Install only essential build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

WORKDIR /build

# Copy dependency files first for better caching
COPY requirements-lock.txt ./
RUN pip install --no-cache-dir --user -r requirements-lock.txt

# Copy and prepare source code
COPY src/ ./src/

# Final stage - use Google's distroless image for minimal attack surface
FROM gcr.io/distroless/python3-debian12:nonroot@sha256:f0705bdc0d76976fc0a7a1995a4135eb9a3358d021f960dfe1a80bd3a4eade82

# Copy Python packages from builder
COPY --from=builder /root/.local /home/nonroot/.local

# Copy application code
COPY --from=builder /build/src /app/src

WORKDIR /app

# Set Python path for user-installed packages
ENV PATH=/home/nonroot/.local/bin:$PATH
ENV PYTHONPATH=/app

# Use distroless non-root user (UID 65532)
USER nonroot

# Expose port
EXPOSE 8000

# Add security labels
LABEL org.opencontainers.image.source="https://github.com/plpetkov-tech/feelgood-api"
LABEL org.opencontainers.image.description="Feel Good Phrases API - Ultra-Minimal Secure Build"
LABEL org.opencontainers.image.licenses="MIT"

# Run application
ENTRYPOINT ["python", "-m", "uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "8000"]
