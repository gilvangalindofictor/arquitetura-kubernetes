"""
Lambda Function: Start Prod Workloads (Deployment/StatefulSet scale-up)
Trigger: EventBridge cron
Author: FinOps Team
Date: 2026-03-24

Strategy:
  PROD uses a DIFFERENT strategy from staging:
  - Staging: scales EKS NODE GROUPS back up (hardware provisioning)
  - Prod: scales DEPLOYMENTS/STATEFULSETS back to their original replica counts
    (cluster is SHARED — nodes already running for staging shared services)

Key differences from staging lambda_start.py:
  - NO node group scaling (nodes are always up — shared cluster)
  - NO RDS start (RDS is shared and always on)
  - NO waiting for system nodes (they are already running)
  - NO Linkerd restart (Linkerd is already running on the shared cluster)
  - Restores replicas from DynamoDB previous_replicas state saved by lambda_stop_prod
  - Falls back to sane defaults if DynamoDB state is not available

Startup sequence:
  Step 1: Read previous replica counts from DynamoDB
  Step 2: For each prod-* namespace, scale deployments/statefulsets back to previous counts
  Step 3b: Restore RabbitMQ via RabbitmqCluster CR PATCH (rabbitmq.com/v1beta1)
           — NOT via apps/v1 StatefulSet (operator reverts it)
           — reads rabbitmq_previous_replicas from DynamoDB (saved by lambda_stop_prod)
  Step 4: Health check — verify key prod workloads have at least 1 Running pod
  Step 5: Update DynamoDB circuit breaker state
  Step 6: Send SNS notification

Circuit Breaker: threshold=3 (same as staging)
DynamoDB: finops-scheduler-state-prod
SNS: prod-specific topic

Environment Variables:
- CLUSTER_NAME: k8s-platform-prod
- ENVIRONMENT: prod
- TARGET_NAMESPACES: comma-separated list of prod-* namespaces to scale up
- DYNAMODB_TABLE_NAME: finops-scheduler-state-prod
- SNS_TOPIC_ARN: ARN of prod SNS alerts topic
- CIRCUIT_BREAKER_THRESHOLD: int (default: 3)
- HEALTH_CHECK_ENABLED: true|false (default: true)
- WORKLOAD_TIMEOUT_SEC: seconds to wait for workloads to become Ready (default: 300)
- LOG_LEVEL: INFO|DEBUG (default: INFO)
- DRY_RUN: true|false (default: false) — when true, only logs actions without executing

Default replica counts (fallback when DynamoDB state is unavailable):
  These represent the expected baseline for each namespace after a fresh start.
  The Lambda prefers restoring from DynamoDB state — these are emergency defaults only.
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
HEALTH_CHECK_ENABLED = os.environ.get('HEALTH_CHECK_ENABLED', 'true').lower() == 'true'
WORKLOAD_TIMEOUT_SEC = int(os.environ.get('WORKLOAD_TIMEOUT_SEC', '300'))
POLL_INTERVAL_SEC    = 15
DRY_RUN = os.environ.get('DRY_RUN', 'false').lower() == 'true'

# Target namespaces — must match TARGET_NAMESPACES in lambda_stop_prod.py
_default_target = (
    "prod-platform-keycloak,"
    "prod-platform-sonarqube,"
    "prod-platform-backstage,"
    "prod-platform-harbor,"
    "prod-platform-externaldns,"
    # NOTE: prod-platform-argocd REMOVED 2026-03-24 — ArgoCD prod is a critical platform tool.
    # Must remain UP for emergency hotfixes/rollbacks on weekends (same policy as staging-platform-argocd).
    # Added to EXCLUDED_NAMESPACES — never stopped/started by FinOps automation.
    # Health check for prod-platform-argocd is preserved in HEALTH_CHECK_CRITERIA below.
    "prod-observability-monitoring,"
    # NOTE: prod-security-vault REMOVED 2026-03-24 — Vault must NEVER be scaled
    # to 0 by FinOps automation. It is always running (added to EXCLUDED_NAMESPACES).
    # Health check for vault-prod is preserved in HEALTH_CHECK_CRITERIA below.
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

# Namespaces ABSOLUTELY FORBIDDEN to touch — shared infrastructure
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
    "cert-manager,"
    "external-secrets-system,"
    "prod-security-externalsecrets,"
    # CRITICAL: prod-security-vault added 2026-03-24.
    # Vault is always running — never stopped/started by FinOps.
    # Health check below verifies vault-prod pods are healthy after cluster startup.
    "prod-security-vault,"
    # CRITICAL: prod-platform-argocd added 2026-03-24.
    # ArgoCD prod is always running — never stopped/started by FinOps automation.
    # Must remain available for emergency hotfixes/rollbacks on weekends.
    # Health check below verifies argocd-prod pods are healthy.
    "prod-platform-argocd,"
    "calico-system,"
    "calico-apiserver,"
    "velero,"
    "kyverno"
)
EXCLUDED_NAMESPACES = set(
    ns.strip()
    for ns in os.environ.get('EXCLUDED_NAMESPACES', _default_excluded).split(',')
    if ns.strip()
)

# ---------------------------------------------------------------------------
# Fallback default replicas — used when DynamoDB state is unavailable
# Maps namespace -> {resource_type -> {name -> replica_count}}
# These are conservative defaults based on current prod topology.
# ---------------------------------------------------------------------------
DEFAULT_REPLICA_FALLBACK = {
    'prod-platform-keycloak': {
        'statefulsets': {'keycloak-keycloakx': 2},
        'deployments': {},
    },
    'prod-platform-sonarqube': {
        'statefulsets': {'sonarqube-sonarqube': 1},
        'deployments': {},
    },
    'prod-platform-backstage': {
        'deployments': {'backstage': 2},
        'statefulsets': {},
    },
    'prod-platform-harbor': {
        'deployments': {
            'harbor-prod-core': 2,
            'harbor-prod-exporter': 1,
            'harbor-prod-jobservice': 1,
            'harbor-prod-portal': 2,
            'harbor-prod-registry': 1,
        },
        'statefulsets': {'harbor-prod-trivy': 1},
    },
    'prod-platform-externaldns': {
        'deployments': {'external-dns-prod': 1},
        'statefulsets': {},
    },
    'prod-platform-argocd': {
        'deployments': {
            'argocd-prod-applicationset-controller': 2,
            'argocd-prod-redis': 1,
            'argocd-prod-repo-server': 2,
            'argocd-prod-server': 2,
        },
        'statefulsets': {'argocd-prod-application-controller': 3},
    },
    'prod-observability-monitoring': {
        'deployments': {
            'kube-prometheus-stack-prod-grafana': 1,
            'kube-prometheus-stack-prod-kube-state-metrics': 1,
            'kube-prometheus-stack-prod-operator': 1,
            'loki-prod-gateway': 2,
            'loki-read': 2,
            'opentelemetry-collector': 2,
            'tempo-prod-compactor': 1,
            'tempo-prod-distributor': 2,
            'tempo-prod-gateway': 2,
            'tempo-prod-querier': 2,
            'tempo-prod-query-frontend': 2,
        },
        'statefulsets': {
            'alertmanager-kube-prometheus-stack-prod-alertmanager': 1,
            'loki-backend': 2,
            'loki-prod-chunks-cache': 1,
            'loki-prod-results-cache': 1,
            'loki-write': 2,
            'prometheus-kube-prometheus-stack-prod-prometheus': 1,
            'tempo-prod-ingester': 2,
            'tempo-prod-memcached': 1,
        },
    },
    'prod-security-vault': {
        'statefulsets': {'vault-prod': 3},
        'deployments': {},
    },
    # ETL workloads: start at 0 by default (controlled by Hatch/ETL auto-run policy)
    'prod-data-hatch-etl': {
        'deployments': {},
        'statefulsets': {},
    },
    'prod-data-vemsoft-etl': {
        'deployments': {},
        'statefulsets': {},
    },
    'prod-data-services': {
        'deployments': {},
        'statefulsets': {},
    },
    # RabbitMQ: do NOT restore via apps/v1 StatefulSet — operator reverts it.
    # Restore is handled exclusively via restore_rabbitmq_cluster() using
    # RabbitmqCluster CR PATCH (rabbitmq.com/v1beta1). Leave statefulsets empty here.
    'prod-data-rabbitmq': {
        'statefulsets': {},
        'deployments': {},
    },
    'prod-data-redis-operator': {
        'deployments': {},
        'statefulsets': {},
    },
    'prod-data-ipaas': {
        'deployments': {},
        'statefulsets': {},
    },
}

# ---------------------------------------------------------------------------
# Health check criteria: namespace -> list of (pod_name_prefix, min_running)
# ---------------------------------------------------------------------------
HEALTH_CHECK_CRITERIA = {
    'prod-platform-keycloak':   [('keycloak', 1)],
    'prod-platform-harbor':     [('harbor-prod-core', 1)],
    'prod-platform-argocd':     [('argocd-prod-application-controller', 1)],
    'prod-security-vault':      [('vault-prod', 1)],
    'prod-observability-monitoring': [('prometheus-kube-prometheus-stack-prod-prometheus', 1)],
}

logger.info(
    f"[INIT] FinOps Prod START — cluster={CLUSTER_NAME} "
    f"env={ENVIRONMENT} dry_run={DRY_RUN} "
    f"health_check={HEALTH_CHECK_ENABLED} "
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
    Generic K8s API request helper. Supports GET and PATCH.

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
# RABBITMQ CLUSTER RESTORE — via RabbitmqCluster CRD (rabbitmq.com/v1beta1)
# IMPORTANT: kubectl scale / apps/v1 StatefulSet PATCH is overridden by the
#            RabbitmqCluster operator. The ONLY correct way to restore RabbitMQ
#            is by PATCHing spec.replicas on the RabbitmqCluster CR directly.
#            Mirrors the approach used in lambda_stop_prod.py scale_rabbitmq_cluster().
# ===========================================================================

RABBITMQ_NAMESPACE  = 'prod-data-rabbitmq'
RABBITMQ_API_GROUP  = 'rabbitmq.com'
RABBITMQ_API_VER    = 'v1beta1'
RABBITMQ_RESOURCE   = 'rabbitmqclusters'
RABBITMQ_DEFAULT_REPLICAS = 3  # fallback if DynamoDB state is unavailable


def restore_rabbitmq_cluster(previous_state: dict) -> list:
    """
    Restore all RabbitmqCluster CRs in RABBITMQ_NAMESPACE by PATCHing spec.replicas
    on the Custom Resource (rabbitmq.com/v1beta1).

    Reads target replica count from DynamoDB field rabbitmq_previous_replicas
    (saved by lambda_stop_prod scale_rabbitmq_cluster). Falls back to
    RABBITMQ_DEFAULT_REPLICAS if DynamoDB state is unavailable.

    Using the CR API — NOT apps/v1/statefulsets — because the operator reverts
    any direct StatefulSet scale immediately.

    Args:
        previous_state: the full DynamoDB state dict loaded by load_previous_state_from_dynamodb
                        (may contain rabbitmq_previous_replicas key).

    Returns:
        List of dicts: [{'name': str, 'target_replicas': int, 'ok': bool}]
    """
    results = []

    # Resolve target replica counts from DynamoDB state saved by lambda_stop_prod
    rmq_saved_raw = previous_state.get('rabbitmq_previous_replicas')
    rmq_saved = None
    if rmq_saved_raw:
        try:
            if isinstance(rmq_saved_raw, str):
                rmq_saved = json.loads(rmq_saved_raw)
            else:
                rmq_saved = rmq_saved_raw  # already a list/dict
        except Exception as exc:
            logger.warning(f"[RABBITMQ] Could not parse rabbitmq_previous_replicas: {exc}")

    # Build name->replicas map from saved state
    rmq_target_map = {}
    if rmq_saved and isinstance(rmq_saved, list):
        for entry in rmq_saved:
            name = entry.get('name')
            prev = entry.get('previous_replicas', RABBITMQ_DEFAULT_REPLICAS)
            if name:
                rmq_target_map[name] = max(prev, 1)  # never restore to 0

    logger.info(
        f"[RABBITMQ] Restore target map from DynamoDB: {rmq_target_map or 'NOT FOUND — will use defaults'}"
    )

    # LIST: GET /apis/rabbitmq.com/v1beta1/namespaces/prod-data-rabbitmq/rabbitmqclusters
    list_path = (
        f'/apis/{RABBITMQ_API_GROUP}/{RABBITMQ_API_VER}'
        f'/namespaces/{RABBITMQ_NAMESPACE}/{RABBITMQ_RESOURCE}'
    )
    try:
        data = _k8s_request('GET', list_path)
    except _K8sApiError as exc:
        logger.error(f"[RABBITMQ] Failed to list RabbitmqClusters: {exc}")
        return [{'name': 'LIST_FAILED', 'target_replicas': -1, 'ok': False, 'error': str(exc)}]

    items = data.get('items', [])
    if not items:
        logger.warning(f"[RABBITMQ] No RabbitmqCluster CRs found in {RABBITMQ_NAMESPACE}")
        return []

    for item in items:
        name = item['metadata']['name']
        current_replicas = item.get('spec', {}).get('replicas', 0)
        # Use saved target or default
        target_replicas = rmq_target_map.get(name, RABBITMQ_DEFAULT_REPLICAS)

        entry = {'name': name, 'target_replicas': target_replicas, 'ok': False}

        if current_replicas == target_replicas:
            logger.info(
                f"[RABBITMQ] {RABBITMQ_NAMESPACE}/{name} already at replicas={target_replicas} — skipping"
            )
            entry['ok'] = True
            results.append(entry)
            continue

        if DRY_RUN:
            logger.info(
                f"[DRY-RUN] Would PATCH rabbitmqcluster/{name} in {RABBITMQ_NAMESPACE} "
                f"replicas: {current_replicas} → {target_replicas}"
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
                body={'spec': {'replicas': target_replicas}},
                content_type='application/merge-patch+json',
            )
            logger.info(
                f"[RABBITMQ] {RABBITMQ_NAMESPACE}/{name}: "
                f"spec.replicas {current_replicas} → {target_replicas} OK"
            )
            entry['ok'] = True
        except _K8sApiError as exc:
            logger.error(
                f"[RABBITMQ] Failed to patch {RABBITMQ_NAMESPACE}/{name}: {exc}"
            )
            entry['error'] = str(exc)

        results.append(entry)

    return results


# ===========================================================================
# STATE READING — DynamoDB
# ===========================================================================

def load_previous_state_from_dynamodb() -> dict:
    """
    Load the previous replica state saved by lambda_stop_prod.

    Returns:
        dict of namespace -> {deployments: {name: int}, statefulsets: {name: int}}
        Returns {} if table does not exist or no previous_replicas key.
    """
    if not DYNAMODB_TABLE_NAME:
        logger.warning("[DYNAMO] DYNAMODB_TABLE_NAME not set — using defaults")
        return {}

    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        response = table.get_item(Key={'environment': ENVIRONMENT})

        if 'Item' not in response:
            logger.warning(f"[DYNAMO] No item found for environment={ENVIRONMENT} — using defaults")
            return {}

        item = response['Item']

        # Check circuit breaker state
        cb_state = item.get('circuit_breaker_state', 'CLOSED')
        if cb_state == 'OPEN':
            logger.error(
                f"[CB] Circuit breaker is OPEN (failures >= {CIRCUIT_BREAKER_THRESHOLD}). "
                "Startup proceeding but circuit breaker state recorded. "
                "Manual investigation required before next cycle."
            )

        previous_replicas_raw = item.get('previous_replicas', '{}')
        if isinstance(previous_replicas_raw, str):
            previous_replicas = json.loads(previous_replicas_raw)
        else:
            previous_replicas = previous_replicas_raw

        logger.info(
            f"[DYNAMO] Loaded previous state for {len(previous_replicas)} namespace(s) "
            f"from DynamoDB"
        )
        return previous_replicas

    except Exception as exc:
        logger.error(f"[DYNAMO] Failed to load previous state: {exc}. Using defaults.")
        return {}


def load_full_dynamodb_item() -> dict:
    """
    Load the raw DynamoDB item for the current environment.
    Used by restore_rabbitmq_cluster() to access rabbitmq_previous_replicas
    (saved by lambda_stop_prod._save_rabbitmq_state_to_dynamodb).

    Returns:
        Full DynamoDB item dict, or {} on error / not found.
    """
    if not DYNAMODB_TABLE_NAME:
        return {}

    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        response = table.get_item(Key={'environment': ENVIRONMENT})
        if 'Item' not in response:
            return {}
        return response['Item']
    except Exception as exc:
        logger.warning(f"[DYNAMO] load_full_dynamodb_item failed: {exc}")
        return {}


def check_circuit_breaker() -> str:
    """
    Check the circuit breaker state in DynamoDB.

    Returns: 'CLOSED' | 'OPEN' | 'UNKNOWN'
    OPEN means the previous shutdown had consecutive failures >= threshold.
    """
    if not DYNAMODB_TABLE_NAME:
        return 'UNKNOWN'

    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        response = table.get_item(Key={'environment': ENVIRONMENT})
        if 'Item' not in response:
            return 'CLOSED'
        return response['Item'].get('circuit_breaker_state', 'CLOSED')
    except Exception as exc:
        logger.warning(f"[CB] Could not check circuit breaker: {exc}")
        return 'UNKNOWN'


def update_dynamodb_state(results: dict):
    """
    Persist startup state to DynamoDB.

    On success: resets startup_failures and circuit_breaker_state to CLOSED.
    On failure: increments startup_failures. Opens CB if threshold reached.
    """
    if not DYNAMODB_TABLE_NAME:
        return

    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        timestamp = datetime.now(timezone.utc).isoformat()

        update_expr = "SET last_startup = :ts, last_updated = :ts, startup_summary = :summary"
        expr_values = {
            ':ts': timestamp,
            ':summary': json.dumps({
                'success': results['success'],
                'namespaces_started': len(results.get('namespaces', {})),
                'total_failures': results.get('total_failures', 0),
            }),
        }

        if results['success']:
            update_expr += ", startup_failures = :zero, circuit_breaker_state = :closed"
            expr_values[':zero'] = 0
            expr_values[':closed'] = 'CLOSED'
            logger.info("[DYNAMO] Startup succeeded — resetting CB to CLOSED")
        else:
            update_expr += ", startup_failures = if_not_exists(startup_failures, :zero) + :one"
            expr_values[':zero'] = 0
            expr_values[':one'] = 1

            response = table.get_item(Key={'environment': ENVIRONMENT})
            if 'Item' in response:
                current_failures = int(response['Item'].get('startup_failures', 0))
                if current_failures + 1 >= CIRCUIT_BREAKER_THRESHOLD:
                    update_expr += ", circuit_breaker_state = :open"
                    expr_values[':open'] = 'OPEN'
                    logger.error(
                        f"[CB] Circuit breaker OPEN after {current_failures + 1} startup failures"
                    )

        table.update_item(
            Key={'environment': ENVIRONMENT},
            UpdateExpression=update_expr,
            ExpressionAttributeValues=expr_values,
        )
        logger.info(f"[DYNAMO] State updated: last_startup={timestamp}")

    except Exception as exc:
        logger.error(f"[DYNAMO] Failed to update state: {exc}")


# ===========================================================================
# WORKLOAD SCALE-UP FUNCTIONS
# ===========================================================================

def _scale_resource(resource_type: str, namespace: str, name: str, replicas: int) -> bool:
    """
    Scale a Deployment or StatefulSet to the given replica count via K8s API PATCH.

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


