#!/usr/bin/env bash
set -euo pipefail

echo "=== Check tooling ==="
command -v aws >/dev/null 2>&1 || echo "WARN: aws CLI not found or not in PATH"
command -v kubectl >/dev/null 2>&1 || echo "WARN: kubectl not found or not in PATH"
command -v helm >/dev/null 2>&1 || echo "WARN: helm not found or not in PATH"

echo
echo "=== RDS instances ==="
if command -v aws >/dev/null 2>&1; then
  aws rds describe-db-instances --query 'DBInstances[].{Identifier:DBInstanceIdentifier,Engine:Engine,EngineVersion:EngineVersion,Status:DBInstanceStatus}' --output table || echo "aws rds query failed"
else
  echo "skipping RDS: aws CLI unavailable"
fi

echo
echo "=== ElastiCache (ReplicationGroups) ==="
if command -v aws >/dev/null 2>&1; then
  aws elasticache describe-replication-groups --query 'ReplicationGroups[].{Id:ReplicationGroupId,Engine:Engine,EngineVersion:EngineVersion}' --output table || echo "aws elasticache replication-groups query failed"
  echo
  aws elasticache describe-cache-clusters --show-cache-node-info --query 'CacheClusters[].{Id:CacheClusterId,Engine:Engine,EngineVersion:EngineVersion}' --output table || echo "aws elasticache cache-clusters query failed"
else
  echo "skipping ElastiCache: aws CLI unavailable"
fi

echo
NS_DATASVC=${NS_DATASVC:-data-services}
NS_REDIS_OP=${NS_REDIS_OP:-redis-operator}
NS_RMQ_OP=${NS_RMQ_OP:-rabbitmq-system}

echo "=== Kubernetes pods images in namespace ${NS_DATASVC} ==="
if command -v kubectl >/dev/null 2>&1; then
  kubectl -n "${NS_DATASVC}" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' || echo "kubectl query failed for ${NS_DATASVC}"
else
  echo "skipping k8s pods: kubectl unavailable"
fi

echo
echo "=== Redis operator (helm) in ${NS_REDIS_OP} ==="
if command -v helm >/dev/null 2>&1; then
  helm -n "${NS_REDIS_OP}" list || echo "helm list failed or no releases in ${NS_REDIS_OP}"
fi
if command -v kubectl >/dev/null 2>&1; then
  kubectl -n "${NS_REDIS_OP}" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}' || echo "kubectl query failed for ${NS_REDIS_OP}"
fi

echo
echo "=== RabbitMQ operator in ${NS_RMQ_OP} ==="
if command -v kubectl >/dev/null 2>&1; then
  kubectl -n "${NS_RMQ_OP}" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}' || echo "kubectl query failed for ${NS_RMQ_OP}"
  kubectl -n "${NS_DATASVC}" get statefulsets,deployments -o wide || true
fi

echo
echo "Done. If output shows warnings about missing CLI or no results, ensure AWS credentials and kubeconfig are configured in this environment."
