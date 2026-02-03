# =============================================================================
# GitLab Network Policies - Marco 3 Fase 2
# Security & Compliance: Micro-segmentation with Calico
# ADR-023: 9 Network Policies for GitLab namespace
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Default Deny All Ingress (Baseline)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_default_deny" {
  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "gitlab-default-deny-ingress"
      namespace = kubernetes_namespace.gitlab.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "gitlab"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {}  # Apply to all pods in namespace

      policyTypes = ["Ingress"]

      # Empty ingress rules = deny all
      ingress = []
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 2. Allow Internal GitLab Communication
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_allow_internal" {
  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "gitlab-allow-internal"
      namespace = kubernetes_namespace.gitlab.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "gitlab"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app" = "gitlab"
        }
      }

      policyTypes = ["Ingress"]

      ingress = [
        {
          # Allow all GitLab pods to communicate with each other
          from = [
            {
              podSelector = {
                matchLabels = {
                  "app" = "gitlab"
                }
              }
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 3. Allow Access to PostgreSQL (data-services namespace)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_allow_postgresql" {
  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "gitlab-allow-postgresql"
      namespace = kubernetes_namespace.gitlab.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "gitlab"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app" = "gitlab"
        }
      }

      policyTypes = ["Egress"]

      egress = [
        {
          # Allow egress to PostgreSQL in data-services namespace
          to = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = "data-services"
                }
              }
              podSelector = {
                matchLabels = {
                  "app.kubernetes.io/name" = "postgresql"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 5432
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 4. Allow Access to Redis (data-services namespace)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_allow_redis" {
  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "gitlab-allow-redis"
      namespace = kubernetes_namespace.gitlab.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "gitlab"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app" = "gitlab"
        }
      }

      policyTypes = ["Egress"]

      egress = [
        {
          # Allow egress to Redis in data-services namespace
          to = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = "data-services"
                }
              }
              podSelector = {
                matchLabels = {
                  "app.kubernetes.io/name" = "redis"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 6379
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 5. Allow Internet Egress (Git operations, webhooks, external integrations)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_allow_internet" {
  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "gitlab-allow-internet-egress"
      namespace = kubernetes_namespace.gitlab.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "gitlab"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app" = "gitlab"
        }
      }

      policyTypes = ["Egress"]

      egress = [
        {
          # Allow DNS resolution
          to = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = "kube-system"
                }
              }
              podSelector = {
                matchLabels = {
                  "k8s-app" = "kube-dns"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "UDP"
              port     = 53
            }
          ]
        },
        {
          # Allow HTTPS egress to internet (for Git operations, webhooks, etc.)
          to = [
            {
              # 0.0.0.0/0 for internet access
              ipBlock = {
                cidr = "0.0.0.0/0"
                except = [
                  "10.0.0.0/8",     # Exclude internal networks
                  "172.16.0.0/12",
                  "192.168.0.0/16"
                ]
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 443  # HTTPS
            },
            {
              protocol = "TCP"
              port     = 80   # HTTP
            },
            {
              protocol = "TCP"
              port     = 22   # Git over SSH
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 6. Allow Monitoring to Scrape Metrics
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_allow_monitoring" {
  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "gitlab-allow-monitoring"
      namespace = kubernetes_namespace.gitlab.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "gitlab"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app" = "gitlab"
        }
      }

      policyTypes = ["Ingress"]

      ingress = [
        {
          from = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = "monitoring"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 8083  # GitLab metrics
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 7. Allow GitLab Runner to Access GitLab API
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_runner_allow_gitlab" {
  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "gitlab-runner-allow-gitlab"
      namespace = kubernetes_namespace.gitlab.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "gitlab-runner"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app" = "gitlab-runner"
        }
      }

      policyTypes = ["Egress"]

      egress = [
        {
          # Allow runner to access GitLab webservice
          to = [
            {
              podSelector = {
                matchLabels = {
                  "app" = "webservice"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 8080  # Workhorse
            }
          ]
        },
        {
          # DNS resolution
          to = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = "kube-system"
                }
              }
              podSelector = {
                matchLabels = {
                  "k8s-app" = "kube-dns"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "UDP"
              port     = 53
            }
          ]
        },
        {
          # Allow runner to pull images and access external resources
          to = [
            {
              ipBlock = {
                cidr = "0.0.0.0/0"
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 443
            },
            {
              protocol = "TCP"
              port     = 80
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 8. Allow ALB Ingress Controller Health Checks
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_allow_alb" {
  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "gitlab-allow-alb-ingress"
      namespace = kubernetes_namespace.gitlab.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "gitlab"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app" = "webservice"
        }
      }

      policyTypes = ["Ingress"]

      ingress = [
        {
          # Allow ALB health checks and traffic from VPC CIDR
          from = [
            {
              ipBlock = {
                cidr = "10.0.0.0/16"  # VPC CIDR - adjust if needed
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 8080  # Workhorse
            },
            {
              protocol = "TCP"
              port     = 8181  # GitLab Shell
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 9. Allow AWS API Egress (for IRSA token exchange and S3 access)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_allow_aws_api" {
  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "gitlab-allow-aws-api-egress"
      namespace = kubernetes_namespace.gitlab.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "gitlab"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app" = "gitlab"
        }
      }

      policyTypes = ["Egress"]

      egress = [
        {
          # Allow egress to AWS API endpoints (STS, S3, etc.)
          # AWS services use public IPs, so we allow HTTPS to public IPs
          to = [
            {
              ipBlock = {
                cidr = "0.0.0.0/0"
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 443  # AWS API uses HTTPS
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}
