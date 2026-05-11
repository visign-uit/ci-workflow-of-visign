FROM python:3.11-slim

WORKDIR /app

ARG TORCH_COMPUTE

RUN test -n "$TORCH_COMPUTE" || (echo "ERROR: Missing required build arg TORCH_COMPUTE (cpu|gpu)" >&2; exit 1)
RUN case "$TORCH_COMPUTE" in cpu|gpu) ;; *) echo "ERROR: TORCH_COMPUTE must be cpu or gpu" >&2; exit 1 ;; esac

# System dependencies needed by OpenCV/MediaPipe at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install torch variant based on TORCH_COMPUTE.
RUN pip install --no-cache-dir --upgrade pip && \
    if [ "$TORCH_COMPUTE" = "gpu" ]; then \
    pip install --no-cache-dir --default-timeout=300 --index-url https://download.pytorch.org/whl/cu121 torch; \
    else \
    pip install --no-cache-dir --default-timeout=300 --index-url https://download.pytorch.org/whl/cpu torch; \
    fi

COPY requirements.runtime.txt .
RUN pip install --no-cache-dir --default-timeout=120 -r requirements.runtime.txt

# Create a non-privileged user
RUN adduser --disabled-password --gecos '' appuser

# Copy application code
COPY . .

# Change ownership of app files to non-privileged user
RUN chown -R appuser: /app

# Switch to non-privileged user
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/docs')" || exit 1

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]

