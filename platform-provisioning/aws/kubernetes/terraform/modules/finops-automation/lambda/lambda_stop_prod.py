"""
Lambda Function: Stop Prod Workloads (Deployment/StatefulSet scale-to-0)
Trigger: EventBridge cron
Author: FinOps Team
Date: 2026-03-24

Strategy:
  PROD uses a DIFFERENT strategy from staging:
  - Staging: scales EKS NODE GROUPS to 0 (hardware savings)
  - Prod: scales DEPLOYMENTS/STATEFULSETS to 0 in prod-* namespaces only
    (cluster is SHARED — node groups must stay up for staging shared services)

Key constraints:
  - Node groups: NOT touched (shared with staging shared services)
  - RDS: NOT stopped (k8s-platform-prod-postgresql is shared by both envs)
  - Shared namespaces: NEVER touched (harbor-system, staging-platform-*, etc.)
  - Only prod-* namespaces that are EXCLUSIVELY prod workloads are scaled down

Scoped namespaces (scalable prod-exclusive):
  - prod-platform-keycloak
  - prod-platform-sonarqube
  - prod-platform-backstage
  - prod-platform-harbor        (Harbor replica — NOT shared harbor-system)
  - prod-platform-externaldns
  - prod-platform-argocd        (MOVED TO EXCLUDED — critical platform tool, must stay UP for emergency hotfixes/rollbacks)
  - prod-observability-monitoring (prod-exclusive observability stack)
  - prod-data-hatch-etl         (ETL workloads — replicas=0 already per Hatch HOLD policy)
  - prod-data-vemsoft-etl       (ETL workloads)
  - prod-data-services          (prod data services)
  - prod-data-rabbitmq          (prod RabbitMQ)
  - prod-data-redis-operator    (prod Redis operator)
  - prod-data-ipaas             (prod iPaaS)

Excluded namespaces (NEVER touched):
  - harbor-system               (shared Harbor registry)
  - staging-platform-gitlab     (shared GitLab)
  - staging-platform-argocd     (shared ArgoCD — staging)
  - prod-platform-argocd        (prod ArgoCD — CRITICAL: must stay UP for emergency hotfixes/rollbacks)
  - staging-security-vault      (shared Vault)
  - staging-observability-monitoring (shared Prometheus/Grafana)
  - monitoring                  (shared monitoring)
  - kube-system                 (critical system)
  - linkerd, linkerd-cni        (service mesh)
  - cert-manager                (PKI)
  - external-secrets-system     (ESO)
  - prod-security-externalsecrets (ESO prod)
  - prod-security-vault         (CRITICAL: Vault prod — KMS auto-unseal, ESO backend; NEVER scale to 0)

Circuit Breaker: threshold=3 (same as staging)
DynamoDB: finops-scheduler-state-prod
SNS: prod-specific topic

Environment Variables:
- CLUSTER_NAME: k8s-platform-prod
- ENVIRONMENT: prod
- TARGET_NAMESPACES: comma-separated list of prod-* namespaces to scale down
- EXCLUDED_NAMESPACES: comma-separated list of namespaces NEVER to touch
- DYNAMODB_TABLE_NAME: finops-scheduler-state-prod
- SNS_TOPIC_ARN: ARN of prod SNS alerts topic
- CIRCUIT_BREAKER_THRESHOLD: int (default: 3)
- LOG_LEVEL: INFO|DEBUG (default: INFO)
- DRY_RUN: true|false (default: false) — when true, only logs actions without executing
"""

import base64
import boto3
import json
import logging
import os
import ssl
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO').upper()
logger.setLevel(getattr(logging, log_level, logging.INFO))

# ---------------------------------------------------------------------------
# AWS clients — explicit timeouts (Lambda compliance)
# ---------------------------------------------------------------------------
_boto_cfg = boto3.session.Config(connect_timeout=10, read_timeout=30)

eks      = boto3.client('eks',      config=_boto_cfg)
sns      = boto3.client('sns',      config=_boto_cfg)
dynamodb = boto3.resource('dynamodb', config=_boto_cfg)

