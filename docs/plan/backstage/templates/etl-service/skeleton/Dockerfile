# ─── Stage 1: Builder ────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Instala dependências de build
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Cria venv isolado em /venv (sem referência a /root)
RUN python -m venv /venv

# Instala dependências no venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir --upgrade pip && \
    /venv/bin/pip install --no-cache-dir -r requirements.txt

# ─── Stage 2: Runtime ────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

WORKDIR /app

# Instala apenas dependências de runtime do SO
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Cria usuário não-root com home directory
RUN useradd --uid 1000 --create-home --shell /bin/false appuser

# Copia venv do builder (path neutro /venv — sem referência a /root)
COPY --from=builder /venv /venv

# Ajusta permissões do venv para appuser
RUN chown -R appuser:appuser /venv

# Copia código-fonte
COPY src/ ./src/
COPY config/ ./config/

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/healthz || exit 1

# Ativa usuário não-root
USER appuser

# Usa Python do venv como padrão
ENV PATH=/venv/bin:$PATH \
    VIRTUAL_ENV=/venv

EXPOSE 8000 9090

ENV PORT=8000

CMD ["python", "-m", "etl_service.main"]