def scale_up_namespace(namespace: str, ns_state: dict, results: dict) -> dict:
    """
    Scale all Deployments and StatefulSets in a namespace back to their previous counts.

    Safety guard: if namespace is in EXCLUDED_NAMESPACES, skip entirely.

    Args:
        namespace: K8s namespace name
        ns_state: {deployments: {name: replicas}, statefulsets: {name: replicas}}
            Loaded from DynamoDB or from DEFAULT_REPLICA_FALLBACK.
        results: Top-level results dict (for tracking)

    Returns: namespace result dict
    """
    if namespace in EXCLUDED_NAMESPACES:
        logger.error(
            f"[SAFETY] Namespace {namespace} is in EXCLUDED_NAMESPACES! "
            "This is a shared resource — aborting scale-up for this namespace."
        )
        return {
            'namespace': namespace,
            'status': 'BLOCKED_SHARED_RESOURCE',
            'message': 'Namespace is in EXCLUDED_NAMESPACES — not touched',
        }

    logger.info(f"[START] Processing namespace: {namespace}")

    ns_result = {
        'namespace': namespace,
        'deployments_scaled': [],
        'statefulsets_scaled': [],
        'failures': [],
    }

    deployments = ns_state.get('deployments', {})
    statefulsets = ns_state.get('statefulsets', {})

    # Scale Deployments
    for name, replicas in deployments.items():
        if replicas == 0:
            logger.info(f"[START] {namespace}/deployment/{name} was 0 replicas — not scaling up")
            continue
        ok = _scale_resource('deployments', namespace, name, replicas)
        if ok:
            ns_result['deployments_scaled'].append(f"{name}={replicas}")
        else:
            ns_result['failures'].append(f"deployment/{name}")

    # Scale StatefulSets
    for name, replicas in statefulsets.items():
        if replicas == 0:
            logger.info(f"[START] {namespace}/statefulset/{name} was 0 replicas — not scaling up")
            continue
        ok = _scale_resource('statefulsets', namespace, name, replicas)
        if ok:
            ns_result['statefulsets_scaled'].append(f"{name}={replicas}")
        else:
            ns_result['failures'].append(f"statefulset/{name}")

    total_scaled = len(ns_result['deployments_scaled']) + len(ns_result['statefulsets_scaled'])
    total_failures = len(ns_result['failures'])
    logger.info(
        f"[START] {namespace}: scaled_up={total_scaled} failures={total_failures}"
    )

    return ns_result


