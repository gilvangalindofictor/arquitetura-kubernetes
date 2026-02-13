# =============================================================================
# Redis Prometheus Alerting Rules
# Critical alerts: SentinelDown, QuorumLost, MasterDown, ReplicaDown
# =============================================================================

resource "kubectl_manifest" "redis_prometheus_rules" {
  depends_on = [kubectl_manifest.redis]

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "redis-alerts"
      namespace = "monitoring"

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/component"  = "alerting-rules"
        "app.kubernetes.io/managed-by" = "terraform"
        "prometheus"                   = "kube-prometheus-stack"
      })
    }

    spec = {
      groups = [
        {
          name     = "redis.rules"
          interval = "30s"

          rules = [
            # CRITICAL: Sentinel Down
            {
              alert = "RedisSentinelDown"
              expr  = "redis_sentinel_up == 0"

              for = "2m"

              labels = {
                severity  = "critical"
                service   = "redis"
                component = "sentinel"
              }

              annotations = {
                summary     = "Redis Sentinel is down (instance {{ $labels.instance }})"
                description = "Redis Sentinel {{ $labels.instance }} has been down for more than 2 minutes.\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
              }
            },

            # CRITICAL: Quorum Lost (less than 2 sentinels)
            {
              alert = "RedisQuorumLost"
              expr  = "count(redis_sentinel_up == 1) < 2"

              for = "1m"

              labels = {
                severity  = "critical"
                service   = "redis"
                component = "sentinel"
              }

              annotations = {
                summary     = "Redis Sentinel quorum lost"
                description = "Less than 2 Redis Sentinels are running. Quorum is lost, automatic failover disabled.\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
              }
            },

            # CRITICAL: Master Down
            {
              alert = "RedisMasterDown"
              expr  = "redis_instance_info{role=\"master\"} == 0"

              for = "1m"

              labels = {
                severity  = "critical"
                service   = "redis"
                component = "master"
              }

              annotations = {
                summary     = "Redis Master is down"
                description = "Redis Master instance is down. Automatic failover should trigger.\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
              }
            },

            # WARNING: Replica Down
            {
              alert = "RedisReplicaDown"
              expr  = "redis_instance_info{role=\"slave\"} == 0"

              for = "5m"

              labels = {
                severity  = "warning"
                service   = "redis"
                component = "replica"
              }

              annotations = {
                summary     = "Redis Replica is down (instance {{ $labels.instance }})"
                description = "Redis Replica {{ $labels.instance }} has been down for more than 5 minutes.\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
              }
            },

            # WARNING: High Memory Usage
            {
              alert = "RedisHighMemoryUsage"
              expr  = "(redis_memory_used_bytes / redis_memory_max_bytes) > 0.85"

              for = "5m"

              labels = {
                severity  = "warning"
                service   = "redis"
                component = "memory"
              }

              annotations = {
                summary     = "Redis high memory usage (instance {{ $labels.instance }})"
                description = "Redis instance {{ $labels.instance }} memory usage is above 85%.\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
              }
            },

            # WARNING: High Connection Count
            {
              alert = "RedisHighConnectionCount"
              expr  = "redis_connected_clients > 1000"

              for = "5m"

              labels = {
                severity  = "warning"
                service   = "redis"
                component = "connections"
              }

              annotations = {
                summary     = "Redis high connection count (instance {{ $labels.instance }})"
                description = "Redis instance {{ $labels.instance }} has more than 1000 connected clients.\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
              }
            },

            # WARNING: Replication Lag
            {
              alert = "RedisReplicationLag"
              expr  = "redis_master_repl_offset - redis_slave_repl_offset > 1000"

              for = "5m"

              labels = {
                severity  = "warning"
                service   = "redis"
                component = "replication"
              }

              annotations = {
                summary     = "Redis replication lag detected (instance {{ $labels.instance }})"
                description = "Redis replica {{ $labels.instance }} is lagging behind master by more than 1000 operations.\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
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
