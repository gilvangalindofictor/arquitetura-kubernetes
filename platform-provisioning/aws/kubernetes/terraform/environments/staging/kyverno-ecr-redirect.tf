################################################################################
# Kyverno ClusterPolicy — Redirect Public Registries to ECR Pull-Through Cache
################################################################################
# Descricao: Aplica ClusterPolicy que reescreve imagens de registries publicos
#            (docker.io, quay.io, ghcr.io, registry.k8s.io) para ECR
#            Pull-Through Cache, resolvendo Docker Hub rate limit (429).
#
# Registries reescritos:
#   docker.io/*       -> 891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/*
#   (bare images)     -> 891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/library/*
#   quay.io/*         -> 891377105802.dkr.ecr.us-east-1.amazonaws.com/quay/*
#   ghcr.io/*         -> 891377105802.dkr.ecr.us-east-1.amazonaws.com/ghcr/*
#   registry.k8s.io/* -> 891377105802.dkr.ecr.us-east-1.amazonaws.com/k8s/*
#
# Excluidos: kube-system, kube-public, kube-node-lease, imagens ECR, Harbor
#
# Pre-requisitos:
#   - ECR Pull-Through Cache rules (modulo ecr-pull-through-cache)
#   - Kyverno v3.2.7+ instalado (staging-governance-kyverno)
#
# GAPs: GAP-SEC-REGISTRY-01/02/03
# Ref:  ecr-pull-through-cache-architecture.md (Fase 3)
# YAML: domains/security/kyverno/policies/redirect-public-registries-to-ecr.yaml
################################################################################