# ---------------------------------------------------------------------------
# Configuration from environment variables
# ---------------------------------------------------------------------------
CLUSTER_NAME        = os.environ.get('CLUSTER_NAME', 'k8s-platform-prod')
AWS_REGION          = os.environ.get('AWS_REGION', 'us-east-1')
ENVIRONMENT         = os.environ.get('ENVIRONMENT', 'prod')
SNS_TOPIC_ARN       = os.environ.get('SNS_TOPIC_ARN', '')
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'finops-scheduler-state-prod')
CIRCUIT_BREAKER_THRESHOLD = int(os.environ.get('CIRCUIT_BREAKER_THRESHOLD', '3'))
DRY_RUN             = os.environ.get('DRY_RUN', 'false').lower() == 'true'

# Target namespaces to scale DOWN — prod-exclusive workloads only
_default_target = (
    "prod-platform-keycloak,"
    "prod-platform-sonarqube,"
    "prod-platform-backstage,"
    "prod-platform-harbor,"
    "prod-platform-externaldns,"
    # NOTE: prod-platform-argocd REMOVED 2026-03-24 — ArgoCD prod is a critical platform tool.
    # Must remain UP for emergency hotfixes/rollbacks on weekends, same as staging-platform-argocd.
    # Added to EXCLUDED_NAMESPACES (never touched by FinOps automation).
    "prod-observability-monitoring,"
    # NOTE: prod-security-vault REMOVED — Vault is CRITICAL infrastructure.
    # Scaling Vault to 0 would break KMS auto-unseal on restart, block ESO
    # (External Secrets Operator) and all workloads depending on secrets.
    # prod-security-vault is now in EXCLUDED_NAMESPACES (never touched).
    "prod-data-hatch-etl,"
    "prod-data-vemsoft-etl,"
    "prod-data-services,"
    "prod-data-rabbitmq,"
    "prod-data-redis-operator,"
    "prod-data-ipaas"
)
TARGET_NAMESPACES = [
    ns.strip()
    for ns in os.environ.get('TARGET_NAMESPACES', _default_target).split(',')
    if ns.strip()
]

# Namespaces that are ABSOLUTELY FORBIDDEN to touch — shared infrastructure
_default_excluded = (
    "harbor-system,"
    "staging-platform-gitlab,"
    "staging-platform-argocd,"
    "staging-platform-keycloak,"
    "staging-platform-harbor,"
    "staging-platform-backstage,"
    "staging-platform-sonarqube,"
    "staging-platform-externaldns,"
    "staging-security-vault,"
    "staging-security-externalsecrets,"
    "staging-observability-monitoring,"
    "monitoring,"
    "kube-system,"
    "kube-public,"
    "kube-node-lease,"
    "linkerd,"
    "linkerd-cni,"
    "linkerd-viz,"
    # FIX: "cert-manager" retained for legacy empty namespace; real workloads in staging-security-certmanager (2026-03-27)
    "cert-manager,"
    "staging-security-certmanager,"
    "external-secrets-system,"
    "prod-security-externalsecrets,"
    # CRITICAL: prod-security-vault added 2026-03-24.
    # Vault prod must NEVER be scaled to 0 by FinOps automation.
    # Reason: KMS auto-unseal requires a running Vault; scaling to 0 and back
    # would leave Vault sealed until KMS re-unseal completes, blocking all
    # External Secrets and cluster secret injection during that window.
    "prod-security-vault,"
    # CRITICAL: prod-platform-argocd added 2026-03-24.
    # ArgoCD prod must remain UP for emergency hotfixes and rollbacks on weekends.
    # Same policy as staging-platform-argocd (shared ArgoCD already excluded).
    # Without ArgoCD, on-call engineers cannot perform GitOps-driven incident response.
    "prod-platform-argocd,"
    "calico-system,"
    "calico-apiserver,"
    "velero,"
    # FIX: "kyverno" → real namespace "staging-governance-kyverno" (2026-03-27)
    # Original entry never matched — Lambda uses exact string match (set membership)
    "staging-governance-kyverno"
)
EXCLUDED_NAMESPACES = set(
    ns.strip()
    for ns in os.environ.get('EXCLUDED_NAMESPACES', _default_excluded).split(',')
    if ns.strip()
)

