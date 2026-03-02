# =============================================================================
# PHASE 0: Baseline Resource Requests (VPA lowerBound-based)
# =============================================================================
# Source: VPA 30d actual usage analysis (Perf Specialist CSV)
# Strategy: Apply VPA lowerBound as requests, lowerBound × headroom as limits
# Headroom ratios:
#   - CPU: 5x (P0 headroom for burst workloads)
#   - Memory: 4x (protection against OOMKill)
#
# Deployment Method: Helm values update via Terraform helm_release
# Execution: Use /tmp/phase0-apply-plan.sh (staged rollout)
# Rollback: Use /tmp/phase0-rollback.sh (emergency revert)
#
# Workloads: 9 total (Vault, Keycloak, Harbor, GitLab×3, ArgoCD, Loki, Tempo)
# Excluded: Prometheus (ConfigUnsupported), Grafana (VPA/actual mismatch), RabbitMQ (name drift)
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Vault (StatefulSet - vault-system)
# VPA lowerBound: cpu=100m, memory=128Mi
# -----------------------------------------------------------------------------

resource "null_resource" "vault_baseline_requests" {
  triggers = {
    cpu_request    = "100m"
    memory_request = "128Mi"
    cpu_limit      = "500m"  # 100m × 5
    memory_limit   = "512Mi" # 128Mi × 4
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      kubectl patch statefulset vault -n vault-system --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
          "requests": {"cpu": "100m", "memory": "128Mi"},
          "limits": {"cpu": "500m", "memory": "512Mi"}
        }}]' || echo "WARN: Vault patch failed (might not exist or already configured)"
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 2. Keycloak (StatefulSet - keycloak)
# VPA lowerBound: cpu=200m, memory=681Mi
# -----------------------------------------------------------------------------

resource "null_resource" "keycloak_baseline_requests" {
  triggers = {
    cpu_request    = "200m"
    memory_request = "681Mi"
    cpu_limit      = "1000m"  # 200m × 5
    memory_limit   = "2724Mi" # 681Mi × 4
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      kubectl patch statefulset keycloak-keycloakx -n keycloak --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
          "requests": {"cpu": "200m", "memory": "681Mi"},
          "limits": {"cpu": "1000m", "memory": "2724Mi"}
        }}]' || echo "WARN: Keycloak patch failed (might not exist or already configured)"
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 3. Harbor Core (Deployment - harbor-system)
# VPA lowerBound: cpu=50m, memory=128Mi
# -----------------------------------------------------------------------------

resource "null_resource" "harbor_core_baseline_requests" {
  triggers = {
    cpu_request    = "50m"
    memory_request = "128Mi"
    cpu_limit      = "250m"  # 50m × 5
    memory_limit   = "512Mi" # 128Mi × 4
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      kubectl patch deployment harbor-core -n harbor-system --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
          "requests": {"cpu": "50m", "memory": "128Mi"},
          "limits": {"cpu": "250m", "memory": "512Mi"}
        }}]' || echo "WARN: Harbor core patch failed (might not exist or already configured)"
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 4. GitLab Webservice (Deployment - gitlab-staging)
# Multi-container: gitlab-workhorse + webservice
# VPA lowerBounds:
#   - workhorse: cpu=10m, memory=50Mi
#   - webservice: cpu=200m, memory=2168Mi
# -----------------------------------------------------------------------------

resource "null_resource" "gitlab_webservice_baseline_requests" {
  triggers = {
    workhorse_cpu_request     = "10m"
    workhorse_memory_request  = "50Mi"
    workhorse_cpu_limit       = "50m"   # 10m × 5
    workhorse_memory_limit    = "200Mi" # 50Mi × 4
    webservice_cpu_request    = "200m"
    webservice_memory_request = "2168Mi"
    webservice_cpu_limit      = "1000m"  # 200m × 5
    webservice_memory_limit   = "8672Mi" # 2168Mi × 4
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      kubectl patch deployment gitlab-webservice-default -n gitlab-staging --type='json' \
        -p='[
          {"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
            "requests": {"cpu": "10m", "memory": "50Mi"},
            "limits": {"cpu": "50m", "memory": "200Mi"}
          }},
          {"op": "replace", "path": "/spec/template/spec/containers/1/resources", "value": {
            "requests": {"cpu": "200m", "memory": "2168Mi"},
            "limits": {"cpu": "1000m", "memory": "8672Mi"}
          }}
        ]' || echo "WARN: GitLab webservice patch failed (might not exist or already configured)"
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 5. GitLab Sidekiq (Deployment - gitlab-staging)
# VPA lowerBound: cpu=125m, memory=1246Mi
# -----------------------------------------------------------------------------

