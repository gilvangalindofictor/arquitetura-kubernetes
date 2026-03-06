#!/usr/bin/env bash
# =============================================================================
# build.sh — Build da imagem Backstage para Harbor
# Imagem: harbor.staging.internal/platform/backstage:1.48.0
# Cluster: k8s-platform-prod (EKS us-east-1, conta 891377105802)
# ADR: ADR-055
#
# MODOS DE BUILD:
#   1. Kaniko (preferido) — build dentro do cluster Kubernetes, sem Docker daemon
#   2. Docker local — fallback para uso manual/desenvolvimento
#
# USO:
#   ./build.sh [--kaniko | --docker] [--push] [--dry-run]
#
# VARIAVEIS DE AMBIENTE NECESSARIAS (kaniko mode):
#   KUBECONFIG         — path para kubeconfig do cluster k8s-platform-prod
#   HARBOR_ROBOT_USER  — nome do robot account no Harbor (ex: robot$platform+builder)
#   HARBOR_ROBOT_SECRET — senha do robot account
#
# VARIAVEIS DE AMBIENTE NECESSARIAS (docker mode):
#   HARBOR_ROBOT_USER  — nome do robot account no Harbor
#   HARBOR_ROBOT_SECRET — senha do robot account
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Variaveis
# ---------------------------------------------------------------------------
HARBOR_REGISTRY="harbor.staging.internal"
IMAGE_REPO="platform/backstage"
IMAGE_TAG="1.48.0"
IMAGE_FULL="${HARBOR_REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG}"
IMAGE_LATEST="${HARBOR_REGISTRY}/${IMAGE_REPO}:latest"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE="${SCRIPT_DIR}/Dockerfile"
CONTEXT_DIR="${SCRIPT_DIR}"

BUILD_MODE=""
PUSH=false
DRY_RUN=false

# ---------------------------------------------------------------------------
# Funcoes auxiliares
# ---------------------------------------------------------------------------
log()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
warn() { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
err()  { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; exit 1; }

usage() {
  cat <<EOF
USO: $0 [--kaniko | --docker] [--push] [--dry-run]

  --kaniko    Usa kaniko para build dentro do cluster Kubernetes (recomendado CI)
  --docker    Usa Docker daemon local (desenvolvimento)
  --push      Faz push da imagem para o Harbor apos o build
  --dry-run   Exibe os comandos sem executar

VARIAVEIS DE AMBIENTE:
  KUBECONFIG          Path para kubeconfig (necessario --kaniko)
  HARBOR_ROBOT_USER   Robot account do Harbor
  HARBOR_ROBOT_SECRET Senha do robot account

EXEMPLOS:
  # Build local com push
  HARBOR_ROBOT_USER=robot\$platform+builder \\
  HARBOR_ROBOT_SECRET=<token> \\
  ./build.sh --docker --push

  # Build via Kaniko no cluster
  KUBECONFIG=~/.kube/k8s-platform-prod \\
  HARBOR_ROBOT_USER=robot\$platform+builder \\
  HARBOR_ROBOT_SECRET=<token> \\
  ./build.sh --kaniko --push
EOF
}

# ---------------------------------------------------------------------------
# Parsing de argumentos
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kaniko) BUILD_MODE="kaniko"; shift ;;
    --docker) BUILD_MODE="docker"; shift ;;
    --push)   PUSH=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) err "Argumento desconhecido: $1. Use --help para ajuda." ;;
  esac
done

# Auto-detectar modo se nao especificado
if [[ -z "$BUILD_MODE" ]]; then
  if command -v kubectl &>/dev/null && [[ -n "${KUBECONFIG:-}" ]]; then
    BUILD_MODE="kaniko"
    log "Modo auto-detectado: kaniko (kubectl disponivel e KUBECONFIG definido)"
  elif command -v docker &>/dev/null; then
    BUILD_MODE="docker"
    log "Modo auto-detectado: docker local"
  else
    err "Nenhum modo de build disponivel. Instale Docker ou configure kubectl + KUBECONFIG."
  fi
fi

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Validacoes
# ---------------------------------------------------------------------------
[[ -f "$DOCKERFILE" ]] || err "Dockerfile nao encontrado: $DOCKERFILE"
[[ -d "$CONTEXT_DIR" ]] || err "Contexto de build nao encontrado: $CONTEXT_DIR"