logger.info(
    f"[INIT] FinOps Prod STOP — cluster={CLUSTER_NAME} "
    f"env={ENVIRONMENT} dry_run={DRY_RUN} "
    f"target_namespaces={TARGET_NAMESPACES}"
)


# ===========================================================================
# K8s API CLIENT — STS presigned token (no kubectl required in Lambda)
# ===========================================================================

class _K8sApiError(Exception):
    """Raised when a K8s API call fails with a non-retryable error."""


def _get_k8s_token() -> str:
    """
    Generate a short-lived STS presigned token for K8s API bearer auth.
    Equivalent to `aws eks get-token`. Token lifetime: 60s.
    """
    from botocore.auth import SigV4QueryAuth
    from botocore.awsrequest import AWSRequest

    session = boto3.session.Session()
    credentials = session.get_credentials().get_frozen_credentials()

    request = AWSRequest(
        method='GET',
        url=f'https://sts.{AWS_REGION}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15',
        headers={'x-k8s-aws-id': CLUSTER_NAME},
    )
    signer = SigV4QueryAuth(credentials, 'sts', AWS_REGION, expires=60)
    signer.add_auth(request)

    token_bytes = request.url.encode('utf-8')
    b64 = base64.urlsafe_b64encode(token_bytes).rstrip(b'=').decode('utf-8')
    return f"k8s-aws-v1.{b64}"


def _get_cluster_endpoint() -> tuple:
    """Return (endpoint, ca_data) from EKS DescribeCluster."""
    resp = eks.describe_cluster(name=CLUSTER_NAME)
    cluster = resp['cluster']
    return cluster['endpoint'], cluster['certificateAuthority']['data']


def _k8s_request(method: str, path: str, body: dict = None, content_type: str = 'application/json') -> dict:
    """
    Generic K8s API request helper. Supports GET, PATCH, LIST.

    Args:
        method: HTTP method (GET, PATCH, DELETE)
        path: K8s API path, e.g. '/api/v1/namespaces/prod-platform-keycloak/deployments'
        body: Request body dict (for PATCH)
        content_type: Content-Type header for PATCH

    Returns: Parsed JSON response dict.
    Raises: _K8sApiError on failure.
    """
    endpoint, ca_data = _get_cluster_endpoint()
    token = _get_k8s_token()

    url = f"{endpoint.rstrip('/')}{path}"
    ca_bytes = base64.b64decode(ca_data)

    with tempfile.NamedTemporaryFile(suffix='.crt', delete=False) as f:
        f.write(ca_bytes)
        ca_file = f.name

    try:
        ctx = ssl.create_default_context(cafile=ca_file)
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/json',
        }
        data = None
        if body is not None:
            data = json.dumps(body).encode('utf-8')
            headers['Content-Type'] = content_type

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, context=ctx, timeout=20) as resp:
            return json.loads(resp.read())

    except urllib.error.HTTPError as exc:
        raise _K8sApiError(f"HTTP {exc.code} {exc.reason} — {path}") from exc
    except urllib.error.URLError as exc:
        raise _K8sApiError(f"URLError: {exc.reason} — {path}") from exc
    except ssl.SSLError as exc:
        raise _K8sApiError(f"SSLError: {exc} — {path}") from exc
    except Exception as exc:
        raise _K8sApiError(f"Unexpected error: {exc} — {path}") from exc
    finally:
        try:
            os.unlink(ca_file)
        except Exception:
            pass


# ===========================================================================
# WORKLOAD SCALE-DOWN FUNCTIONS
# ===========================================================================

