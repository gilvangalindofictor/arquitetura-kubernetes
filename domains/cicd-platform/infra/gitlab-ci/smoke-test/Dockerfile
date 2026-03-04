# =============================================================================
# GAP-005: Smoke Test Image
# =============================================================================
# Imagem minimalista para validar a cadeia CI/CD end-to-end da plataforma.
# Tamanho alvo: < 10MB (alpine:3.19 base = ~7MB)
#
# Labels obrigatórios conforme Kyverno ClusterPolicy require-labels
# (apply.kyverno.io/version=v1, type=enforce)
# =============================================================================
FROM alpine:3.19

# Kyverno mandatory labels (ClusterPolicy: require-labels)
LABEL app.kubernetes.io/name="smoke-test"
LABEL app.kubernetes.io/part-of="k8s-platform"
LABEL app.kubernetes.io/managed-by="gitlab-ci"
LABEL app.kubernetes.io/component="validation"

# Provenance labels (adicionados pelo kaniko durante o build)
# --label git.commit=${CI_COMMIT_SHA}
# --label git.ref=${CI_COMMIT_REF_NAME}
# --label build.pipeline=${CI_PIPELINE_ID}
# --label gap=GAP-005

# Metadados de documentação
LABEL org.opencontainers.image.title="smoke-test-ci"
LABEL org.opencontainers.image.description="GAP-005 end-to-end CI/CD validation image"
LABEL org.opencontainers.image.vendor="k8s-platform"
LABEL org.opencontainers.image.source="gitlab.staging.internal/smoke-test-ci"

# Instalar curl para health check em testes de integração futuros
RUN apk add --no-cache curl=~8.5 && \
    echo "smoke-test: GAP-005 CI/CD validation image" > /smoke-test.txt && \
    echo "build_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /smoke-test.txt && \
    echo "base_image=alpine:3.19" >> /smoke-test.txt

# Usuário não-root (boa prática de segurança + Kyverno policy)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

WORKDIR /app

# Health check simples
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD cat /smoke-test.txt || exit 1

CMD ["cat", "/smoke-test.txt"]
