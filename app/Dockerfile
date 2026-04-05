# Multi-stage Dockerfile for Flask application
# Stage 1: Builder
FROM public.ecr.aws/docker/library/python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime
FROM python:3.12-slim

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH

# Copy application code
COPY main.py .

# Create non-root user
RUN useradd -m -u 1001 appuser && chown -R appuser:appuser /app /root
USER appuser

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "main:app"]