def _list_scalable_resources(namespace: str) -> dict:
    """
    List all Deployments and StatefulSets in a namespace with their current replica counts.

    Returns:
        {
          'deployments': [{'name': str, 'replicas': int}],
          'statefulsets': [{'name': str, 'replicas': int}]
        }
    """
    result = {'deployments': [], 'statefulsets': []}

    # List Deployments
    try:
        path = f'/apis/apps/v1/namespaces/{namespace}/deployments'
        data = _k8s_request('GET', path)
        for item in data.get('items', []):
            name = item['metadata']['name']
            replicas = item.get('spec', {}).get('replicas', 0)
            result['deployments'].append({'name': name, 'replicas': replicas})
    except _K8sApiError as exc:
        logger.warning(f"[LIST] Failed to list deployments in {namespace}: {exc}")

    # List StatefulSets
    try:
        path = f'/apis/apps/v1/namespaces/{namespace}/statefulsets'
        data = _k8s_request('GET', path)
        for item in data.get('items', []):
            name = item['metadata']['name']
            replicas = item.get('spec', {}).get('replicas', 0)
            result['statefulsets'].append({'name': name, 'replicas': replicas})
    except _K8sApiError as exc:
        logger.warning(f"[LIST] Failed to list statefulsets in {namespace}: {exc}")

    return result


def _scale_resource(resource_type: str, namespace: str, name: str, replicas: int) -> bool:
    """
    Scale a Deployment or StatefulSet to the given replica count via K8s API PATCH.

    Args:
        resource_type: 'deployments' or 'statefulsets'
        namespace: K8s namespace
        name: Resource name
        replicas: Target replica count

    Returns: True on success, False on failure.
    """
    path = f'/apis/apps/v1/namespaces/{namespace}/{resource_type}/{name}'
    patch_body = {'spec': {'replicas': replicas}}

    if DRY_RUN:
        logger.info(f"[DRY-RUN] Would PATCH {resource_type}/{name} in {namespace} replicas={replicas}")
        return True

    try:
        _k8s_request('PATCH', path, body=patch_body, content_type='application/merge-patch+json')
        logger.info(f"[SCALE] {namespace}/{resource_type}/{name} → replicas={replicas} OK")
        return True
    except _K8sApiError as exc:
        logger.error(f"[SCALE] Failed to scale {namespace}/{resource_type}/{name}: {exc}")
        return False


# ===========================================================================
# RABBITMQ CLUSTER SCALE-DOWN — via RabbitmqCluster CRD (rabbitmq.com/v1beta1)
# IMPORTANT: kubectl scale / apps/v1 StatefulSet PATCH is overridden by the
#            RabbitmqCluster operator. The ONLY correct way to scale RabbitMQ
#            is by PATCHing spec.replicas on the RabbitmqCluster CR directly.
# ===========================================================================

RABBITMQ_NAMESPACE  = 'prod-data-rabbitmq'
RABBITMQ_API_GROUP  = 'rabbitmq.com'
RABBITMQ_API_VER    = 'v1beta1'
RABBITMQ_RESOURCE   = 'rabbitmqclusters'


