# Harbor Helm Chart Values
# https://github.com/goharbor/harbor-helm

%{ if ingress_enabled }
expose:
  type: ingress
  tls:
    enabled: false
  ingress:
    hosts:
      core: ${ingress_host}
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      alb.ingress.kubernetes.io/healthcheck-path: /api/v2.0/health
      %{ if ingress_group_name != "" }alb.ingress.kubernetes.io/group.name: ${ingress_group_name}%{ endif }

externalURL: http://${ingress_host}
%{ else }
expose:
  type: clusterIP
  tls:
    enabled: false
  clusterIP:
    name: harbor

externalURL: http://harbor-core.${namespace}.svc.cluster.local
%{ endif }

persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      storageClass: ${storage_class}
      size: 5Gi
    chartmuseum:
      storageClass: ${storage_class}
      size: 5Gi
    jobservice:
      storageClass: ${storage_class}
      size: 1Gi

imageChartStorage:
  type: s3
  s3:
    region: ${s3_region}
    bucket: ${s3_bucket}
    regionendpoint: https://s3.${s3_region}.amazonaws.com
    encrypt: true
    secure: true

harborAdminPassword: ${admin_password_secret}

database:
  type: external
  external:
    host: ${postgresql_host}
    port: ${postgresql_port}
    username: ${postgresql_username}
    password: ${postgresql_password}
    coreDatabase: ${postgresql_database}
    notaryServerDatabase: notaryserver
    notarySignerDatabase: notarysigner
    sslmode: require

redis:
  type: external
  external:
    addr: ${redis_host}:${redis_port}
    password: ${redis_password_secret}

core:
  serviceAccountName: ${service_account}
  replicas: 2
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

jobservice:
  serviceAccountName: ${service_account}
  replicas: 1  # FIXED: RWO PVC doesn't support multiple replicas (ADR-039)
  strategy:
    type: Recreate  # ADR-044: RWO PVC requires Recreate to avoid attach conflict
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

registry:
  serviceAccountName: ${service_account}
  strategy:
    type: Recreate  # ADR-044: RWO PVC requires Recreate to avoid attach conflict
  registry:
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 512Mi
        cpu: 500m
  controller:
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 512Mi
        cpu: 500m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

portal:
  replicas: 2
  resources:
    requests:
      memory: 128Mi
      cpu: 50m
    limits:
      memory: 256Mi
      cpu: 200m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

trivy:
  enabled: ${enable_trivy}
  persistence:
    enabled: true
    storageClass: ${storage_class}
    size: 5Gi
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi
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