# ===========================================================================
# HEALTH CHECK
# ===========================================================================

def _list_pods(namespace: str) -> list:
    """
    List pods in a namespace via K8s API.

    Returns list of {name, phase, ready} dicts.
    """
    path = f'/api/v1/namespaces/{namespace}/pods'
    data = _k8s_request('GET', path)

    pods = []
    for item in data.get('items', []):
        name = item['metadata']['name']
        phase = item.get('status', {}).get('phase', 'Unknown')

        # Check if all containers are ready
        container_statuses = item.get('status', {}).get('containerStatuses', [])
        ready = all(cs.get('ready', False) for cs in container_statuses) if container_statuses else False

        pods.append({'name': name, 'phase': phase, 'ready': ready})

    return pods


def verify_prod_health(timeout_sec: int = 300) -> tuple:
    """
    Verify that key prod workloads have at least 1 Running+Ready pod.

    Polls HEALTH_CHECK_CRITERIA until all minimum counts are met OR timeout.
    This is a SOFT gate — failure marks result as DEGRADED but does not block.

    Returns: (bool: all_healthy, dict: diagnostics)
    """
    if not HEALTH_CHECK_ENABLED:
        logger.warning("[HEALTH] HEALTH_CHECK_ENABLED=false — skipping")
        return True, {'result': 'SKIPPED'}

    logger.info(f"[HEALTH] Starting prod health check (timeout={timeout_sec}s)")
    deadline = time.time() + timeout_sec
    attempts = 0
    last_diag = {}

    while time.time() < deadline:
        attempts += 1
        all_ok = True
        components = {}
        failures = []

        for namespace, criteria in HEALTH_CHECK_CRITERIA.items():
            for (prefix, min_count) in criteria:
                key = f"{namespace}/{prefix}"
                try:
                    pods = _list_pods(namespace)
                    matching = [p for p in pods if p['name'].startswith(prefix)]
                    running = [p for p in matching if p['phase'] == 'Running' and p['ready']]
                    count = len(running)
                    ok = count >= min_count

                    components[key] = {
                        'required': min_count,
                        'running': count,
                        'status': 'ok' if ok else 'insufficient',
                    }

                    if not ok:
                        all_ok = False
                        failures.append(f"{key}: need {min_count}, got {count}")

                except _K8sApiError as exc:
                    components[key] = {'status': 'error', 'error': str(exc)}
                    all_ok = False
                    failures.append(f"{key}: K8s API error — {exc}")

                except Exception as exc:
                    components[key] = {'status': 'error', 'error': str(exc)}
                    all_ok = False
                    failures.append(f"{key}: error — {exc}")

        elapsed = round(time.time() - (deadline - timeout_sec), 1)
        last_diag = {
            'summary': 'OK' if all_ok else f"DEGRADED: {'; '.join(failures)}",
            'components': components,
            'elapsed_sec': elapsed,
            'attempts': attempts,
        }

        if all_ok:
            logger.info(f"[HEALTH] All prod workloads healthy after {elapsed}s ({attempts} attempts)")
            return True, last_diag

        logger.info(
            f"[HEALTH] Not fully healthy (attempt={attempts}, elapsed={elapsed}s): "
            f"{'; '.join(failures)}"
        )
        time.sleep(POLL_INTERVAL_SEC)

    logger.warning(
        f"[HEALTH] Timeout after {timeout_sec}s ({attempts} attempts). "
        f"Last: {last_diag.get('summary')}"
    )
    return False, last_diag