def scale_rabbitmq_cluster(replicas: int = 0) -> list:
    """
    Scale all RabbitmqCluster CRs in RABBITMQ_NAMESPACE by PATCHing spec.replicas
    on the Custom Resource (rabbitmq.com/v1beta1).  Saves previous replica counts
    to the DynamoDB entry for prod-data-rabbitmq under field rabbitmq_previous_replicas.

    Using the CR API — NOT apps/v1/statefulsets — because the operator reverts
    any direct StatefulSet scale immediately.

    Args:
        replicas: Target replica count (0 = scale down, N = restore).

    Returns:
        List of dicts: [{'name': str, 'previous_replicas': int, 'ok': bool}]
    """
    results = []

    # LIST: GET /apis/rabbitmq.com/v1beta1/namespaces/prod-data-rabbitmq/rabbitmqclusters
    list_path = (
        f'/apis/{RABBITMQ_API_GROUP}/{RABBITMQ_API_VER}'
        f'/namespaces/{RABBITMQ_NAMESPACE}/{RABBITMQ_RESOURCE}'
    )
    try:
        data = _k8s_request('GET', list_path)
    except _K8sApiError as exc:
        logger.error(f"[RABBITMQ] Failed to list RabbitmqClusters: {exc}")
        return [{'name': 'LIST_FAILED', 'previous_replicas': -1, 'ok': False, 'error': str(exc)}]

    items = data.get('items', [])
    if not items:
        logger.warning(f"[RABBITMQ] No RabbitmqCluster CRs found in {RABBITMQ_NAMESPACE}")
        return []

    for item in items:
        name = item['metadata']['name']
        previous_replicas = item.get('spec', {}).get('replicas', 3)

        entry = {'name': name, 'previous_replicas': previous_replicas, 'ok': False}

        if previous_replicas == replicas:
            logger.info(
                f"[RABBITMQ] {RABBITMQ_NAMESPACE}/{name} already at replicas={replicas} — skipping"
            )
            entry['ok'] = True
            results.append(entry)
            continue

        if DRY_RUN:
            logger.info(
                f"[DRY-RUN] Would PATCH rabbitmqcluster/{name} in {RABBITMQ_NAMESPACE} "
                f"replicas: {previous_replicas} → {replicas}"
            )
            entry['ok'] = True
            results.append(entry)
            continue

        # PATCH: PATCH /apis/rabbitmq.com/v1beta1/namespaces/.../rabbitmqclusters/{name}
        patch_path = f'{list_path}/{name}'
        try:
            _k8s_request(
                'PATCH',
                patch_path,
                body={'spec': {'replicas': replicas}},
                content_type='application/merge-patch+json',
            )
            logger.info(
                f"[RABBITMQ] {RABBITMQ_NAMESPACE}/{name}: "
                f"spec.replicas {previous_replicas} → {replicas} OK"
            )
            entry['ok'] = True
        except _K8sApiError as exc:
            logger.error(
                f"[RABBITMQ] Failed to patch {RABBITMQ_NAMESPACE}/{name}: {exc}"
            )
            entry['error'] = str(exc)

        results.append(entry)

    # Persist previous_replicas to DynamoDB so lambda_start_prod can restore
    _save_rabbitmq_state_to_dynamodb(results)

    return results


def _save_rabbitmq_state_to_dynamodb(rmq_results: list):
    """
    Persist RabbitMQ previous replica counts to DynamoDB field rabbitmq_previous_replicas.
    Schema: list of {name, previous_replicas, ok} stored as JSON string.
    """
    if not DYNAMODB_TABLE_NAME:
        return

    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        state = [
            {'name': r['name'], 'previous_replicas': r['previous_replicas']}
            for r in rmq_results
            if r.get('ok') and r.get('previous_replicas', -1) >= 0
        ]
        if not state:
            logger.warning("[RABBITMQ] No valid RabbitMQ state entries to persist")
            return

        table.update_item(
            Key={'environment': ENVIRONMENT},
            UpdateExpression=(
                "SET rabbitmq_previous_replicas = :s, "
                "rabbitmq_cr_name = :name, "
                "rabbitmq_namespace = :ns, "
                "rabbitmq_saved_at = :ts"
            ),
            ExpressionAttributeValues={
                ':s': json.dumps(state),
                ':name': state[0]['name'] if len(state) == 1 else json.dumps([s['name'] for s in state]),
                ':ns': RABBITMQ_NAMESPACE,
                ':ts': datetime.now(timezone.utc).isoformat(),
            },
        )
        logger.info(
            f"[RABBITMQ] Saved rabbitmq_previous_replicas to DynamoDB: "
            f"{[s['name'] + '=' + str(s['previous_replicas']) for s in state]}"
        )
    except Exception as exc:
        logger.error(f"[RABBITMQ] Failed to save RabbitMQ state to DynamoDB: {exc}")


