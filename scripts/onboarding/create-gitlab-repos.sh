#!/bin/bash
# Cria repositórios GitLab na estrutura Corporate Domains
# Referência: ADR-047, ADR-048, ADR-049
# Uso: ./create-gitlab-repos.sh <produto> <domain> <env>

set -euo pipefail

PRODUTO="$1"
DOMAIN="$2"
ENV="$3"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[GITLAB]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[GITLAB]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[GITLAB]${NC} $1"
}

# Validações
log_info "Validando parâmetros..."

if ! [[ "$PRODUTO" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
    echo "❌ Nome do produto inválido: '$PRODUTO'"
    exit 1
fi

# GitLab configuration
GITLAB_HOST="${GITLAB_HOST:-gitlab.empresa.com}"
GITLAB_API_URL="https://${GITLAB_HOST}/api/v4"

# Estrutura GitLab (ADR-047)
# corporate-domains/{domain}/{produto}/
CORPORATE_DOMAINS_GROUP="corporate-domains"
DOMAIN_GROUP="${CORPORATE_DOMAINS_GROUP}/${DOMAIN}"
PRODUCT_GROUP="${DOMAIN_GROUP}/${PRODUTO}"

log_info "GitLab Host: $GITLAB_HOST"
log_info "Estrutura: $PRODUCT_GROUP"

# Verificar se gitlab CLI está instalado e autenticado
if ! command -v gitlab &> /dev/null; then
    log_warning "GitLab CLI não encontrado. Instale: pip install python-gitlab-cli"
    log_info "Alternativamente, use a API diretamente com curl"
    exit 1
fi

# Verificar autenticação
if ! gitlab current-user get &> /dev/null; then
    echo "❌ GitLab CLI não autenticado"
    echo "Configure: export GITLAB_PRIVATE_TOKEN=<seu-token>"
    exit 1
fi

log_success "GitLab CLI autenticado"

# ====================
# Criar Grupo do Produto (se não existir)
# ====================
log_info "Criando grupo do produto: $PRODUCT_GROUP"

# Obter ID do grupo de domínio
DOMAIN_GROUP_ID=$(gitlab group list --search "${DOMAIN}" --in-group "${CORPORATE_DOMAINS_GROUP}" --json | jq -r '.[0].id' 2>/dev/null || echo "")

if [ -z "$DOMAIN_GROUP_ID" ]; then
    echo "❌ Grupo de domínio não encontrado: $DOMAIN_GROUP"
    echo "Crie primeiro: gitlab group create --name ${DOMAIN} --path ${DOMAIN} --parent-id <corporate-domains-id>"
    exit 1
fi

log_info "Domain Group ID: $DOMAIN_GROUP_ID"

# Criar grupo do produto
PRODUCT_GROUP_ID=$(gitlab group list --search "${PRODUTO}" --in-group "${DOMAIN}" --json 2>/dev/null | jq -r '.[0].id' || echo "")

if [ -z "$PRODUCT_GROUP_ID" ]; then
    log_info "Criando novo grupo: $PRODUTO"

    gitlab group create \
        --name "$PRODUTO" \
        --path "$PRODUTO" \
        --parent-id "$DOMAIN_GROUP_ID" \
        --visibility private \
        --description "Produto: ${PRODUTO} | Domínio: ${DOMAIN} | Governance: ADR-047"

    # Obter ID do grupo recém-criado
    sleep 2
    PRODUCT_GROUP_ID=$(gitlab group list --search "${PRODUTO}" --in-group "${DOMAIN}" --json | jq -r '.[0].id')
    log_success "Grupo criado: $PRODUCT_GROUP (ID: $PRODUCT_GROUP_ID)"
else
    log_warning "Grupo já existe: $PRODUTO (ID: $PRODUCT_GROUP_ID)"
fi

# ====================
# Criar Repositório da Aplicação
# ====================
APP_REPO_NAME="$PRODUTO"
log_info "Criando repositório da aplicação: $APP_REPO_NAME"

# Verificar se repo já existe
EXISTING_REPO=$(gitlab project list --in-group "$PRODUCT_GROUP_ID" --search "$APP_REPO_NAME" --json 2>/dev/null | jq -r '.[0].id' || echo "")

if [ -n "$EXISTING_REPO" ]; then
    log_warning "Repositório já existe: $APP_REPO_NAME (ID: $EXISTING_REPO)"
else
    gitlab project create \
        --name "$APP_REPO_NAME" \
        --path "$APP_REPO_NAME" \
        --namespace-id "$PRODUCT_GROUP_ID" \
        --visibility private \
        --description "Aplicação: ${PRODUTO} | Domínio: ${DOMAIN}" \
        --initialize-with-readme \
        --default-branch main

    log_success "Repositório criado: $APP_REPO_NAME"
fi

# ====================
# Criar Repositório GitOps
# ====================
GITOPS_REPO_NAME="${PRODUTO}-gitops"
log_info "Criando repositório GitOps: $GITOPS_REPO_NAME"

# Verificar se repo já existe
EXISTING_GITOPS=$(gitlab project list --in-group "$PRODUCT_GROUP_ID" --search "$GITOPS_REPO_NAME" --json 2>/dev/null | jq -r '.[0].id' || echo "")

if [ -n "$EXISTING_GITOPS" ]; then
    log_warning "Repositório já existe: $GITOPS_REPO_NAME (ID: $EXISTING_GITOPS)"
else
    gitlab project create \
        --name "$GITOPS_REPO_NAME" \
        --path "$GITOPS_REPO_NAME" \
        --namespace-id "$PRODUCT_GROUP_ID" \
        --visibility private \
        --description "GitOps: ${PRODUTO} | Manifests Kubernetes | ArgoCD" \
        --initialize-with-readme \
        --default-branch main

    log_success "Repositório criado: $GITOPS_REPO_NAME"
fi

# ====================
# Criar estrutura inicial no repo GitOps
# ====================
log_info "Criando estrutura inicial no repositório GitOps..."

# Clonar repo temporariamente
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

git clone "git@${GITLAB_HOST}:${PRODUCT_GROUP}/${GITOPS_REPO_NAME}.git"
cd "$GITOPS_REPO_NAME"

# Criar estrutura de diretórios (ADR-048)
mkdir -p {base,overlays/{dev,staging,prod}}

# Criar base/kustomization.yaml
cat > base/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Referência: ADR-048 - GitOps Structure
# Base manifests para ${PRODUTO}

resources:
- deployment.yaml
- service.yaml

commonLabels:
  app.kubernetes.io/name: ${PRODUTO}
  app.kubernetes.io/managed-by: argocd
  domain: ${DOMAIN}
EOF

# Criar base/deployment.yaml (template)
cat > base/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${PRODUTO}
  labels:
    app.kubernetes.io/name: ${PRODUTO}
    app.kubernetes.io/part-of: ${PRODUTO}
    app.kubernetes.io/component: application
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${PRODUTO}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${PRODUTO}
        app.kubernetes.io/part-of: ${PRODUTO}
        domain: ${DOMAIN}
        environment: PLACEHOLDER
    spec:
      containers:
      - name: ${PRODUTO}
        image: registry.empresa.com/${DOMAIN}/${PRODUTO}:latest
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: ENVIRONMENT
          value: PLACEHOLDER
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
EOF

# Criar base/service.yaml
cat > base/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${PRODUTO}
  labels:
    app.kubernetes.io/name: ${PRODUTO}
    app.kubernetes.io/component: application
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app.kubernetes.io/name: ${PRODUTO}
EOF

# Criar overlays para cada ambiente
for overlay_env in dev staging prod; do
    cat > overlays/${overlay_env}/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Referência: ADR-048 - Environment: ${overlay_env}

bases:
- ../../base

namespace: ${overlay_env}-${DOMAIN}-${PRODUTO}

commonLabels:
  environment: ${overlay_env}

patchesStrategicMerge:
- deployment-patch.yaml

images:
- name: registry.empresa.com/${DOMAIN}/${PRODUTO}
  newTag: ${overlay_env}-latest
EOF

    cat > overlays/${overlay_env}/deployment-patch.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${PRODUTO}
spec:
  replicas: $([ "$overlay_env" = "prod" ] && echo "3" || [ "$overlay_env" = "staging" ] && echo "2" || echo "1")
  template:
    metadata:
      labels:
        environment: ${overlay_env}
    spec:
      containers:
      - name: ${PRODUTO}
        env:
        - name: ENVIRONMENT
          value: ${overlay_env}
EOF
done

# Criar README.md
cat > README.md <<EOF
# ${PRODUTO} - GitOps Repository

Repositório GitOps para deployment da aplicação **${PRODUTO}** no Kubernetes.

## 📁 Estrutura

\`\`\`
.
├── base/                   # Manifests base (comum a todos ambientes)
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/               # Customizações por ambiente
    ├── dev/
    ├── staging/
    └── prod/
\`\`\`

## 🚀 Deploy

### ArgoCD (Automático)
Commits na branch \`main\` disparam sync automático no ArgoCD.

### Manual (Kustomize)
\`\`\`bash
# Dev
kubectl apply -k overlays/dev/

# Staging
kubectl apply -k overlays/staging/

# Production
kubectl apply -k overlays/prod/
\`\`\`

## 📋 Governança

- **Domínio**: ${DOMAIN}
- **Produto**: ${PRODUTO}
- **Referências**: ADR-047, ADR-048, ADR-049
- **Namespace Pattern**: \`{env}-${DOMAIN}-${PRODUTO}\`

## 🔗 Links

- **App Repo**: https://${GITLAB_HOST}/${PRODUCT_GROUP}/${PRODUTO}
- **ArgoCD**: https://argocd.empresa.com/applications/${PRODUTO}
- **Grafana**: https://grafana.empresa.com/d/${PRODUTO}
EOF

# Commit e push
git add .
git commit -m "feat: Initial GitOps structure

- Base manifests (Deployment, Service)
- Overlays for dev, staging, prod environments
- Kustomize configuration per ADR-048

Co-Authored-By: Governance Onboarding <governance@empresa.com>"

git push origin main

log_success "Estrutura GitOps criada e pushed"

# Cleanup
cd /
rm -rf "$TEMP_DIR"

# ====================
# Configurar Protected Branches (ADR-049)
# ====================
log_info "Configurando protected branches..."

# Proteger branch main em ambos repos
for repo in "$APP_REPO_NAME" "$GITOPS_REPO_NAME"; do
    PROJECT_ID=$(gitlab project list --in-group "$PRODUCT_GROUP_ID" --search "$repo" --json | jq -r '.[0].id')

    if [ -n "$PROJECT_ID" ]; then
        gitlab project-protected-branch create \
            --project-id "$PROJECT_ID" \
            --name main \
            --push-access-level 30 \
            --merge-access-level 30 \
            --allow-force-push false \
            2>/dev/null || log_warning "Protected branch já configurado: $repo"
    fi
done

log_success "Protected branches configurados"

# ====================
# Sumário
# ====================
echo ""
log_success "========================================="
log_success "Repositórios GitLab Criados!"
log_success "========================================="
echo ""
log_info "Estrutura:"
log_info "  ${CORPORATE_DOMAINS_GROUP}/"
log_info "  └── ${DOMAIN}/"
log_info "      └── ${PRODUTO}/"
log_info "          ├── ${PRODUTO}         (aplicação)"
log_info "          └── ${PRODUTO}-gitops  (manifests k8s)"
echo ""
log_info "URLs:"
log_info "  App:    https://${GITLAB_HOST}/${PRODUCT_GROUP}/${PRODUTO}"
log_info "  GitOps: https://${GITLAB_HOST}/${PRODUCT_GROUP}/${GITOPS_REPO_NAME}"
echo ""
log_info "Clone:"
log_info "  git clone git@${GITLAB_HOST}:${PRODUCT_GROUP}/${PRODUTO}.git"
log_info "  git clone git@${GITLAB_HOST}:${PRODUCT_GROUP}/${GITOPS_REPO_NAME}.git"
echo ""
log_info "Próximos passos:"
log_info "  1. Configure CI/CD no repo app (.gitlab-ci.yml)"
log_info "  2. Build e push primeira imagem Docker"
log_info "  3. Crie ArgoCD Application apontando para ${GITOPS_REPO_NAME}"
echo ""
log_success "========================================="
