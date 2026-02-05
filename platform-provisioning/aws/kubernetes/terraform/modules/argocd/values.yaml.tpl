# ArgoCD Helm Chart Values
# Terraform-managed configuration

global:
  domain: ${domain}

server:
  replicas: ${replicas}

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

  config:
    url: https://${domain}
    
    # Keycloak OIDC
    oidc.config: |
      name: Keycloak
      issuer: ${keycloak_url}/realms/master
      clientID: ${keycloak_client}
      clientSecret: $oidc.keycloak.clientSecret
      requestedScopes: ["openid", "profile", "email", "groups"]
  
  rbacConfig:
    policy.default: role:readonly
    policy.csv: |
      # Admin group from Keycloak
      g, argocd-admins, role:admin
      
      # No secret enumeration (security)
      p, role:readonly, repositories, get, */*, deny
      p, role:readonly, certificates, get, *, deny
      p, role:readonly, accounts, get, *, deny

  metrics:
    enabled: ${enable_monitoring}
    serviceMonitor:
      enabled: ${enable_monitoring}

  ingress:
    enabled: ${ingress_enabled}
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    hosts:
      - ${domain}

repoServer:
  replicas: ${replicas}

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

  metrics:
    enabled: ${enable_monitoring}
    serviceMonitor:
      enabled: ${enable_monitoring}

controller:
  replicas: 1  # Single controller (leader election)

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

  metrics:
    enabled: ${enable_monitoring}
    serviceMonitor:
      enabled: ${enable_monitoring}

dex:
  enabled: false  # Using Keycloak OIDC instead

redis:
  enabled: true

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

applicationSet:
  enabled: true
  replicas: ${replicas}

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

notifications:
  enabled: false  # TODO: Enable with Slack/email