def scale_down_namespace(namespace: str, results: dict) -> dict:
    """
    Scale all Deployments and StatefulSets in a namespace to 0 replicas.
    Saves previous replica counts in results for state tracking.

    Safety guard: if namespace is in EXCLUDED_NAMESPACES, skip entirely.

    Returns:
        {
          'namespace': str,
          'deployments_scaled': [str],
          'statefulsets_scaled': [str],
          'failures': [str],
          'previous_state': {'deployments': {...}, 'statefulsets': {...}}
        }
    """
    if namespace in EXCLUDED_NAMESPACES:
        logger.error(
            f"[SAFETY] Namespace {namespace} is in EXCLUDED_NAMESPACES! "
            "This is a shared resource — aborting scale-down for this namespace."
        )
        return {
            'namespace': namespace,
            'status': 'BLOCKED_SHARED_RESOURCE',
            'message': 'Namespace is in EXCLUDED_NAMESPACES — not touched',
        }

    logger.info(f"[STOP] Processing namespace: {namespace}")

    ns_result = {
        'namespace': namespace,
        'deployments_scaled': [],
        'statefulsets_scaled': [],
        'failures': [],
        'previous_state': {'deployments': {}, 'statefulsets': {}},
    }

    # List current state
    resources = _list_scalable_resources(namespace)

    # Scale Deployments to 0
    for deploy in resources['deployments']:
        name = deploy['name']
        prev_replicas = deploy['replicas']
        if prev_replicas == 0:
            logger.info(f"[STOP] {namespace}/deployment/{name} already at 0 replicas — skipping")
            ns_result['previous_state']['deployments'][name] = 0
            ns_result['deployments_scaled'].append(name)
            continue

        ns_result['previous_state']['deployments'][name] = prev_replicas
        ok = _scale_resource('deployments', namespace, name, 0)
        if ok:
            ns_result['deployments_scaled'].append(name)
        else:
            ns_result['failures'].append(f"deployment/{name}")

    # Scale StatefulSets to 0
    for sts in resources['statefulsets']:
        name = sts['name']
        prev_replicas = sts['replicas']
        if prev_replicas == 0:
            logger.info(f"[STOP] {namespace}/statefulset/{name} already at 0 replicas — skipping")
            ns_result['previous_state']['statefulsets'][name] = 0
            ns_result['statefulsets_scaled'].append(name)
            continue

        ns_result['previous_state']['statefulsets'][name] = prev_replicas
        ok = _scale_resource('statefulsets', namespace, name, 0)
        if ok:
            ns_result['statefulsets_scaled'].append(name)
        else:
            ns_result['failures'].append(f"statefulset/{name}")

    total_scaled = len(ns_result['deployments_scaled']) + len(ns_result['statefulsets_scaled'])
    total_failures = len(ns_result['failures'])
    logger.info(
        f"[STOP] {namespace}: scaled={total_scaled} failures={total_failures}"
    )

    return ns_result


# ===========================================================================
# STATE MANAGEMENT — DynamoDB Circuit Breaker
# ===========================================================================

def update_dynamodb_state(results: dict):
    """
    Persist shutdown state to DynamoDB.

    Schema:
      PK: environment (str) = 'prod'
      Fields:
        circuit_breaker_state: CLOSED | OPEN
        shutdown_failures: int (incremented on failure, reset on success)
        last_shutdown: ISO timestamp
        last_updated: ISO timestamp
        shutdown_summary: JSON summary of last operation
    """
    if not DYNAMODB_TABLE_NAME:
        logger.warning("[DYNAMO] DYNAMODB_TABLE_NAME not set — skipping state update")
        return

    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        timestamp = datetime.now(timezone.utc).isoformat()

        update_expr = "SET last_shutdown = :ts, last_updated = :ts, shutdown_summary = :summary"
        expr_values = {
            ':ts': timestamp,
            ':summary': json.dumps({
                'success': results['success'],
                'namespaces_processed': len(results.get('namespaces', {})),
                'total_failures': results.get('total_failures', 0),
            }),
        }

        if results['success']:
            update_expr += ", shutdown_failures = :zero"
            expr_values[':zero'] = 0
            logger.info("[DYNAMO] Shutdown succeeded — resetting failure counter")
        else:
            update_expr += ", shutdown_failures = if_not_exists(shutdown_failures, :zero) + :one"
            expr_values[':zero'] = 0
            expr_values[':one'] = 1
            logger.warning("[DYNAMO] Shutdown failed — incrementing failure counter")

            # Check circuit breaker threshold
            response = table.get_item(Key={'environment': ENVIRONMENT})
            if 'Item' in response:
                current_failures = int(response['Item'].get('shutdown_failures', 0))
                if current_failures + 1 >= CIRCUIT_BREAKER_THRESHOLD:
                    update_expr += ", circuit_breaker_state = :open"
                    expr_values[':open'] = 'OPEN'
                    logger.error(
                        f"[CB] Circuit breaker OPEN after {current_failures + 1} failures "
                        f"(threshold={CIRCUIT_BREAKER_THRESHOLD})"
                    )

        table.update_item(
            Key={'environment': ENVIRONMENT},
            UpdateExpression=update_expr,
            ExpressionAttributeValues=expr_values,
        )
        logger.info(f"[DYNAMO] State updated: last_shutdown={timestamp}")

    except Exception as exc:
        logger.error(f"[DYNAMO] Failed to update state: {exc}")
        # Non-blocking: don't fail the whole operation for DynamoDB errors


