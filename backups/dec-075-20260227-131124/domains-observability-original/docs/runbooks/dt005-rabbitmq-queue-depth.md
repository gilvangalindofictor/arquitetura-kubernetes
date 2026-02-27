# Runbook: RabbitMQQueueDepthHigh / RabbitMQDown

- **Alert Name**: `RabbitMQQueueDepthHighWarning` / `RabbitMQQueueDepthHighCritical` / `RabbitMQDown`
- **Severity**: `warning` (>1000 msgs) / `critical` (>5000 msgs or down)
- **Source**: DT-005 Data Services Alerts
- **Description**: RabbitMQ queues have accumulated a large backlog of messages (consumers not keeping up with producers) or the RabbitMQ instance is completely unavailable.

---

## 1. Initial Triage

1. **Check RabbitMQ pod status**:
   ```bash
   kubectl get pods -n <namespace> -l app=rabbitmq -o wide
   ```

2. **Check queue depths via management CLI**:
   ```bash
   kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl list_queues name messages consumers
   ```

3. **Check RabbitMQ management UI** (if accessible): Review queue details, message rates, consumer counts.

## 2. Diagnostic Steps

### For Queue Depth:

1. **Identify the problematic queue**:
   ```bash
   kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl list_queues name messages messages_ready messages_unacknowledged consumers
   ```

2. **Check consumer status**:
   ```bash
   # Find consumer pods
   kubectl get pods -n <namespace> -l role=consumer
   # Check if consumers are healthy
   kubectl logs -n <namespace> -l role=consumer --tail=100
   ```

3. **Check message publish rate vs. consume rate** in the RabbitMQ management UI or via metrics:
   ```bash
   kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl list_queues name message_stats.publish_details.rate message_stats.deliver_get_details.rate
   ```

4. **Check for dead-lettered messages**:
   ```bash
   kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl list_queues name messages arguments | grep dead
   ```

### For RabbitMQ Down:

1. **Check pod logs**:
   ```bash
   kubectl logs -n <namespace> -l app=rabbitmq --tail=200
   ```

2. **Check cluster status**:
   ```bash
   kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl cluster_status
   ```

3. **Check disk and memory alarms**:
   ```bash
   kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl status | grep -A5 "alarms"
   ```

## 3. Mitigation / Resolution

### Queue Depth:

- **Scale consumer pods**:
  ```bash
  kubectl scale deployment/<consumer-deployment> --replicas=<N> -n <namespace>
  ```

- **Purge stale queue** (CAUTION - data loss):
  ```bash
  kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl purge_queue <queue-name>
  ```

- **Investigate slow consumers**: Check consumer logs for processing errors or slow dependencies.

- **Implement prefetch limits** if not set:
  Configure `prefetch_count` in consumer applications to prevent a single consumer from being overwhelmed.

### RabbitMQ Down:

- **Restart pod**:
  ```bash
  kubectl delete pod <rabbitmq-pod> -n <namespace>
  ```

- **Clear disk alarm** (if disk space triggered):
  ```bash
  # Check disk usage
  kubectl exec -n <namespace> <rabbitmq-pod> -- df -h
  # Clear old logs
  kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl logrotate
  ```

- **Reset a node** (cluster issues):
  ```bash
  kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl stop_app
  kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl reset
  kubectl exec -n <namespace> <rabbitmq-pod> -- rabbitmqctl start_app
  ```

## 4. Post-Mortem

- Identify why consumers fell behind (bug, dependency failure, resource limits)
- Review consumer scaling policies (HPA based on queue depth)
- Consider implementing dead letter queues for failed messages
- Review message TTL policies to prevent unbounded queue growth
- Document the event and capacity planning implications
