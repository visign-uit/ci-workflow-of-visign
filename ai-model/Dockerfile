# ============================================
# Stage 1: The Builder
# ============================================
FROM python:3.11-slim AS builder

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Create the isolated virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip

ARG TORCH_COMPUTE
RUN test -n "$TORCH_COMPUTE" || (echo "ERROR: Missing required build arg TORCH_COMPUTE (cpu|gpu)" >&2; exit 1)
RUN case "$TORCH_COMPUTE" in cpu|gpu) ;; *) echo "ERROR: TORCH_COMPUTE must be cpu or gpu" >&2; exit 1 ;; esac

RUN --mount=type=cache,target=/root/.cache/pip \
    if [ "$TORCH_COMPUTE" = "gpu" ]; then \
        pip install --default-timeout=300 --index-url https://download.pytorch.org/whl/cu121 torch; \
    else \
        pip install --default-timeout=300 --index-url https://download.pytorch.org/whl/cpu torch; \
    fi

COPY requirements.runtime.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --default-timeout=120 -r requirements.runtime.txt

# ============================================
# Stage 2: The Runner
# ============================================
FROM python:3.11-slim AS runner

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Pull the finished venv from Stage 1 into exactly ONE clean layer
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN adduser --disabled-password --gecos '' appuser

# Single-layer secure copy
COPY --chown=appuser:appuser . .

USER appuser

EXPOSE 8000

# Optional uncomment to keep Healthcheck for local dev, K8s will use its own probes
# HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
#     CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/docs')" || exit 1

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--workers", "2"]