def save_previous_state_to_dynamodb(ns_results: list):
    """
    Save the previous replica counts to DynamoDB so lambda_start_prod can restore them.

    This is the state that lambda_start_prod uses to scale deployments back to
    their original replica counts.

    Schema item field: previous_replicas (map of namespace -> {deployments: {name: int}, statefulsets: {name: int}})
    """
    if not DYNAMODB_TABLE_NAME:
        return

    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        previous_state = {}

        for ns_result in ns_results:
            ns = ns_result.get('namespace')
            if not ns:
                continue
            prev = ns_result.get('previous_state', {})
            if prev.get('deployments') or prev.get('statefulsets'):
                previous_state[ns] = {
                    'deployments': prev.get('deployments', {}),
                    'statefulsets': prev.get('statefulsets', {}),
                }

        if previous_state:
            table.update_item(
                Key={'environment': ENVIRONMENT},
                UpdateExpression="SET previous_replicas = :state",
                ExpressionAttributeValues={':state': json.dumps(previous_state)},
            )
            logger.info(
                f"[DYNAMO] Saved previous replica state for {len(previous_state)} namespace(s)"
            )

    except Exception as exc:
        logger.error(f"[DYNAMO] Failed to save previous state: {exc}")


# ===========================================================================
# NOTIFICATION
# ===========================================================================

def send_notification(results: dict):
    """Send shutdown results to SNS topic."""
    if not SNS_TOPIC_ARN:
        logger.warning("[SNS] SNS_TOPIC_ARN not configured — skipping notification")
        return

    success = results.get('success', False)
    subject = f"[FinOps Prod] STOP — {'SUCCESS' if success else 'FAILED'} — {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}"

    lines = [
        f"FinOps PROD Shutdown — {'DRY RUN' if DRY_RUN else 'EXECUTED'}",
        f"Cluster: {CLUSTER_NAME}",
        f"Timestamp: {results.get('timestamp', 'unknown')}",
        f"Success: {success}",
        "",
        "Namespaces Processed:",
    ]

    for ns, ns_result in results.get('namespaces', {}).items():
        d_count = len(ns_result.get('deployments_scaled', []))
        s_count = len(ns_result.get('statefulsets_scaled', []))
        f_count = len(ns_result.get('failures', []))
        status = ns_result.get('status', '')
        if status == 'BLOCKED_SHARED_RESOURCE':
            lines.append(f"  {ns}: BLOCKED (shared resource — not touched)")
        else:
            lines.append(f"  {ns}: deployments={d_count} statefulsets={s_count} failures={f_count}")

    lines.append("")
    lines.append(f"Total failures: {results.get('total_failures', 0)}")
    lines.append(f"Next START: Tomorrow 10:30 UTC / 07:30 BRT")

    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject[:100],
            Message="\n".join(lines),
        )
        logger.info("[SNS] Notification sent")
    except Exception as exc:
        logger.error(f"[SNS] Failed to send notification: {exc}")