# ===========================================================================
# NOTIFICATION
# ===========================================================================

def send_notification(results: dict):
    """Send startup results to SNS topic."""
    if not SNS_TOPIC_ARN:
        logger.warning("[SNS] SNS_TOPIC_ARN not configured — skipping notification")
        return

    success = results.get('success', False)
    health = results.get('health_check', {})
    health_ok = health.get('summary', 'unknown') == 'OK' if health else 'N/A'

    subject = f"[FinOps Prod] START — {'SUCCESS' if success else 'DEGRADED'} — {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}"

    lines = [
        f"FinOps PROD Startup — {'DRY RUN' if DRY_RUN else 'EXECUTED'}",
        f"Cluster: {CLUSTER_NAME}",
        f"Timestamp: {results.get('timestamp', 'unknown')}",
        f"Success: {success}",
        f"Health Check: {health.get('summary', 'N/A')}",
        f"Elapsed: {results.get('elapsed_sec', 'N/A')}s",
        "",
        "Namespaces Started:",
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
    lines.append(f"Next STOP: Today 23:00 UTC / 20:00 BRT")

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
    Main handler: scale up all prod-exclusive namespaces back to previous replica counts.

    Startup sequence:
      1. Check circuit breaker state (log warning if OPEN — do not block startup)
      2. Load previous replica state from DynamoDB (saved by lambda_stop_prod)
         Fall back to DEFAULT_REPLICA_FALLBACK if not available
      3. For each namespace in TARGET_NAMESPACES:
         a. Safety check: skip if in EXCLUDED_NAMESPACES
         b. Scale deployments + statefulsets to previous counts
      4. Health check: verify key prod workloads Running (soft gate)
      5. Update DynamoDB state (circuit breaker)
      6. Send SNS notification

    Does NOT:
      - Scale node groups (nodes are always up — shared cluster)
      - Start RDS (shared database — always running)
      - Restart Linkerd (shared — already running for staging)
      - Wait for node provisioning (nodes already running)
    """
    start_ts = datetime.now(timezone.utc)
    logger.info(
        f"[START] FinOps Prod START — cluster={CLUSTER_NAME} "
        f"env={ENVIRONMENT} dry_run={DRY_RUN} "
        f"health_check={HEALTH_CHECK_ENABLED}"
    )

    results = {
        'timestamp': start_ts.isoformat(),
        'environment': ENVIRONMENT,
        'cluster': CLUSTER_NAME,
        'dry_run': DRY_RUN,
        'namespaces': {},
        'health_check': {},
        'total_failures': 0,
        'success': True,
        'state_source': 'unknown',
    }

    # ------------------------------------------------------------------
    # STEP 1: Check circuit breaker state (informational — do not block)
    # ------------------------------------------------------------------
    cb_state = check_circuit_breaker()
    results['circuit_breaker_state'] = cb_state
    if cb_state == 'OPEN':
        logger.warning(
            "[CB] Circuit breaker is OPEN — previous shutdown had consecutive failures. "
            "Proceeding with startup but INVESTIGATION REQUIRED. "
            f"Check DynamoDB table: {DYNAMODB_TABLE_NAME}"
        )

    # ------------------------------------------------------------------
    # STEP 2: Load previous replica state from DynamoDB
    # ------------------------------------------------------------------
    previous_state = load_previous_state_from_dynamodb()

    if previous_state:
        results['state_source'] = 'dynamodb'
        logger.info(f"[STATE] Using DynamoDB previous state for {len(previous_state)} namespace(s)")
    else:
        results['state_source'] = 'defaults'
        previous_state = DEFAULT_REPLICA_FALLBACK
        logger.warning(
            "[STATE] No DynamoDB state available — using DEFAULT_REPLICA_FALLBACK. "
            "This may scale up to different replica counts than were running before shutdown."
        )

    # ------------------------------------------------------------------
    # STEP 3: Scale up each namespace
    # ------------------------------------------------------------------
    for namespace in TARGET_NAMESPACES:
        ns_state = previous_state.get(namespace, DEFAULT_REPLICA_FALLBACK.get(namespace, {}))

        if not ns_state:
            logger.warning(
                f"[START] No state found for {namespace} — skipping "
                "(no deployments/statefulsets in default config)"
            )
            results['namespaces'][namespace] = {
                'namespace': namespace,
                'status': 'skipped_no_state',
                'message': 'No previous state or default config found',
            }
            continue

        try:
            ns_result = scale_up_namespace(namespace, ns_state, results)
            results['namespaces'][namespace] = ns_result

            if ns_result.get('failures'):
                results['total_failures'] += len(ns_result['failures'])
                results['success'] = False
                logger.warning(
                    f"[START] {namespace}: {len(ns_result['failures'])} failure(s): "
                    f"{ns_result['failures']}"
                )

        except Exception as exc:
            logger.error(
                f"[START] Unexpected error processing {namespace}: {exc}", exc_info=True
            )
            results['namespaces'][namespace] = {
                'namespace': namespace,
                'status': 'error',
                'message': str(exc),
                'failures': [str(exc)],
            }
            results['total_failures'] += 1
            results['success'] = False

    # ------------------------------------------------------------------
    # STEP 3b: Restore RabbitMQ via RabbitmqCluster CR (operator-controlled)
    # Must use CR PATCH — direct StatefulSet scale is reverted by the operator.
    # rabbitmq_previous_replicas was saved to DynamoDB by lambda_stop_prod.
    # ------------------------------------------------------------------
    logger.info("[START] Restoring RabbitMQ via RabbitmqCluster CR (prod-data-rabbitmq)")
    full_item = load_full_dynamodb_item()
    rmq_results = restore_rabbitmq_cluster(full_item)
    results['rabbitmq'] = rmq_results
    if rmq_results and not all(r.get('ok') for r in rmq_results):
        failed = [r['name'] for r in rmq_results if not r.get('ok')]
        logger.error(f"[START] RabbitMQ restore failures: {failed}")
        results['total_failures'] += len(failed)
        results['success'] = False
    else:
        scaled = [f"{r['name']}={r.get('target_replicas')}" for r in rmq_results if r.get('ok')]
        logger.info(f"[START] RabbitMQ restored: {scaled}")

    # ------------------------------------------------------------------
    # STEP 4: Health check (soft gate — DEGRADED does not block)
    # ------------------------------------------------------------------
    if HEALTH_CHECK_ENABLED and not DRY_RUN:
        logger.info(f"[HEALTH] Waiting {WORKLOAD_TIMEOUT_SEC}s for workloads to become ready...")
        ok, diag = verify_prod_health(timeout_sec=WORKLOAD_TIMEOUT_SEC)
        results['health_check'] = diag

        if not ok:
            logger.warning(
                f"[HEALTH] Prod workloads not fully ready after {WORKLOAD_TIMEOUT_SEC}s. "
                "Setting success=False (DEGRADED). Pods are starting — check cluster in ~5 min."
            )
            results['success'] = False
            results['degraded_reason'] = 'HEALTH_CHECK_FAILED'
    else:
        results['health_check'] = {'result': 'SKIPPED' if not HEALTH_CHECK_ENABLED else 'DRY_RUN'}

    # ------------------------------------------------------------------
    # STEP 5: Update DynamoDB state
    # ------------------------------------------------------------------
    update_dynamodb_state(results)

    # ------------------------------------------------------------------
    # STEP 6: Send notification
    # ------------------------------------------------------------------
    send_notification(results)

    elapsed = (datetime.now(timezone.utc) - start_ts).total_seconds()
    results['elapsed_sec'] = round(elapsed, 1)

    status_code = 200 if results['success'] else 500
    logger.info(
        f"[DONE] Prod START completed in {elapsed:.1f}s — "
        f"success={results['success']} failures={results['total_failures']}"
    )

    return {'statusCode': status_code, 'body': results}
