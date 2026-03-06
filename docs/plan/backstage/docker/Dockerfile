# =============================================================================
# Backstage IDP — Dockerfile
# Versao:    1.48.0
# Node.js:   22 LTS (OBRIGATORIO — 18/20 descontinuados desde v1.46)
# Base build: node:22-bookworm-slim
# Base runtime: node:24-trixie-slim (conforme BACKSTAGE-IMPLEMENTATION-PLAN.md)
# CVE-2025-55285: plugin-scaffolder-backend >= 2.1.1 (usamos 3.1.3)
# Cluster:   k8s-platform-prod (EKS us-east-1, conta 891377105802)
# Registry:  harbor.staging.internal/platform/backstage:1.48.0
# ADR:       ADR-055
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Deps — instala apenas dependencias de producao
# -----------------------------------------------------------------------------
FROM node:22-bookworm-slim AS deps

# Instalar dependencias do sistema necessarias para compilacao de modulos nativos
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    make \
    g++ \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Habilitar Corepack para Yarn 4.4.1 (package manager oficial Backstage)
RUN corepack enable && corepack prepare yarn@4.4.1 --activate

WORKDIR /app

# Copiar arquivos de manifesto de pacotes antes do codigo-fonte
# para aproveitar cache de layers do Docker
COPY package.json yarn.lock .yarnrc.yml ./
COPY packages/app/package.json ./packages/app/
COPY packages/backend/package.json ./packages/backend/

# Instalar todas as dependencias (incluindo devDependencies para o build)
RUN yarn install --frozen-lockfile

# -----------------------------------------------------------------------------
# Stage 2: Build — compila frontend e backend
# -----------------------------------------------------------------------------
FROM node:22-bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare yarn@4.4.1 --activate

WORKDIR /app

# Copiar node_modules instalados no stage anterior
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/app/node_modules ./packages/app/node_modules
COPY --from=deps /app/packages/backend/node_modules ./packages/backend/node_modules

# Copiar codigo-fonte completo
COPY . .

# Build do TypeScript (type-check) e depois build completo
RUN yarn tsc && yarn build:all

# Empacotar apenas as dependencias de producao do backend
# O comando bundle cria dist/skeleton.tar.gz e dist/bundle.tar.gz
RUN yarn workspace backend build && \
    yarn workspaces focus --all --production && \
    yarn pack --out /tmp/backstage-backend.tgz || true

# -----------------------------------------------------------------------------
# Stage 3: Runtime — imagem final minimalista
# Usa node:24-trixie-slim conforme BACKSTAGE-IMPLEMENTATION-PLAN.md secao 3
# ~1.1-1.5GB final conforme documentado
# -----------------------------------------------------------------------------
FROM node:24-trixie-slim AS runtime

# Instalar apenas dependencias de runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    dumb-init \
    && rm -rf /var/lib/apt/lists/*

# Criar usuario nao-root para seguranca (CIS Benchmark)
RUN groupadd --system --gid 1001 backstage && \
    useradd --system --uid 1001 --gid backstage --shell /bin/bash --home-dir /app backstage

WORKDIR /app

ENV NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=1024" \
    LOG_LEVEL=info \
    # Backstage app config - sobrescrito via Helm
    APP_CONFIG_app_baseUrl=https://backstage.staging.internal \
    APP_CONFIG_backend_baseUrl=https://backstage.staging.internal \
    APP_CONFIG_backend_listen_port=7007

# Copiar artefatos de build do stage anterior
COPY --from=build --chown=backstage:backstage /app/packages/backend/dist ./packages/backend/dist
COPY --from=build --chown=backstage:backstage /app/packages/app/dist ./packages/app/dist

# Copiar node_modules de producao
# (apenas as dependencias necessarias para runtime)
COPY --from=build --chown=backstage:backstage /app/node_modules ./node_modules
COPY --from=build --chown=backstage:backstage /app/packages/backend/node_modules ./packages/backend/node_modules

# Copiar package.json raiz (necessario para resolucao de workspaces)
COPY --chown=backstage:backstage package.json ./

# Porta do Backstage backend
EXPOSE 7007

# Usar dumb-init para signal handling correto em containers
# Permite graceful shutdown do Node.js via SIGTERM
USER backstage

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "packages/backend/dist/index.cjs"]

# -----------------------------------------------------------------------------
# Metadata da imagem (OCI Image Spec)
# -----------------------------------------------------------------------------
LABEL org.opencontainers.image.title="Backstage IDP" \
      org.opencontainers.image.version="1.48.0" \
      org.opencontainers.image.description="Backstage Internal Developer Platform - Platform Team" \
      org.opencontainers.image.vendor="Platform Engineering" \
      org.opencontainers.image.source="https://gitlab.staging.internal/platform/backstage-app" \
      org.opencontainers.image.base.name="node:24-trixie-slim" \
      backstage.io/version="1.48.0" \
      com.harbor.project="platform"
