affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - preference:
        matchExpressions:
        - key: node-type
          operator: In
          values:
          - system
      weight: 50

config:
  clients:
  - tenant_id: "${loki_tenant_id}"
    url: ${loki_url}/loki/api/v1/push
  snippets:
    extraScrapeConfigs: |
      ${indent(6, extra_scrape_configs)}

daemonset:
  enabled: true

podLabels:
  app.kubernetes.io/managed-by: helm
  app.kubernetes.io/name: promtail
  app.kubernetes.io/part-of: observability
  domain: ${domain}
  environment: ${environment}
  owner: ${owner}

resources:
  limits:
    cpu: ${resources_limits_cpu}
    memory: ${resources_limits_memory}
  requests:
    cpu: ${resources_requests_cpu}
    memory: ${resources_requests_memory}

serviceMonitor:
  enabled: ${enable_service_monitor}
  labels:
%{ for key, value in service_monitor_labels ~}
    ${key}: ${value}
%{ endfor ~}
  namespace: ${service_monitor_namespace}

tolerations:
- effect: NoSchedule
  key: node-type
  operator: Equal
  value: system
- effect: NoSchedule
  key: node-type
  operator: Equal
  value: workload
- effect: NoSchedule
  key: workload
  operator: Equal
  value: critical
