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
