# Multi-stage Dockerfile for Flask application
# Stage 1: Builder
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Runtime
FROM python:3.12-slim
WORKDIR /app

# Copy installed packages from builder to system path
COPY --from=builder /install /usr/local

# Copy application code
COPY main.py .

# Create non-root user
RUN useradd -m -u 1001 appuser && chown -R appuser:appuser /app

USER appuser
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "main:app"]