# ===========================================================================
# MAIN HANDLER
# ===========================================================================

def lambda_handler(event, context):
    """
    Main handler: scale down all prod-exclusive namespaces.

    Does NOT:
      - Touch node groups (cluster shared with staging)
      - Stop RDS (shared k8s-platform-prod-postgresql)
      - Touch any shared namespace (harbor-system, staging-*, etc.)

    Does:
      1. For each namespace in TARGET_NAMESPACES:
         a. Safety check: skip if in EXCLUDED_NAMESPACES
         b. List all Deployments + StatefulSets
         c. Save current replica counts to DynamoDB (for START restore)
         d. Scale all to replicas=0
      2. Update DynamoDB circuit breaker state
      3. Notify SNS

    Circuit Breaker: if shutdown_failures >= threshold, sets circuit_breaker_state=OPEN.
    When OPEN, lambda_start_prod.py will check state before starting — prevents
    repeated start/stop loops on a broken cluster.
    """
    start_ts = datetime.now(timezone.utc)
    logger.info(
        f"[START] FinOps Prod STOP — cluster={CLUSTER_NAME} "
        f"env={ENVIRONMENT} dry_run={DRY_RUN}"
    )
    logger.info(f"[START] Target namespaces: {TARGET_NAMESPACES}")
    logger.info(f"[START] Excluded namespaces (NEVER touch): {sorted(EXCLUDED_NAMESPACES)}")

    results = {
        'timestamp': start_ts.isoformat(),
        'environment': ENVIRONMENT,
        'cluster': CLUSTER_NAME,
        'dry_run': DRY_RUN,
        'namespaces': {},
        'total_failures': 0,
        'success': True,
    }

    ns_results_list = []

    for namespace in TARGET_NAMESPACES:
        try:
            ns_result = scale_down_namespace(namespace, results)
            results['namespaces'][namespace] = ns_result

            if ns_result.get('failures'):
                results['total_failures'] += len(ns_result['failures'])
                results['success'] = False
                logger.warning(
                    f"[STOP] {namespace}: {len(ns_result['failures'])} failure(s): "
                    f"{ns_result['failures']}"
                )

            ns_results_list.append(ns_result)

        except Exception as exc:
            logger.error(f"[STOP] Unexpected error processing {namespace}: {exc}", exc_info=True)
            results['namespaces'][namespace] = {
                'namespace': namespace,
                'status': 'error',
                'message': str(exc),
                'failures': [str(exc)],
            }
            results['total_failures'] += 1
            results['success'] = False

    # ------------------------------------------------------------------
    # Scale RabbitMQ via RabbitmqCluster CRD (operator-controlled resource)
    # Must use CR PATCH — direct StatefulSet scale is reverted by operator
    # ------------------------------------------------------------------
    logger.info("[STOP] Scaling RabbitMQ via RabbitmqCluster CR (prod-data-rabbitmq)")
    rmq_results = scale_rabbitmq_cluster(replicas=0)
    results['rabbitmq'] = rmq_results
    if rmq_results and not all(r.get('ok') for r in rmq_results):
        failed = [r['name'] for r in rmq_results if not r.get('ok')]
        logger.error(f"[STOP] RabbitMQ scale-down failures: {failed}")
        results['total_failures'] += len(failed)
        results['success'] = False
    else:
        scaled = [r['name'] for r in rmq_results if r.get('ok')]
        logger.info(f"[STOP] RabbitMQ scaled to 0: {scaled}")

    # Save previous state so START can restore original replica counts
    save_previous_state_to_dynamodb(ns_results_list)

    # Update circuit breaker state
    update_dynamodb_state(results)

    # Send notification
    send_notification(results)

    elapsed = (datetime.now(timezone.utc) - start_ts).total_seconds()
    results['elapsed_sec'] = round(elapsed, 1)

    status_code = 200 if results['success'] else 500
    logger.info(
        f"[DONE] Prod STOP completed in {elapsed:.1f}s — "
        f"success={results['success']} failures={results['total_failures']}"
    )

    return {'statusCode': status_code, 'body': results}