resource "kubectl_manifest" "kyverno_redirect_public_registries_to_ecr" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: redirect-public-registries-to-ecr
      labels:
        app.kubernetes.io/managed-by: terraform
        governance.platform/policy: ecr-registry-redirect
        governance.platform/gap: GAP-SEC-REGISTRY-03
      annotations:
        policies.kyverno.io/title: Redirect Public Registries to ECR Pull-Through Cache
        policies.kyverno.io/category: Security & Compliance
        policies.kyverno.io/severity: medium
        policies.kyverno.io/subject: Pod
        policies.kyverno.io/description: >-
          Reescreve referencias de imagens de registries publicos (docker.io, quay.io,
          ghcr.io, registry.k8s.io) para ECR Pull-Through Cache. Resolve Docker Hub
          rate limit (429 Too Many Requests) e garante pulls intra-regiao sem custo
          de data transfer. Imagens ja apontando para ECR ou Harbor interno nao sao
          alteradas. Ref: GAP-SEC-REGISTRY-01/02/03.
    spec:
      background: false
      rules:
        # ---- REGRA 1: docker.io/* -> ECR docker-hub (containers) ---------------
        - name: redirect-docker-io-containers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
          mutate:
            foreach:
              - list: "request.object.spec.containers"
                preconditions:
                  all:
                    - key: "{{ element.image }}"
                      operator: Equals
                      value: "docker.io/*"
                patchStrategicMerge:
                  spec:
                    containers:
                      - name: "{{ element.name }}"
                        image: "{{ regex_replace_all('^docker\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/$1') }}"

        # ---- REGRA 2: docker.io/* -> ECR docker-hub (initContainers) ---------
        - name: redirect-docker-io-initcontainers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
              - key: "{{ request.object.spec.initContainers[] || `[]` | length(@) }}"
                operator: GreaterThanOrEquals
                value: 1
          mutate:
            foreach:
              - list: "request.object.spec.initContainers"
                preconditions:
                  all:
                    - key: "{{ element.image }}"
                      operator: Equals
                      value: "docker.io/*"
                patchStrategicMerge:
                  spec:
                    initContainers:
                      - name: "{{ element.name }}"
                        image: "{{ regex_replace_all('^docker\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/$1') }}"

        # ---- REGRA 3: bare images -> ECR docker-hub (containers) ---------------
        # Imagens sem prefixo: nginx:latest -> docker-hub/library/nginx:latest
        - name: redirect-bare-images-containers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
          mutate:
            foreach:
              - list: "request.object.spec.containers"
                preconditions:
                  all:
                    - key: "{{ regex_match('^[a-zA-Z0-9][a-zA-Z0-9_.-]*(:[a-zA-Z0-9._-]+)?$', element.image) }}"
                      operator: Equals
                      value: true
                patchStrategicMerge:
                  spec:
                    containers:
                      - name: "{{ element.name }}"
                        image: "891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/library/{{ element.image }}"

        # ---- REGRA 4: bare images -> ECR docker-hub (initContainers) ---------
        - name: redirect-bare-images-initcontainers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
              - key: "{{ request.object.spec.initContainers[] || `[]` | length(@) }}"
                operator: GreaterThanOrEquals
                value: 1
          mutate:
            foreach:
              - list: "request.object.spec.initContainers"
                preconditions:
                  all:
                    - key: "{{ regex_match('^[a-zA-Z0-9][a-zA-Z0-9_.-]*(:[a-zA-Z0-9._-]+)?$', element.image) }}"
                      operator: Equals
                      value: true
                patchStrategicMerge:
                  spec:
                    initContainers:
                      - name: "{{ element.name }}"
                        image: "891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/library/{{ element.image }}"

        # ---- REGRA 5: quay.io/* -> ECR (containers) ---------------------------
        - name: redirect-quay-containers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
          mutate:
            foreach:
              - list: "request.object.spec.containers"
                preconditions:
                  all:
                    - key: "{{ element.image }}"
                      operator: Equals
                      value: "quay.io/*"
                patchStrategicMerge:
                  spec:
                    containers:
                      - name: "{{ element.name }}"
                        image: "{{ regex_replace_all('^quay\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/quay/$1') }}"

        # ---- REGRA 6: quay.io/* -> ECR (initContainers) -----------------------
        - name: redirect-quay-initcontainers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
              - key: "{{ request.object.spec.initContainers[] || `[]` | length(@) }}"
                operator: GreaterThanOrEquals
                value: 1
          mutate:
            foreach:
              - list: "request.object.spec.initContainers"
                preconditions:
                  all:
                    - key: "{{ element.image }}"
                      operator: Equals
                      value: "quay.io/*"
                patchStrategicMerge:
                  spec:
                    initContainers:
                      - name: "{{ element.name }}"
                        image: "{{ regex_replace_all('^quay\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/quay/$1') }}"

        # ---- REGRA 7: ghcr.io/* -> ECR (containers) ---------------------------
        # DEPENDENCIA: enable_ghcr=false (main.tf) significa que NAO ha pull-through
        #   rule para GHCR no ECR. Esta regra redireciona ghcr.io → ECR ghcr/ prefix,
        #   mas sem a pull-through rule o pull falha (ErrImagePull).
        # GAP-KYVERNO-GHCR-001 (2026-03-23): A excecao para ghcr.io/jkroepke/kube-webhook-certgen
        #   esta codificada em kubectl_manifest.kyverno_exception_prom_admission_certgen abaixo.
        #   Essa imagem e redirecionada para registry.k8s.io/ingress-nginx/kube-webhook-certgen
        #   via ECR pull-through k8s/ (ativo) pelo fix GAP-PROM-ADM-001 no modulo kube-prometheus-stack.
        # NOTA: Quando enable_ghcr=true, remover o PolicyException abaixo (pull-through GHCR estara ativo).
        - name: redirect-ghcr-containers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
          mutate:
            foreach:
              - list: "request.object.spec.containers"
                preconditions:
                  all:
                    - key: "{{ element.image }}"
                      operator: Equals
                      value: "ghcr.io/*"
                patchStrategicMerge:
                  spec:
                    containers:
                      - name: "{{ element.name }}"
                        image: "{{ regex_replace_all('^ghcr\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/ghcr/$1') }}"

        # ---- REGRA 8: ghcr.io/* -> ECR (initContainers) -----------------------
        # Mesma dependencia que REGRA 7 — ver comentario acima (GAP-KYVERNO-GHCR-001).
        - name: redirect-ghcr-initcontainers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
              - key: "{{ request.object.spec.initContainers[] || `[]` | length(@) }}"
                operator: GreaterThanOrEquals
                value: 1
          mutate:
            foreach:
              - list: "request.object.spec.initContainers"
                preconditions:
                  all:
                    - key: "{{ element.image }}"
                      operator: Equals
                      value: "ghcr.io/*"
                patchStrategicMerge:
                  spec:
                    initContainers:
                      - name: "{{ element.name }}"
                        image: "{{ regex_replace_all('^ghcr\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/ghcr/$1') }}"

        # ---- REGRA 9: registry.k8s.io/* -> ECR (containers) -------------------
        - name: redirect-k8s-registry-containers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
          mutate:
            foreach:
              - list: "request.object.spec.containers"
                preconditions:
                  all:
                    - key: "{{ element.image }}"
                      operator: Equals
                      value: "registry.k8s.io/*"
                patchStrategicMerge:
                  spec:
                    containers:
                      - name: "{{ element.name }}"
                        image: "{{ regex_replace_all('^registry\\.k8s\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/k8s/$1') }}"

        # ---- REGRA 10: registry.k8s.io/* -> ECR (initContainers) ---------------
        - name: redirect-k8s-registry-initcontainers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
              - key: "{{ request.object.spec.initContainers[] || `[]` | length(@) }}"
                operator: GreaterThanOrEquals
                value: 1
          mutate:
            foreach:
              - list: "request.object.spec.initContainers"
                preconditions:
                  all:
                    - key: "{{ element.image }}"
                      operator: Equals
                      value: "registry.k8s.io/*"
                patchStrategicMerge:
                  spec:
                    initContainers:
                      - name: "{{ element.name }}"
                        image: "{{ regex_replace_all('^registry\\.k8s\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/k8s/$1') }}"

        # ---- REGRA 11: Docker Hub org/image -> ECR docker-hub (containers) -----
        # Captura: hashicorp/vault:1.15.4, grafana/grafana:11.x, etc.
        - name: redirect-docker-hub-org-containers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
          mutate:
            foreach:
              - list: "request.object.spec.containers"
                preconditions:
                  all:
                    - key: "{{ regex_match('^[a-zA-Z0-9][a-zA-Z0-9_-]*/[a-zA-Z0-9][a-zA-Z0-9_./-]*(:[a-zA-Z0-9._-]+)?$', element.image) }}"
                      operator: Equals
                      value: true
                    - key: "{{ regex_match('.*\\.dkr\\.ecr\\..*\\.amazonaws\\.com/.*', element.image) }}"
                      operator: Equals
                      value: false
                    - key: "{{ regex_match('^harbor-core\\.harbor-system\\.svc\\.cluster\\.local.*', element.image) }}"
                      operator: Equals
                      value: false
                    - key: "{{ regex_match('^harbor\\.staging\\.internal.*', element.image) }}"
                      operator: Equals
                      value: false
                patchStrategicMerge:
                  spec:
                    containers:
                      - name: "{{ element.name }}"
                        image: "891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/{{ element.image }}"

        # ---- REGRA 12: Docker Hub org/image -> ECR docker-hub (initContainers)
        - name: redirect-docker-hub-org-initcontainers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
          preconditions:
            all:
              - key: "{{ request.operation || 'BACKGROUND' }}"
                operator: AnyIn
                value:
                  - CREATE
                  - UPDATE
              - key: "{{ request.object.spec.initContainers[] || `[]` | length(@) }}"
                operator: GreaterThanOrEquals
                value: 1
          mutate:
            foreach:
              - list: "request.object.spec.initContainers"
                preconditions:
                  all:
                    - key: "{{ regex_match('^[a-zA-Z0-9][a-zA-Z0-9_-]*/[a-zA-Z0-9][a-zA-Z0-9_./-]*(:[a-zA-Z0-9._-]+)?$', element.image) }}"
                      operator: Equals
                      value: true
                    - key: "{{ regex_match('.*\\.dkr\\.ecr\\..*\\.amazonaws\\.com/.*', element.image) }}"
                      operator: Equals
                      value: false
                    - key: "{{ regex_match('^harbor-core\\.harbor-system\\.svc\\.cluster\\.local.*', element.image) }}"
                      operator: Equals
                      value: false
                    - key: "{{ regex_match('^harbor\\.staging\\.internal.*', element.image) }}"
                      operator: Equals
                      value: false
                patchStrategicMerge:
                  spec:
                    initContainers:
                      - name: "{{ element.name }}"
                        image: "891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/{{ element.image }}"
  YAML

  # Kyverno deve estar instalado antes de aplicar ClusterPolicies
  # depends_on = [helm_release.kyverno]  # Descomentar quando Kyverno estiver gerenciado por TF

  lifecycle {
    ignore_changes = [
      # Kyverno controller pode adicionar annotations/labels de status
      yaml_body,
    ]
  }
}