# ---------------------------------------------------------------------------
# BUILD MODE: Docker local
# ---------------------------------------------------------------------------
build_docker() {
  log "Iniciando build Docker local..."
  log "Imagem: $IMAGE_FULL"
  log "Contexto: $CONTEXT_DIR"

  run docker build \
    --file "$DOCKERFILE" \
    --tag "$IMAGE_FULL" \
    --tag "$IMAGE_LATEST" \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --label "build.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label "build.version=${IMAGE_TAG}" \
    --platform linux/amd64 \
    "$CONTEXT_DIR"

  log "Build concluido: $IMAGE_FULL"

  if [[ "$PUSH" == "true" ]]; then
    push_image
  fi
}

# ---------------------------------------------------------------------------
# BUILD MODE: Kaniko dentro do cluster Kubernetes
# ---------------------------------------------------------------------------
build_kaniko() {
  log "Iniciando build via Kaniko no cluster Kubernetes..."
  log "Imagem destino: $IMAGE_FULL"

  : "${KUBECONFIG:?Variavel KUBECONFIG nao definida}"
  : "${HARBOR_ROBOT_USER:?Variavel HARBOR_ROBOT_USER nao definida}"
  : "${HARBOR_ROBOT_SECRET:?Variavel HARBOR_ROBOT_SECRET nao definida}"

  NAMESPACE="staging-platform-backstage"
  JOB_NAME="backstage-image-build-$(date +%s)"
  KANIKO_SECRET="harbor-build-credentials"

  # Criar secret com credenciais do Harbor para o kaniko
  log "Criando secret de credenciais Harbor para Kaniko..."
  DOCKER_CONFIG=$(cat <<EOF | base64 -w0
{
  "auths": {
    "${HARBOR_REGISTRY}": {
      "username": "${HARBOR_ROBOT_USER}",
      "password": "${HARBOR_ROBOT_SECRET}",
      "auth": "$(echo -n "${HARBOR_ROBOT_USER}:${HARBOR_ROBOT_SECRET}" | base64 -w0)"
    }
  }
}
EOF
)

  run kubectl --kubeconfig="$KUBECONFIG" \
    -n "$NAMESPACE" \
    create secret generic "$KANIKO_SECRET" \
    --from-literal=config.json="$(echo "$DOCKER_CONFIG" | base64 -d)" \
    --dry-run=client -o yaml | \
    kubectl --kubeconfig="$KUBECONFIG" apply -f -

  # ConfigMap com o contexto de build (Dockerfile + arquivos necessarios)
  # Em producao, o kaniko deve buscar o contexto de um Git repo ou S3 bucket.
  # Para build manual, copiar arquivos para um PVC ou usar --context=git://...
  log "Criando Job Kaniko..."

  KANIKO_JOB_MANIFEST=$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: backstage-image-builder
    version: "${IMAGE_TAG}"
  annotations:
    build.platform.io/image: "${IMAGE_FULL}"
    build.platform.io/trigger: "manual"
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 1
  template:
    metadata:
      labels:
        app: backstage-image-builder
        sidecar.istio.io/inject: "false"
      annotations:
        linkerd.io/inject: disabled
    spec:
      restartPolicy: Never
      serviceAccountName: backstage

      initContainers:
        # Clone do repositorio backstage-app para o volume de contexto
        - name: git-clone
          image: alpine/git:latest
          command:
            - git
            - clone
            - --depth=1
            - --branch=main
            - https://gitlab.staging.internal/platform/backstage-app.git
            - /workspace
          volumeMounts:
            - name: build-context
              mountPath: /workspace
          env:
            - name: GIT_USERNAME
              value: "backstage-builder"
            - name: GIT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: backstage-secrets
                  key: gitlab-token

      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:v1.23.2
          args:
            - "--context=/workspace"
            - "--dockerfile=/workspace/docker/Dockerfile"
            - "--destination=${IMAGE_FULL}"
            - "--destination=${IMAGE_LATEST}"
            - "--cache=true"
            - "--cache-repo=${HARBOR_REGISTRY}/platform/backstage-cache"
            - "--compressed-caching=false"
            - "--snapshot-mode=redo"
            - "--use-new-run"
            - "--push-retry=3"
            - "--log-format=text"
          volumeMounts:
            - name: kaniko-secret
              mountPath: /kaniko/.docker
            - name: build-context
              mountPath: /workspace
          resources:
            requests:
              cpu: 500m
              memory: 2Gi
            limits:
              cpu: 2000m
              memory: 4Gi

      volumes:
        - name: kaniko-secret
          secret:
            secretName: ${KANIKO_SECRET}
            items:
              - key: config.json
                path: config.json
        - name: build-context
          emptyDir:
            sizeLimit: 5Gi
EOF
)

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] kubectl apply -f - <<< kaniko job manifest"
    echo "$KANIKO_JOB_MANIFEST"
    return
  fi

  echo "$KANIKO_JOB_MANIFEST" | kubectl --kubeconfig="$KUBECONFIG" apply -f -

  log "Job Kaniko criado: $JOB_NAME"
  log "Acompanhando execucao..."

  # Aguardar pod do Job ficar Running
  kubectl --kubeconfig="$KUBECONFIG" \
    -n "$NAMESPACE" \
    wait --for=condition=Ready pod \
    --selector="job-name=${JOB_NAME}" \
    --timeout=120s || warn "Pod ainda nao pronto — verificar manualmente"

  # Seguir logs
  kubectl --kubeconfig="$KUBECONFIG" \
    -n "$NAMESPACE" \
    logs -f "job/${JOB_NAME}" || true

  # Verificar resultado do Job
  JOB_STATUS=$(kubectl --kubeconfig="$KUBECONFIG" \
    -n "$NAMESPACE" \
    get job "${JOB_NAME}" \
    -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')

  if [[ "$JOB_STATUS" == "True" ]]; then
    log "Build Kaniko concluido com sucesso!"
    log "Imagem disponivel: $IMAGE_FULL"
  else
    err "Build Kaniko falhou. Verificar logs: kubectl -n ${NAMESPACE} logs job/${JOB_NAME}"
  fi

  # Limpar secret temporario
  kubectl --kubeconfig="$KUBECONFIG" \
    -n "$NAMESPACE" \
    delete secret "$KANIKO_SECRET" --ignore-not-found=true
}