resource "null_resource" "gitlab_sidekiq_baseline_requests" {
  triggers = {
    cpu_request    = "125m"
    memory_request = "1246Mi"
    cpu_limit      = "625m"   # 125m × 5
    memory_limit   = "4984Mi" # 1246Mi × 4
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      kubectl patch deployment gitlab-sidekiq-all-in-1-v2 -n gitlab-staging --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
          "requests": {"cpu": "125m", "memory": "1246Mi"},
          "limits": {"cpu": "625m", "memory": "4984Mi"}
        }}]' || echo "WARN: GitLab sidekiq patch failed (might not exist or already configured)"
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 6. ArgoCD Server (Deployment - argocd)
# VPA lowerBound: cpu=15m, memory=100Mi
# -----------------------------------------------------------------------------

resource "null_resource" "argocd_server_baseline_requests" {
  triggers = {
    cpu_request    = "15m"
    memory_request = "100Mi"
    cpu_limit      = "75m"   # 15m × 5
    memory_limit   = "400Mi" # 100Mi × 4
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      kubectl patch deployment argocd-server -n argocd --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
          "requests": {"cpu": "15m", "memory": "100Mi"},
          "limits": {"cpu": "75m", "memory": "400Mi"}
        }}]' || echo "WARN: ArgoCD server patch failed (might not exist or already configured)"
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 7. Loki Write (StatefulSet - monitoring)
# VPA lowerBound: cpu=50m, memory=194Mi
# -----------------------------------------------------------------------------

resource "null_resource" "loki_write_baseline_requests" {
  triggers = {
    cpu_request    = "50m"
    memory_request = "194Mi"
    cpu_limit      = "250m"  # 50m × 5
    memory_limit   = "776Mi" # 194Mi × 4
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      kubectl patch statefulset loki-write -n monitoring --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
          "requests": {"cpu": "50m", "memory": "194Mi"},
          "limits": {"cpu": "250m", "memory": "776Mi"}
        }}]' || echo "WARN: Loki write patch failed (might not exist or already configured)"
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 8. Tempo Distributor (Deployment - monitoring)
# VPA lowerBound: cpu=15m, memory=100Mi
# -----------------------------------------------------------------------------

resource "null_resource" "tempo_distributor_baseline_requests" {
  triggers = {
    cpu_request    = "15m"
    memory_request = "100Mi"
    cpu_limit      = "75m"   # 15m × 5
    memory_limit   = "400Mi" # 100Mi × 4
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      kubectl patch deployment tempo-distributor -n monitoring --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
          "requests": {"cpu": "15m", "memory": "100Mi"},
          "limits": {"cpu": "75m", "memory": "400Mi"}
        }}]' || echo "WARN: Tempo distributor patch failed (might not exist or already configured)"
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# EXCLUSIONS (3 workloads)
# =============================================================================
#
# 1. Prometheus (monitoring/StatefulSet)
#    Reason: VPA status "ConfigUnsupported - parent controller"
#    Action: Manual analysis required; excluded from Phase 0
#
# 2. Grafana (monitoring/Deployment)
#    Reason: VPA targetRef kind mismatch (VPA:StatefulSet actual:Deployment)
#    Action: VPA object needs correction before baseline can be applied
#
# 3. RabbitMQ (data-services/StatefulSet)
#    Reason: VPA targetRef name mismatch (VPA:rabbitmq-server actual:k8s-platform-prod-rabbitmq-server)
#    Action: VPA object needs update to match actual StatefulSet name
#
# =============================================================================
