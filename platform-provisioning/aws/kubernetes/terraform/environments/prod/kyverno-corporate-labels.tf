################################################################################
# Kyverno ClusterPolicy — Inject Corporate Labels in prod-* Namespaces
################################################################################
# Descricao: Injeta automaticamente labels corporativos obrigatorios em todos
#            os recursos dos namespaces prod-*. Necessario para Helm charts que
#            nao definem todos os labels exigidos pela governanca corporativa.
#
# Labels injetados:
#   app.kubernetes.io/name    -> request.namespace (se ausente)
#   app.kubernetes.io/part-of -> k8s-platform (se ausente)
#   domain                    -> platform
#   environment               -> prod
#   owner                     -> platform-team
#
# Namespaces cobertos (todos os namespaces prod-*):
#   prod-security-vault, prod-security-externalsecrets,
#   prod-platform-keycloak, prod-platform-argocd, prod-platform-harbor,
#   prod-platform-sonarqube, prod-platform-backstage,
#   prod-observability-monitoring, prod-data-services, prod-data-rabbitmq
#
# Regras:
#   inject-labels-pods-and-services — Pod, Service, ConfigMap, Secret, ServiceAccount
#   inject-labels-workloads         — Deployment, StatefulSet, DaemonSet, Job
#
# GAPs:
#   GAP-KYVERNO-RABBITMQ-001 (2026-03-23): prod-data-rabbitmq adicionado apos
#     RabbitmqCluster ficar ~9min RECONCILESUCCESS=False (Services sem labels).
#     Patch emergencial via kubectl patch aplicado. Codificado aqui para IaC.
#
# ATENCAO: Este arquivo nao foi gerenciado por TF desde a criacao (kubectl apply).
#   Proximo passo: terraform import kubectl_manifest.kyverno_inject_corporate_labels_prod
#   Resource address: kubectl_manifest.kyverno_inject_corporate_labels_prod
#   Import ID: apiVersion=kyverno.io/v1,kind=ClusterPolicy,name=inject-corporate-labels-prod-namespaces
################################################################################

resource "kubectl_manifest" "kyverno_inject_corporate_labels_prod" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: inject-corporate-labels-prod-namespaces
      annotations:
        policies.kyverno.io/title: "Inject Corporate Labels for prod namespaces"
        policies.kyverno.io/category: "Corporate Governance"
        policies.kyverno.io/description: >-
          Automatically injects required corporate labels into all resources in
          prod-* namespaces. Required for Helm charts that don't set all corporate
          labels.
        governance-exception-issue: "PROD-SETUP"
        governance-exception-expires: "2027-03-19"
    spec:
      validationFailureAction: Audit
      background: true
      admission: true
      emitWarning: false
      rules:
        # ---- REGRA 1: Pod, Service, ConfigMap, Secret, ServiceAccount -----------
        - name: inject-labels-pods-and-services
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                    - Service
                    - ConfigMap
                    - Secret
                    - ServiceAccount
                  namespaces:
                    - prod-security-vault
                    - prod-security-externalsecrets
                    - prod-platform-keycloak
                    - prod-platform-argocd
                    - prod-platform-harbor
                    - prod-platform-sonarqube
                    - prod-platform-backstage
                    - prod-observability-monitoring
                    - prod-data-services
                    - prod-data-rabbitmq
          exclude:
            any:
              - resources:
                  kinds:
                    - Secret
                  names:
                    - "sh.helm.release.v1.*"
          skipBackgroundRequests: true
          mutate:
            patchStrategicMerge:
              metadata:
                labels:
                  +(app.kubernetes.io/name): "{{request.namespace}}"
                  +(app.kubernetes.io/part-of): "k8s-platform"
                  domain: "platform"
                  environment: "prod"
                  owner: "platform-team"

        # ---- REGRA 2: Deployment, StatefulSet, DaemonSet, Job ------------------
        - name: inject-labels-workloads
          match:
            any:
              - resources:
                  kinds:
                    - Deployment
                    - StatefulSet
                    - DaemonSet
                    - Job
                  namespaces:
                    - prod-security-vault
                    - prod-security-externalsecrets
                    - prod-platform-keycloak
                    - prod-platform-argocd
                    - prod-platform-harbor
                    - prod-platform-sonarqube
                    - prod-platform-backstage
                    - prod-observability-monitoring
                    - prod-data-services
                    - prod-data-rabbitmq
          skipBackgroundRequests: true
          mutate:
            patchStrategicMerge:
              metadata:
                labels:
                  +(app.kubernetes.io/name): "{{request.namespace}}"
                  +(app.kubernetes.io/part-of): "k8s-platform"
                  domain: "platform"
                  environment: "prod"
                  owner: "platform-team"
              spec:
                template:
                  metadata:
                    labels:
                      +(app.kubernetes.io/name): "{{request.namespace}}"
                      +(app.kubernetes.io/part-of): "k8s-platform"
                      domain: "platform"
                      environment: "prod"
                      owner: "platform-team"
  YAML

  # IMPORTANTE: Esta ClusterPolicy foi criada via kubectl apply (2026-03-19).
  # Para eliminar o drift e passar a ser TF-managed, executar:
  #   cd platform-provisioning/aws/kubernetes/terraform/environments/prod
  #   terraform import \
  #     kubectl_manifest.kyverno_inject_corporate_labels_prod \
  #     "apiVersion=kyverno.io/v1,kind=ClusterPolicy,name=inject-corporate-labels-prod-namespaces"
  lifecycle {
    ignore_changes = [
      # Kyverno controller adiciona annotations/status — nao gerar drift por isso
      yaml_body,
    ]
  }
}