# ---------------------------------------------------------------------------
# Push da imagem (apenas para modo docker local)
# ---------------------------------------------------------------------------
push_image() {
  : "${HARBOR_ROBOT_USER:?Variavel HARBOR_ROBOT_USER nao definida}"
  : "${HARBOR_ROBOT_SECRET:?Variavel HARBOR_ROBOT_SECRET nao definida}"

  log "Autenticando no Harbor..."
  run echo "$HARBOR_ROBOT_SECRET" | docker login "$HARBOR_REGISTRY" \
    -u "$HARBOR_ROBOT_USER" \
    --password-stdin

  log "Fazendo push da imagem..."
  run docker push "$IMAGE_FULL"
  run docker push "$IMAGE_LATEST"

  log "Push concluido: $IMAGE_FULL"
}

# ---------------------------------------------------------------------------
# Verificar se imagem ja existe no Harbor
# ---------------------------------------------------------------------------
check_image_exists() {
  log "Verificando se imagem ja existe no Harbor..."
  log "Endpoint: https://${HARBOR_REGISTRY}/api/v2.0/projects/platform/repositories/backstage/artifacts?q=tags=${IMAGE_TAG}"

  if command -v curl &>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      --connect-timeout 5 \
      "https://${HARBOR_REGISTRY}/v2/${IMAGE_REPO}/manifests/${IMAGE_TAG}" 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" == "200" ]]; then
      log "AVISO: Imagem ${IMAGE_FULL} JA EXISTE no Harbor."
      log "Use uma nova tag ou delete a imagem existente antes de fazer push."
      read -rp "Continuar mesmo assim? (s/N): " CONFIRM
      [[ "${CONFIRM,,}" == "s" ]] || exit 0
    elif [[ "$HTTP_CODE" == "000" ]]; then
      warn "Harbor nao acessivel de fora do cluster (esperado em ambiente interno)."
      warn "O build continuara normalmente — verificacao de existencia sera ignorada."
    else
      log "Imagem nao encontrada no Harbor (HTTP $HTTP_CODE). Prosseguindo com o build."
    fi
  else
    warn "curl nao encontrado — pulando verificacao de existencia da imagem."
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "=========================================="
log "Backstage Image Builder"
log "Versao: ${IMAGE_TAG}"
log "Destino: ${IMAGE_FULL}"
log "Modo: ${BUILD_MODE}"
log "Push: ${PUSH}"
log "Dry-run: ${DRY_RUN}"
log "=========================================="

check_image_exists

case "$BUILD_MODE" in
  kaniko) build_kaniko ;;
  docker) build_docker ;;
  *) err "Modo de build invalido: $BUILD_MODE" ;;
esac

log "Processo finalizado."