################################################################################
# GAP-KYVERNO-GHCR-001 (2026-03-23): PolicyException — certgen admission webhook
################################################################################
# Problema: enable_ghcr=false → sem ECR pull-through para GHCR. As regras 7/8
#   acima redirecionam ghcr.io/* → ECR ghcr/ prefix, mas o prefix nao existe
#   no ECR → ErrImagePull no Job do admission webhook do kube-prometheus-stack.
#
# Solucao: PolicyException exclui ghcr.io/jkroepke/kube-webhook-certgen das
#   regras de redirect GHCR. O modulo kube-prometheus-stack (GAP-PROM-ADM-001)
#   sobrescreve a imagem para registry.k8s.io/ingress-nginx/kube-webhook-certgen,
#   que cai na REGRA 9/10 (k8s/ pull-through — ativo) automaticamente.
#
# Ciclo de vida:
#   - enable_ghcr=false: esta excecao DEVE existir
#   - enable_ghcr=true:  remover este recurso (pull-through GHCR estara ativo)
#
# Ref: GAP-PROM-ADM-001 (modules/kube-prometheus-stack/main.tf)
################################################################################

resource "kubectl_manifest" "kyverno_exception_prom_admission_certgen" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v2
    kind: PolicyException
    metadata:
      name: exception-prom-admission-certgen-ghcr
      namespace: staging-observability-monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        governance.platform/gap: GAP-KYVERNO-GHCR-001
      annotations:
        policies.kyverno.io/title: Exception — kube-webhook-certgen GHCR redirect
        policies.kyverno.io/description: >-
          Exclui ghcr.io/jkroepke/kube-webhook-certgen das regras de redirect GHCR
          (redirect-ghcr-containers / redirect-ghcr-initcontainers) enquanto
          enable_ghcr=false. A imagem e substituida pelo override GAP-PROM-ADM-001
          (registry.k8s.io/ingress-nginx/kube-webhook-certgen via ECR k8s/ ativo).
          Remover quando enable_ghcr=true.
    spec:
      exceptions:
        - policyName: redirect-public-registries-to-ecr
          ruleNames:
            - redirect-ghcr-containers
            - redirect-ghcr-initcontainers
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - staging-observability-monitoring
              selector:
                matchExpressions:
                  - key: batch.kubernetes.io/job-name
                    operator: Exists
              images:
                containers:
                  - "ghcr.io/jkroepke/kube-webhook-certgen*"
                initContainers:
                  - "ghcr.io/jkroepke/kube-webhook-certgen*"
  YAML

  depends_on = [kubectl_manifest.kyverno_redirect_public_registries_to_ecr]

  lifecycle {
    ignore_changes = [
      yaml_body,
    ]
  }
}
