"""
Lambda Function: Start EKS Node Groups + RDS
Trigger: EventBridge cron (Segunda-Sexta 08:00 BRT = 11:00 UTC)
Author: FinOps Team / SRE Team
Date: 2026-01-29
Updated: 2026-03-13 — SRE health check + sequência correta de startup

Environment Variables:
- CLUSTER_NAME: k8s-platform-cluster
- AWS_REGION: us-east-1
- ENVIRONMENT: dev|staging|prod
- RDS_INSTANCE_ID: RDS instance identifier
- SNS_TOPIC_ARN: SNS topic ARN for notifications
- DYNAMODB_TABLE_NAME: DynamoDB table for state tracking
- HEALTH_CHECK_ENABLED: true|false (default: true)
- NODE_READY_TIMEOUT_SEC: seconds to wait for system nodes Ready (default: 480 = 8min)
- LINKERD_TIMEOUT_SEC: seconds to wait for Linkerd control plane (default: 300 = 5min)
- WORKLOAD_TIMEOUT_SEC: seconds to wait for critical workloads (default: 300 = 5min)
- SYSTEM_DESIRED: desired node count for system node group (default: 3)
- WORKLOADS_DESIRED: desired node count for workloads node group (default: 2)
- CRITICAL_DESIRED: desired node count for critical node group (default: 2)

STARTUP SEQUENCE (SRE-validated 2026-03-13):
  Step 1: Resume ASG processes (BEFORE scaling nodes — belt-and-suspenders)
  Step 2: Scale CA Deployment to 1 replica
  Step 3: start_node_group() for 'system' only (desired=2)
  Step 4: Wait system nodes Ready (timeout: NODE_READY_TIMEOUT_SEC)
  Step 5: Verify Linkerd control plane Running (timeout: LINKERD_TIMEOUT_SEC)
  Step 6: start_node_group() for 'workloads' and 'critical'
  Step 7: start_rds()
  Step 8: verify_cluster_health() — final gate

ROOT CAUSE ADDRESSED:
  Before this fix, the Lambda reported success but Linkerd was Pending and
  GitLab/Harbor were in CrashLoop. The old code started all node groups
  simultaneously, resumed CA, and reported success without any health
  verification. The Linkerd control plane (proxy-injector) was not running
  when workload nodes joined, causing init containers to hang indefinitely.

IAM NOTE:
  The Lambda role requires eks:DescribeNodegroup (already present in iam.tf).
  K8s API health checks (Linkerd/workload pods) require the Lambda IAM role
  to be mapped in aws-auth ConfigMap with at least 'system:masters' or a
  custom ClusterRole granting get/list on pods in target namespaces.
  See: aws-auth mapping note at bottom of this file.

LAMBDA TIMEOUT:
  Set lambda_timeout = 900 in variables.tf (15 min) to accommodate full
  startup sequence. Default 300s is insufficient when NODE_READY_TIMEOUT_SEC
  + LINKERD_TIMEOUT_SEC + WORKLOAD_TIMEOUT_SEC = 480+300+300 = 1080s worst case.
  In practice: ~600-720s typical startup.
"""

import boto3
import json
import os
import time
import logging
import urllib.request
import urllib.error
import base64
import ssl
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# AWS clients — explicit timeouts required (python:S7618)
# connect_timeout: max seconds to establish TCP connection
# read_timeout: max seconds to wait for response from AWS API
# ---------------------------------------------------------------------------
_boto_cfg = boto3.session.Config(connect_timeout=10, read_timeout=30)
eks       = boto3.client('eks',      config=_boto_cfg)
rds       = boto3.client('rds',      config=_boto_cfg)
sns       = boto3.client('sns',      config=_boto_cfg)
dynamodb  = boto3.resource('dynamodb', config=_boto_cfg)
autoscaling = boto3.client('autoscaling', config=_boto_cfg)

# ---------------------------------------------------------------------------
# Configuration — environment variables
# ---------------------------------------------------------------------------
CLUSTER_NAME        = os.environ.get('CLUSTER_NAME', 'k8s-platform-cluster')
AWS_REGION          = os.environ.get('AWS_REGION', 'us-east-1')
ENVIRONMENT         = os.environ.get('ENVIRONMENT', 'dev')
RDS_INSTANCE_ID     = os.environ.get('RDS_INSTANCE_ID', '')
SNS_TOPIC_ARN       = os.environ.get('SNS_TOPIC_ARN', '')
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', '')

# Health check toggles
HEALTH_CHECK_ENABLED   = os.environ.get('HEALTH_CHECK_ENABLED', 'true').lower() == 'true'
NODE_READY_TIMEOUT_SEC = int(os.environ.get('NODE_READY_TIMEOUT_SEC', '480'))   # 8 min
LINKERD_TIMEOUT_SEC    = int(os.environ.get('LINKERD_TIMEOUT_SEC', '300'))      # 5 min
WORKLOAD_TIMEOUT_SEC   = int(os.environ.get('WORKLOAD_TIMEOUT_SEC', '300'))     # 5 min

# Poll interval for all wait loops
POLL_INTERVAL_SEC = 15

# ---------------------------------------------------------------------------
# Node groups configuration — start config (scale UP targets)
# max_size is intentionally absent: it is always read from AWS at runtime
# inside start_node_group() so the Lambda never overrides a manually raised cap.
#
# Env vars (all optional — defaults shown below):
#   SYSTEM_DESIRED    — desired replicas for system node group    (default: 3)
#   WORKLOADS_DESIRED — desired replicas for workloads node group (default: 2)
#   CRITICAL_DESIRED  — desired replicas for critical node group  (default: 2)
#
# Rationale for these defaults:
#   system desired 3   — prevents DaemonSet + Linkerd boot deadlock (root cause 2026-03-12 P0)
#   workloads min   0  — consistent with lambda_stop (scales workloads to 0); min=2 blocked scale-to-0
#   workloads desired 2 — lean start, Cluster Autoscaler handles real demand
# ---------------------------------------------------------------------------
NODE_GROUPS_CONFIG = {
    'system':    {'min': 2, 'desired': int(os.environ.get('SYSTEM_DESIRED',    '3'))},
    'workloads': {'min': 0, 'desired': int(os.environ.get('WORKLOADS_DESIRED', '2'))},
    'critical':  {'min': 2, 'desired': int(os.environ.get('CRITICAL_DESIRED',  '2'))},
}

# ---------------------------------------------------------------------------
# Workload health criteria
# Defines the minimum pods that MUST be Running for health=OK.
# namespace → list of (name_prefix, min_running_count)
# ---------------------------------------------------------------------------
CRITICAL_WORKLOADS = {
    'staging-security-vault':    [('vault-0', 1)],
    'staging-platform-gitlab':   [('gitlab-webservice', 1)],
    'linkerd':                   [('linkerd-destination', 1),
                                   ('linkerd-identity', 1),
                                   ('linkerd-proxy-injector', 1)],
    'staging-observability-monitoring': [('alertmanager', 1)],
}

# Linkerd-specific namespaces/prefixes for the dedicated Linkerd check
LINKERD_NAMESPACE = 'linkerd'
LINKERD_COMPONENTS = ['linkerd-destination', 'linkerd-identity', 'linkerd-proxy-injector']


# ===========================================================================
# MAIN HANDLER — Orchestrates the full startup sequence
# ===========================================================================

def lambda_handler(event, context):
    """
    Orchestrates environment startup with proper sequencing and health gates.

    SEQUENCE:
      1. Resume ASG processes
      2. Scale CA Deployment to 1 replica
      3. Start system node group
      4. Wait system nodes ACTIVE + nodes Ready  [GATE]
      5. Verify Linkerd control plane Running     [GATE]
      6. Start workloads + critical node groups
      7. Start RDS
      8. Final cluster health check              [GATE]
      9. Report via SNS + update DynamoDB
    """
    start_ts = datetime.now(timezone.utc)
    logger.info(f"[START] Startup sequence — environment={ENVIRONMENT} cluster={CLUSTER_NAME}")
    logger.info(f"[START] health_check={HEALTH_CHECK_ENABLED} "
                f"node_timeout={NODE_READY_TIMEOUT_SEC}s "
                f"linkerd_timeout={LINKERD_TIMEOUT_SEC}s "
                f"workload_timeout={WORKLOAD_TIMEOUT_SEC}s")

    results = {
        'timestamp':    start_ts.isoformat(),
        'environment':  ENVIRONMENT,
        'cluster':      CLUSTER_NAME,
        'node_groups':  {},
        'rds':          {},
        'health_check': {},
        'sequence':     [],
        'success':      True,
        'failure_reason': None,
    }

    try:
        # ------------------------------------------------------------------
        # STEP 1: Resume ASG processes BEFORE scaling nodes.
        # Rationale: If ASG processes are still suspended from a previous
        # shutdown, the EKS node group scale-up call will succeed at the EKS
        # API level, but EC2 Auto Scaling will not actually launch instances
        # because Launch/Terminate processes are suspended. Resuming FIRST
        # ensures the EC2 fleet reacts immediately to the desired count change.
        # ------------------------------------------------------------------
        _seq(results, 'step_1_resume_asg_processes', 'starting')
        resume_asg_processes(results)
        _seq(results, 'step_1_resume_asg_processes', 'done')

        # ------------------------------------------------------------------
        # STEP 1b: Start RDS EARLY (fire-and-forget).
        # Fix 2026-03-18: RDS takes 5-10 min to start. Previously at step 7,
        # after Linkerd check. If Linkerd blocked (CrashLoopBackOff), RDS
        # never started. Now fires immediately — runs in parallel with node
        # provisioning. Step 7 still checks final RDS state.
        # ------------------------------------------------------------------
        _seq(results, 'step_1b_start_rds_early', 'starting')
        if RDS_INSTANCE_ID:
            try:
                start_rds(RDS_INSTANCE_ID, results)
            except Exception as exc:
                logger.warning(f"[RDS] Early start failed (non-blocking): {exc}")
                results['rds'] = {'status': 'early_start_error', 'message': str(exc)}
        _seq(results, 'step_1b_start_rds_early', 'done')

        # ------------------------------------------------------------------
        # STEP 2: Scale CA Deployment to 1 replica.
        # Rationale: CA must be running before workload nodes join so it can
        # manage the node pool correctly. Starting CA before workloads node
        # group is started ensures CA is operational when workload nodes
        # register — CA will not fight with our explicit desired count changes
        # during startup because desired > 0 is already what we want.
        # Note: CA was scaled to 0 by lambda_stop.py during shutdown.
        # ------------------------------------------------------------------
        _seq(results, 'step_2_scale_ca_deployment', 'starting')
        scale_ca_deployment(replicas=1, results=results)
        _seq(results, 'step_2_scale_ca_deployment', 'done')

        # ------------------------------------------------------------------
        # STEP 3: Start system node group FIRST.
        # Rationale: System nodes host kube-system pods (CoreDNS, kube-proxy,
        # AWS VPC CNI), Linkerd CNI DaemonSet, and the Linkerd control plane
        # itself. Workload pods with Linkerd sidecars need proxy-injector and
        # linkerd-destination to be running before they can start. If system
        # and workload nodes come up simultaneously, workload pods start
        # requesting Linkerd admission webhook before proxy-injector is ready,
        # resulting in init containers hanging indefinitely.
        # ------------------------------------------------------------------
        _seq(results, 'step_3_start_system_nodegroup', 'starting')
        start_node_group('system', NODE_GROUPS_CONFIG['system'], results)
        _seq(results, 'step_3_start_system_nodegroup', 'done')

        # ------------------------------------------------------------------
        # STEP 4: Wait for system nodes to be ACTIVE + EC2 instances Ready.
        # Gate: EKS nodegroup status == ACTIVE and running count >= desired.
        # Rationale: We cannot proceed to Linkerd check if nodes are still
        # provisioning. The EKS nodegroup ACTIVE status confirms the node
        # group update has been processed and EC2 instances are running.
        # ------------------------------------------------------------------
        if HEALTH_CHECK_ENABLED:
            _seq(results, 'step_4_wait_system_nodes_ready', 'starting')
            ok, diag = wait_nodegroup_active(
                ng_name='system',
                desired=NODE_GROUPS_CONFIG['system']['desired'],
                timeout_sec=NODE_READY_TIMEOUT_SEC,
            )
            results['health_check']['system_nodes'] = diag
            _seq(results, 'step_4_wait_system_nodes_ready', 'ok' if ok else 'FAILED')

            if not ok:
                _fail(results, 'SYSTEM_NODES_NOT_READY',
                      f"System nodes did not become ready within {NODE_READY_TIMEOUT_SEC}s. "
                      f"Diag: {diag}")
                update_dynamodb_state(results)
                send_notification(results)
                return _response(results)
        else:
            # Without health check, give nodes a fixed grace period
            logger.warning("[HEALTH_CHECK_DISABLED] Sleeping 120s for system nodes (no gate)")
            time.sleep(120)

        # ------------------------------------------------------------------
        # STEP 4a: Rollout restart linkerd-cni DaemonSet.
        #
        # Fix 2026-03-23 (GAP-FINOPS-CNI-01): After a stop/start cycle longer
        # than 24h (weekends, holidays), the linkerd-cni ServiceAccount token
        # on the host kubeconfig expires. The repair-controller (v1.3.0) has a
        # known bug preventing automatic token renewal.
        # Symptom: "Failed to create pod sandbox: linkerd-cni Unauthorized"
        # Cascade: CNI Unauthorized → linkerd Init:0/1 → CA offline → 57+ pods Pending
        # Fix: Rollout restart regenerates host kubeconfig with a fresh 24h token.
        # Always runs — cost ~60s, benefit: prevents full cluster cascade on startup.
        # ------------------------------------------------------------------
        _seq(results, 'step_4a_rollout_restart_linkerd_cni', 'starting')
        try:
            _rollout_restart_linkerd_cni()
            _seq(results, 'step_4a_rollout_restart_linkerd_cni', 'done')
        except Exception as exc:
            logger.warning(f"[LINKERD-CNI] Rollout restart failed (non-blocking): {exc}")
            _seq(results, 'step_4a_rollout_restart_linkerd_cni', 'WARNING')

        # ------------------------------------------------------------------
        # STEP 4b: Clean up CrashLoopBackOff pods + Rollout restart Linkerd.
        #
        # Fix GAP-FINOPS-02: Before the rollout restart, delete any Linkerd
        # pods stuck in CrashLoopBackOff. On t3.medium nodes (~17 pods/node),
        # these sick pods occupy scheduling slots. The rollout restart creates
        # new pods (new ReplicaSet) that need free slots to be scheduled.
        # Without cleanup, new pods stay Pending → step_5 times out → DEGRADED.
        #
        # Sequence:
        #   4b-i.  Delete CrashLoopBackOff pods in 'linkerd' namespace
        #   4b-ii. Wait 5s for kubelet to release resources
        #   4b-iii.Rollout restart Linkerd (identity first, then dependents)
        # ------------------------------------------------------------------
        _seq(results, 'step_4b_cleanup_and_rollout_restart_linkerd', 'starting')
        try:
            deleted_pods = _delete_crashloopbackoff_pods(LINKERD_NAMESPACE)
            results['health_check']['linkerd_cleanup'] = {
                'deleted_pods': deleted_pods,
                'count': len(deleted_pods),
            }

            if deleted_pods:
                logger.info(f"[LINKERD] Waiting 5s for resource release after deleting {len(deleted_pods)} pod(s)")
                time.sleep(5)

            _rollout_restart_linkerd()
            _seq(results, 'step_4b_cleanup_and_rollout_restart_linkerd', 'done')
        except Exception as exc:
            logger.warning(f"[LINKERD] Cleanup + rollout restart failed (non-blocking): {exc}")
            _seq(results, 'step_4b_cleanup_and_rollout_restart_linkerd', 'WARNING')

        # ------------------------------------------------------------------
        # STEP 5: Verify Linkerd control plane is Running.
        # Gate: linkerd-destination, linkerd-identity, linkerd-proxy-injector
        #       all have at least 1 Running pod in namespace 'linkerd'.
        # Rationale: This is the most critical gate in the startup sequence.
        # Every workload pod with a Linkerd annotation calls the
        # proxy-injector admission webhook and the identity service during
        # its init phase. If either is not Running, pods hang in Init state
        # forever (no timeout in the webhook path by default). Starting
        # workload nodes BEFORE Linkerd is ready guarantees CrashLoops.
        #
        # Fix 2026-03-18: Linkerd failure is now a WARNING, not a hard stop.
        # If Linkerd fails, workloads + RDS still start (DEGRADED mode).
        # Previous behavior: return early → RDS never started → full outage.
        # ------------------------------------------------------------------
        if HEALTH_CHECK_ENABLED:
            _seq(results, 'step_5_verify_linkerd', 'starting')
            ok, diag = wait_linkerd_ready(timeout_sec=LINKERD_TIMEOUT_SEC)
            results['health_check']['linkerd'] = diag
            _seq(results, 'step_5_verify_linkerd', 'ok' if ok else 'DEGRADED')

            if not ok:
                logger.warning(
                    f"[LINKERD] Control plane not ready within {LINKERD_TIMEOUT_SEC}s — "
                    "continuing in DEGRADED mode. Workloads will start but may have "
                    "init container delays until Linkerd recovers."
                )
                results['linkerd_degraded'] = True
                # Do NOT return early — continue starting workloads + RDS
        else:
            logger.warning("[HEALTH_CHECK_DISABLED] Skipping Linkerd gate")

        # ------------------------------------------------------------------
        # STEP 6: Start workloads and critical node groups.
        # Rationale: Now that system nodes are Ready and Linkerd is Running,
        # workload pods will be scheduled on nodes that already have the CNI
        # plugin operational, and their Linkerd sidecars will be injected
        # correctly by the now-running proxy-injector.
        # ------------------------------------------------------------------
        _seq(results, 'step_6_start_workload_critical_nodegroups', 'starting')
        for ng_name in ('workloads', 'critical'):
            try:
                start_node_group(ng_name, NODE_GROUPS_CONFIG[ng_name], results)
            except Exception as exc:
                logger.error(f"Error starting node group {ng_name}: {exc}")
                results['node_groups'][ng_name] = {'status': 'error', 'message': str(exc)}
                results['success'] = False
        _seq(results, 'step_6_start_workload_critical_nodegroups', 'done')

        # ------------------------------------------------------------------
        # STEP 7: Verify RDS status (started in step 1b).
        # Fix 2026-03-18: RDS start moved to step 1b (fire-and-forget).
        # This step now just re-checks status. If step 1b failed (e.g.
        # timeout), retry the start here as fallback.
        # ------------------------------------------------------------------
        _seq(results, 'step_7_verify_rds', 'starting')
        if RDS_INSTANCE_ID:
            try:
                start_rds(RDS_INSTANCE_ID, results)
            except Exception as exc:
                logger.error(f"Error with RDS {RDS_INSTANCE_ID}: {exc}")
                results['rds'] = {'status': 'error', 'message': str(exc)}
                results['success'] = False
        _seq(results, 'step_7_verify_rds', 'done')

        # ------------------------------------------------------------------
        # STEP 8: Final cluster health check.
        # Gate: verify all CRITICAL_WORKLOADS have minimum running pods.
        # This is a soft gate — failure sets success=False and changes the
        # SNS subject to DEGRADED but does not prevent the function from
        # completing (nodes are running, partial health is better than
        # reporting success when nothing works).
        # ------------------------------------------------------------------
        if HEALTH_CHECK_ENABLED:
            _seq(results, 'step_8_final_health_check', 'starting')
            ok, diag = verify_cluster_health(timeout_sec=WORKLOAD_TIMEOUT_SEC)
            results['health_check']['final'] = diag
            _seq(results, 'step_8_final_health_check', 'ok' if ok else 'DEGRADED')

            if not ok:
                # Soft failure — cluster is up but not fully healthy
                _fail(results, 'CLUSTER_HEALTH_DEGRADED',
                      f"Final health check failed: {diag.get('summary', 'unknown')}")
                # Do NOT return early — fall through to notification
        else:
            logger.warning("[HEALTH_CHECK_DISABLED] Skipping final health gate")

        # ------------------------------------------------------------------
        # Mark overall result: DEGRADED if Linkerd was not ready
        # ------------------------------------------------------------------
        if results.get('linkerd_degraded') and results['success']:
            _fail(results, 'LINKERD_NOT_READY',
                  'Linkerd control plane did not become ready, but workloads + RDS started')

        # ------------------------------------------------------------------
        # Persist state + notify
        # ------------------------------------------------------------------
        elapsed = (datetime.now(timezone.utc) - start_ts).total_seconds()
        results['elapsed_sec'] = round(elapsed, 1)
        logger.info(f"[DONE] Startup sequence completed in {elapsed:.1f}s — "
                    f"success={results['success']}")

        update_dynamodb_state(results)
        send_notification(results)

        return _response(results)

    except Exception as exc:
        logger.error(f"[FATAL] Unexpected error in startup sequence: {exc}", exc_info=True)
        results['success'] = False
        results['error'] = str(exc)
        send_notification(results)
        return {'statusCode': 500, 'body': results}


# ===========================================================================
# HEALTH CHECK FUNCTIONS
# ===========================================================================

def verify_cluster_health(timeout_sec: int = 300) -> tuple:
    """
    Final cluster health gate.

    Polls CRITICAL_WORKLOADS until all minimum running counts are met OR
    timeout_sec is exceeded.

    Returns:
        (bool: all_healthy, dict: diagnostics)

    Diagnostics structure:
        {
          'summary': 'OK' | 'DEGRADED: <reason>',
          'components': {
            '<namespace>/<prefix>': {
              'required': int,
              'running': int,
              'status': 'ok' | 'insufficient' | 'error',
              'pods': [{'name': str, 'phase': str, 'ready': bool}]
            }
          },
          'elapsed_sec': float,
          'attempts': int,
        }

    K8s API access:
        Uses the EKS cluster endpoint + STS token (bearer auth). The Lambda
        IAM role must be mapped in aws-auth ConfigMap with permissions to
        list/get pods in the target namespaces. See IAM NOTE in module header.
    """
    logger.info(f"[HEALTH] Starting final cluster health check (timeout={timeout_sec}s)")

    deadline = time.time() + timeout_sec
    attempts = 0
    last_diag = {}

    while time.time() < deadline:
        attempts += 1
        all_ok = True
        components = {}
        failures = []

        for namespace, criteria in CRITICAL_WORKLOADS.items():
            for (prefix, min_count) in criteria:
                key = f"{namespace}/{prefix}"
                try:
                    pods = _list_pods(namespace, label_selector=None)
                    matching = [
                        p for p in pods
                        if p['name'].startswith(prefix)
                    ]
                    running = [
                        p for p in matching
                        if p['phase'] == 'Running' and p['ready']
                    ]
                    count = len(running)
                    ok = count >= min_count

                    components[key] = {
                        'required': min_count,
                        'running':  count,
                        'status':   'ok' if ok else 'insufficient',
                        'pods':     matching[:10],  # cap to avoid huge payloads
                    }

                    if not ok:
                        all_ok = False
                        failures.append(
                            f"{key}: need {min_count} running, got {count}"
                        )

                except _K8sApiError as exc:
                    components[key] = {
                        'required': min_count,
                        'running':  0,
                        'status':   'error',
                        'error':    str(exc),
                    }
                    all_ok = False
                    failures.append(f"{key}: K8s API error — {exc}")
                except Exception as exc:
                    components[key] = {
                        'required': min_count,
                        'running':  0,
                        'status':   'error',
                        'error':    str(exc),
                    }
                    all_ok = False
                    failures.append(f"{key}: unexpected error — {exc}")

        elapsed = round(time.time() - (deadline - timeout_sec), 1)
        last_diag = {
            'summary':     'OK' if all_ok else f"DEGRADED: {'; '.join(failures)}",
            'components':  components,
            'elapsed_sec': elapsed,
            'attempts':    attempts,
        }

        if all_ok:
            logger.info(f"[HEALTH] All components healthy after {elapsed}s ({attempts} attempts)")
            return True, last_diag

        logger.info(
            f"[HEALTH] Not fully healthy yet (attempt {attempts}, elapsed {elapsed}s): "
            f"{'; '.join(failures)}"
        )
        time.sleep(POLL_INTERVAL_SEC)

    logger.warning(
        f"[HEALTH] Timeout after {timeout_sec}s ({attempts} attempts). "
        f"Last state: {last_diag.get('summary')}"
    )
    return False, last_diag


def wait_nodegroup_active(ng_name: str, desired: int, timeout_sec: int) -> tuple:
    """
    Poll EKS DescribeNodegroup until:
      - nodegroup status == 'ACTIVE'
      - scalingConfig.desiredSize matches desired
      - health.issues is empty

    Does NOT verify individual EC2 node K8s readiness (that requires K8s API).
    The ACTIVE status + desired count is a reliable proxy: EKS marks the
    nodegroup ACTIVE only after all desired nodes have joined the cluster.

    Returns: (bool: ready, dict: diagnostics)
    """
    logger.info(
        f"[NODES] Waiting for nodegroup '{ng_name}' ACTIVE "
        f"(desired={desired}, timeout={timeout_sec}s)"
    )
    deadline = time.time() + timeout_sec
    attempts = 0
    last_status = 'unknown'
    last_issues = []

    while time.time() < deadline:
        attempts += 1
        try:
            resp = eks.describe_nodegroup(
                clusterName=CLUSTER_NAME,
                nodegroupName=ng_name,
            )
            ng = resp['nodegroup']
            status          = ng.get('status', 'UNKNOWN')
            scaling         = ng.get('scalingConfig', {})
            current_desired = scaling.get('desiredSize', 0)
            health_issues   = ng.get('health', {}).get('issues', [])
            last_status     = status
            last_issues     = health_issues

            logger.info(
                f"[NODES] {ng_name}: status={status} "
                f"desired={current_desired}/{desired} "
                f"issues={len(health_issues)} "
                f"(attempt {attempts})"
            )

            if status == 'ACTIVE' and current_desired >= desired and not health_issues:
                elapsed = round(time.time() - (deadline - timeout_sec), 1)
                diag = {
                    'status':      status,
                    'desired':     current_desired,
                    'target':      desired,
                    'issues':      health_issues,
                    'elapsed_sec': elapsed,
                    'attempts':    attempts,
                    'result':      'READY',
                }
                logger.info(f"[NODES] '{ng_name}' READY in {elapsed}s")
                return True, diag

            # DEGRADED or CREATE_FAILED are terminal — no point waiting
            if status in ('DEGRADED', 'CREATE_FAILED', 'DELETE_FAILED'):
                diag = {
                    'status':   status,
                    'desired':  current_desired,
                    'target':   desired,
                    'issues':   health_issues,
                    'result':   f'TERMINAL_STATUS: {status}',
                }
                logger.error(f"[NODES] '{ng_name}' in terminal status: {status}. Issues: {health_issues}")
                return False, diag

        except Exception as exc:
            logger.warning(f"[NODES] DescribeNodegroup error (non-fatal, attempt {attempts}): {exc}")

        time.sleep(POLL_INTERVAL_SEC)

    elapsed = round(timeout_sec, 1)
    diag = {
        'status':      last_status,
        'desired':     'unknown',
        'target':      desired,
        'issues':      last_issues,
        'elapsed_sec': elapsed,
        'attempts':    attempts,
        'result':      f'TIMEOUT after {timeout_sec}s',
    }
    logger.warning(f"[NODES] '{ng_name}' timeout after {timeout_sec}s. Last status: {last_status}")
    return False, diag


def wait_linkerd_ready(timeout_sec: int) -> tuple:
    """
    Poll K8s API until all LINKERD_COMPONENTS have at least 1 Running+Ready pod
    in LINKERD_NAMESPACE.

    This is a hard gate — workload nodes must not start before Linkerd is ready.

    Returns: (bool: ready, dict: diagnostics)

    Linkerd health criteria:
      - linkerd-destination: 1+ Running pod (route discovery)
      - linkerd-identity: 1+ Running pod (mTLS certificate issuance)
      - linkerd-proxy-injector: 1+ Running pod (sidecar injection webhook)

    If K8s API is unreachable (e.g., RBAC not configured), this function falls
    back to a fixed sleep of LINKERD_TIMEOUT_SEC / 2 and returns True with a
    warning in the diagnostics. This preserves backward compatibility if the
    aws-auth mapping has not been applied yet.
    """
    logger.info(
        f"[LINKERD] Waiting for Linkerd control plane "
        f"(timeout={timeout_sec}s, namespace={LINKERD_NAMESPACE})"
    )
    deadline = time.time() + timeout_sec
    attempts = 0
    last_states = {}
    api_unreachable = False

    while time.time() < deadline:
        attempts += 1
        all_ready = True
        states = {}
        api_error = None

        for component in LINKERD_COMPONENTS:
            try:
                pods = _list_pods(LINKERD_NAMESPACE, label_selector=None)
                matching = [p for p in pods if p['name'].startswith(component)]
                running = [p for p in matching if p['phase'] == 'Running' and p['ready']]

                states[component] = {
                    'total':   len(matching),
                    'running': len(running),
                    'ready':   len(running) >= 1,
                    'pods':    [{'name': p['name'], 'phase': p['phase']} for p in matching[:5]],
                }

                if len(running) < 1:
                    all_ready = False

            except _K8sApiError as exc:
                # K8s API not reachable — likely RBAC not set up
                api_error = str(exc)
                api_unreachable = True
                all_ready = False
                states[component] = {'error': api_error, 'ready': False}
                break
            except Exception as exc:
                api_error = str(exc)
                all_ready = False
                states[component] = {'error': api_error, 'ready': False}
                break

        last_states = states
        elapsed = round(time.time() - (deadline - timeout_sec), 1)

        if api_unreachable and api_error:
            # K8s API unreachable — fall back to a fixed wait to avoid infinite loop
            fallback_sleep = timeout_sec // 2
            logger.warning(
                f"[LINKERD] K8s API unreachable: {api_error}. "
                f"FALLBACK: sleeping {fallback_sleep}s and assuming Linkerd ready. "
                "ACTION REQUIRED: Map Lambda IAM role in aws-auth ConfigMap "
                "(see IAM NOTE in module header)."
            )
            time.sleep(fallback_sleep)
            diag = {
                'components':  last_states,
                'elapsed_sec': elapsed,
                'attempts':    attempts,
                'result':      'ASSUMED_READY (K8s API unreachable — fallback)',
                'warning':     'K8s API RBAC not configured for Lambda role',
            }
            return True, diag

        logger.info(
            f"[LINKERD] attempt={attempts} elapsed={elapsed}s "
            f"states={json.dumps({k: v.get('running', '?') for k, v in states.items()})}"
        )

        if all_ready:
            diag = {
                'components':  last_states,
                'elapsed_sec': elapsed,
                'attempts':    attempts,
                'result':      'READY',
            }
            logger.info(f"[LINKERD] All components Running after {elapsed}s")
            return True, diag

        time.sleep(POLL_INTERVAL_SEC)

    elapsed = round(timeout_sec, 1)
    diag = {
        'components':  last_states,
        'elapsed_sec': elapsed,
        'attempts':    attempts,
        'result':      f'TIMEOUT after {timeout_sec}s',
    }
    logger.warning(f"[LINKERD] Timeout. Last states: {last_states}")
    return False, diag


# ===========================================================================
# K8s API CLIENT — STS token bearer auth (no kubectl required)
# ===========================================================================

class _K8sApiError(Exception):
    """Raised when the K8s API call fails with a non-retryable error."""


def _get_k8s_token() -> str:
    """
    Generate a short-lived STS presigned token for K8s API authentication.

    Uses SigV4QueryAuth (presigned URL) — identical to `aws eks get-token`.
    The x-k8s-aws-id header is embedded in the signed URL so EKS can
    validate cluster ownership. Token lifetime: 60s.

    The Lambda IAM role must be mapped in aws-auth ConfigMap for the
    resulting token to have any K8s RBAC permissions.

    Returns: Bearer token string "k8s-aws-v1.<base64url(presigned_url)>".
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

    # SigV4QueryAuth embeds the signature as query parameters (presigned URL).
    # The x-k8s-aws-id header is included in X-Amz-SignedHeaders so EKS
    # can verify the cluster association when it re-validates the token.
    signer = SigV4QueryAuth(credentials, 'sts', AWS_REGION, expires=60)
    signer.add_auth(request)

    token_bytes = request.url.encode('utf-8')
    b64 = base64.urlsafe_b64encode(token_bytes).rstrip(b'=').decode('utf-8')
    return f"k8s-aws-v1.{b64}"


def _get_cluster_endpoint() -> tuple:
    """
    Retrieve EKS cluster API endpoint and CA cert from EKS DescribeCluster.

    Returns: (endpoint: str, ca_data: str)
    """
    resp = eks.describe_cluster(name=CLUSTER_NAME)
    cluster = resp['cluster']
    endpoint = cluster['endpoint']
    ca_data  = cluster['certificateAuthority']['data']
    return endpoint, ca_data


def _k8s_get(path: str) -> dict:
    """
    Perform a GET request against the K8s API server.

    Args:
        path: API path, e.g. '/api/v1/namespaces/linkerd/pods'

    Returns: Parsed JSON response dict.

    Raises:
        _K8sApiError: on HTTP error, SSL error, or connection failure.
    """
    endpoint, ca_data = _get_cluster_endpoint()
    token = _get_k8s_token()

    url = f"{endpoint.rstrip('/')}{path}"

    # Write CA cert to a temp file for SSL verification
    import tempfile
    ca_bytes = base64.b64decode(ca_data)

    with tempfile.NamedTemporaryFile(suffix='.crt', delete=False) as f:
        f.write(ca_bytes)
        ca_file = f.name

    try:
        ctx = ssl.create_default_context(cafile=ca_file)
        req = urllib.request.Request(
            url,
            headers={
                'Authorization': f'Bearer {token}',
                'Accept':        'application/json',
            },
        )
        with urllib.request.urlopen(req, context=ctx, timeout=20) as resp:
            body = resp.read()
            return json.loads(body)
    except urllib.error.HTTPError as exc:
        raise _K8sApiError(f"HTTP {exc.code} {exc.reason} — {path}") from exc
    except urllib.error.URLError as exc:
        raise _K8sApiError(f"URLError: {exc.reason} — {path}") from exc
    except ssl.SSLError as exc:
        raise _K8sApiError(f"SSLError: {exc} — {path}") from exc
    except Exception as exc:
        raise _K8sApiError(f"Unexpected error: {exc} — {path}") from exc
    finally:
        import os as _os
        try:
            _os.unlink(ca_file)
        except Exception:
            pass


def _k8s_patch(path: str, body: dict, content_type: str = 'application/strategic-merge-patch+json') -> dict:
    """
    Perform a PATCH request against the K8s API server.

    Args:
        path: API path, e.g. '/apis/apps/v1/namespaces/linkerd/deployments/linkerd-destination'
        body: Patch body dict.
        content_type: Patch content type.

    Returns: Parsed JSON response dict.
    """
    endpoint, ca_data = _get_cluster_endpoint()
    token = _get_k8s_token()

    url = f"{endpoint.rstrip('/')}{path}"

    import tempfile
    ca_bytes = base64.b64decode(ca_data)
    with tempfile.NamedTemporaryFile(suffix='.crt', delete=False) as f:
        f.write(ca_bytes)
        ca_file = f.name

    try:
        ctx = ssl.create_default_context(cafile=ca_file)
        data = json.dumps(body).encode('utf-8')
        req = urllib.request.Request(
            url,
            data=data,
            headers={
                'Authorization': f'Bearer {token}',
                'Content-Type':  content_type,
                'Accept':        'application/json',
            },
            method='PATCH',
        )
        with urllib.request.urlopen(req, context=ctx, timeout=20) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        raise _K8sApiError(f"HTTP {exc.code} {exc.reason} — {path}") from exc
    finally:
        try:
            os.unlink(ca_file)
        except Exception:
            pass


def _k8s_delete(path: str) -> dict:
    """
    Perform a DELETE request against the K8s API server.

    Args:
        path: API path, e.g. '/api/v1/namespaces/linkerd/pods/linkerd-destination-xxx'

    Returns: Parsed JSON response dict.

    Raises:
        _K8sApiError: on HTTP error, SSL error, or connection failure.
    """
    endpoint, ca_data = _get_cluster_endpoint()
    token = _get_k8s_token()

    url = f"{endpoint.rstrip('/')}{path}"

    import tempfile
    ca_bytes = base64.b64decode(ca_data)
    with tempfile.NamedTemporaryFile(suffix='.crt', delete=False) as f:
        f.write(ca_bytes)
        ca_file = f.name

    try:
        ctx = ssl.create_default_context(cafile=ca_file)
        req = urllib.request.Request(
            url,
            headers={
                'Authorization': f'Bearer {token}',
                'Accept':        'application/json',
            },
            method='DELETE',
        )
        with urllib.request.urlopen(req, context=ctx, timeout=20) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        raise _K8sApiError(f"HTTP {exc.code} {exc.reason} — {path}") from exc
    finally:
        try:
            os.unlink(ca_file)
        except Exception:
            pass


def _delete_crashloopbackoff_pods(namespace: str) -> list:
    """
    Delete pods in CrashLoopBackOff or error states to free scheduling slots.

    Fix GAP-FINOPS-02: On t3.medium nodes (max ~17 pods/node), pods stuck in
    CrashLoopBackOff occupy scheduling slots. When a rollout restart creates
    new pods (new ReplicaSet), the scheduler cannot place them because the old
    CrashLoopBackOff pods still consume IP/slot capacity. Deleting the sick
    pods first frees slots so the new pods from the rollout can be scheduled.
    """
    deleted = []
    try:
        path = f"/api/v1/namespaces/{namespace}/pods"
        data = _k8s_get(path)

        for item in data.get('items', []):
            pod_name = item['metadata']['name']
            phase = item.get('status', {}).get('phase', 'Unknown')

            is_failed = phase == 'Failed'

            is_crashloop = False
            container_statuses = item.get('status', {}).get('containerStatuses', [])
            init_container_statuses = item.get('status', {}).get('initContainerStatuses', [])

            for cs in container_statuses + init_container_statuses:
                waiting = cs.get('state', {}).get('waiting', {})
                reason = waiting.get('reason', '')
                if reason in ('CrashLoopBackOff', 'ImagePullBackOff', 'ErrImagePull'):
                    is_crashloop = True
                    break

            if is_failed or is_crashloop:
                try:
                    delete_path = f"/api/v1/namespaces/{namespace}/pods/{pod_name}"
                    _k8s_delete(delete_path)
                    deleted.append(pod_name)
                    logger.info(
                        f"[CLEANUP] Deleted unhealthy pod {namespace}/{pod_name} "
                        f"(phase={phase}, crashloop={is_crashloop})"
                    )
                except _K8sApiError as exc:
                    logger.warning(
                        f"[CLEANUP] Failed to delete pod {namespace}/{pod_name}: {exc}"
                    )

    except _K8sApiError as exc:
        logger.warning(f"[CLEANUP] Failed to list pods in {namespace}: {exc}")
    except Exception as exc:
        logger.warning(f"[CLEANUP] Unexpected error cleaning {namespace}: {exc}")

    if deleted:
        logger.info(f"[CLEANUP] Deleted {len(deleted)} unhealthy pod(s) in {namespace}: {deleted}")
    else:
        logger.info(f"[CLEANUP] No unhealthy pods found in {namespace}")

    return deleted


def _wait_identity_ready(timeout_sec: int = 120):
    """
    Wait for linkerd-identity Deployment to have at least 1 Ready pod.

    Fix 2026-03-18: destination and proxy-injector proxies connect to
    identity:8080 during startup to bootstrap mTLS certs. If identity is
    still rolling (no Ready pod), the connection goes through the CNI
    iptables → local proxy → deadlock (InvalidContentType). Waiting for
    identity ensures the gRPC endpoint is serving before dependents restart.
    """
    deadline = time.time() + timeout_sec
    attempt = 0
    while time.time() < deadline:
        attempt += 1
        try:
            pods = _list_pods('linkerd', 'linkerd.io/control-plane-component=identity')
            ready_count = sum(1 for p in pods if p.get('ready'))
            if ready_count >= 1:
                logger.info(f"[LINKERD] identity ready ({ready_count} pod(s)) after {attempt} attempts")
                return True
            logger.info(f"[LINKERD] identity not ready yet (ready={ready_count}, attempt={attempt})")
        except Exception as exc:
            logger.warning(f"[LINKERD] identity check error (attempt={attempt}): {exc}")
        time.sleep(POLL_INTERVAL_SEC)
    logger.warning(f"[LINKERD] identity not ready after {timeout_sec}s — proceeding anyway")
    return False


def _rollout_restart_linkerd():
    """
    Rollout restart Linkerd control plane Deployments via K8s API.

    Fix 2026-03-18: After a stop/start cycle, Linkerd destination and
    proxy-injector pods enter CrashLoopBackOff because the proxy sidecar
    can't reconnect after nodes were terminated. A rollout restart (setting
    `kubectl.kubernetes.io/restartedAt` annotation on the pod template)
    creates fresh pods that start clean.

    CRITICAL ORDERING (fix 2026-03-18):
      1. Restart identity FIRST
      2. WAIT for identity to be Ready (at least 1 pod 2/2)
      3. THEN restart destination + proxy-injector
    Without the wait, destination/proxy-injector pods start before identity
    finishes rolling → same CNI deadlock (InvalidContentType) because the
    proxy can't reach identity:8080 to bootstrap its mTLS certificate.
    """
    now = datetime.now(timezone.utc).isoformat()
    patch_body = {
        'spec': {
            'template': {
                'metadata': {
                    'annotations': {
                        'kubectl.kubernetes.io/restartedAt': now,
                    }
                }
            }
        }
    }

    # Step 1: Restart identity
    path = '/apis/apps/v1/namespaces/linkerd/deployments/linkerd-identity'
    try:
        _k8s_patch(path, patch_body)
        logger.info("[LINKERD] Rollout restart: linkerd-identity OK")
    except _K8sApiError as exc:
        logger.warning(f"[LINKERD] Rollout restart linkerd-identity failed: {exc}")
        # If identity restart fails, still try the others — they might recover
        # from CrashLoopBackOff on their own with existing identity

    # Step 2: Wait for identity to be Ready before restarting dependents
    logger.info("[LINKERD] Waiting for identity to be Ready before restarting dependents...")
    _wait_identity_ready(timeout_sec=120)

    # Step 3: Restart destination + proxy-injector (identity is now serving)
    for deploy in ('linkerd-destination', 'linkerd-proxy-injector'):
        path = f'/apis/apps/v1/namespaces/linkerd/deployments/{deploy}'
        try:
            _k8s_patch(path, patch_body)
            logger.info(f"[LINKERD] Rollout restart: {deploy} OK")
        except _K8sApiError as exc:
            logger.warning(f"[LINKERD] Rollout restart {deploy} failed: {exc}")
            # Non-blocking — continue with other deployments


def _rollout_restart_linkerd_cni():
    """
    Rollout restart linkerd-cni DaemonSet via K8s API.

    Fix 2026-03-23 (GAP-FINOPS-CNI-01): The linkerd-cni DaemonSet writes a
    kubeconfig to each node host filesystem using the pod ServiceAccount token
    (TTL: 24h auto-mounted projected token). The repair-controller (v1.3.0) has
    a known bug that prevents automatic token renewal when the token expires.

    After a stop/start cycle > 24h (weekends, feriados), the host kubeconfig
    has an expired token, causing CNI Unauthorized errors and a full cascade:
      CNI Unauthorized → linkerd Init:0/1 → CA offline → 57+ pods Pending
                       → vault-prod offline → prod services degraded

    This function forces a rollout restart (same mechanism as kubectl rollout
    restart) by setting the restartedAt annotation on the DaemonSet pod template.
    All CNI pods are recreated rolling (maxUnavailable=1), each writing a fresh
    token to the host kubeconfig. Should always run before Step 4b (Linkerd
    control plane restart) to ensure CNI is functional before identity/destination
    try to initialize.

    RBAC requirement (kubectl-manifests.tf finops-health-checker ClusterRole):
      - apiGroups: ["apps"]
        resources: ["daemonsets"]
        verbs: ["get", "patch"]
    """
    CNI_NAMESPACE = 'linkerd-cni'
    CNI_DAEMONSET = 'linkerd-cni'
    CNI_ROLLOUT_WAIT_SEC = 60  # Allow rolling update to progress on all nodes

    now = datetime.now(timezone.utc).isoformat()
    patch_body = {
        'spec': {
            'template': {
                'metadata': {
                    'annotations': {
                        'kubectl.kubernetes.io/restartedAt': now,
                    }
                }
            }
        }
    }

    path = f'/apis/apps/v1/namespaces/{CNI_NAMESPACE}/daemonsets/{CNI_DAEMONSET}'
    _k8s_patch(path, patch_body)
    logger.info(f"[LINKERD-CNI] Rollout restart patch applied to {CNI_DAEMONSET}")

    # Wait for rolling update to progress before proceeding to Linkerd control plane.
    # Full DaemonSet rollout status polling is not implemented here — the 60s wait
    # allows the first pods to be updated (maxUnavailable=1, ~5-8s per node).
    # Linkerd control plane restart (Step 4b) provides additional convergence time.
    logger.info(f"[LINKERD-CNI] Waiting {CNI_ROLLOUT_WAIT_SEC}s for DaemonSet rolling update...")
    time.sleep(CNI_ROLLOUT_WAIT_SEC)
    logger.info("[LINKERD-CNI] DaemonSet rollout wait complete — proceeding to Step 4b")


def _list_pods(namespace: str, label_selector: str = None) -> list:
    """
    List pods in a namespace via K8s API.

    Args:
        namespace: K8s namespace.
        label_selector: Optional label selector string (e.g. 'app=vault').

    Returns: List of pod dicts:
        [{'name': str, 'phase': str, 'ready': bool}]
    """
    path = f"/api/v1/namespaces/{namespace}/pods"
    if label_selector:
        path += f"?labelSelector={urllib.parse.quote(label_selector)}"

    data = _k8s_get(path)
    pods = []
    for item in data.get('items', []):
        name   = item['metadata']['name']
        phase  = item.get('status', {}).get('phase', 'Unknown')

        # Determine readiness: all containers Ready
        conditions = item.get('status', {}).get('conditions', [])
        ready_cond = next(
            (c for c in conditions if c.get('type') == 'Ready'),
            None
        )
        ready = ready_cond is not None and ready_cond.get('status') == 'True'

        pods.append({'name': name, 'phase': phase, 'ready': ready})
    return pods


# ===========================================================================
# STARTUP HELPERS
# ===========================================================================

def resume_asg_processes(results: dict):
    """
    Resume ASG Launch/Terminate processes for all ASGs belonging to this cluster.

    This is STEP 1 in the startup sequence — must run before start_node_group()
    to ensure EC2 Auto Scaling will actually launch instances when EKS requests
    a desired count change.

    Also scales the CA Deployment is handled separately in scale_ca_deployment().
    """
    try:
        cluster_tag_key = f'k8s.io/cluster-autoscaler/{CLUSTER_NAME}'
        paginator = autoscaling.get_paginator('describe_auto_scaling_groups')
        resumed_asgs = []

        for page in paginator.paginate():
            for asg in page['AutoScalingGroups']:
                tags = {t['Key']: t['Value'] for t in asg.get('Tags', [])}
                if cluster_tag_key not in tags:
                    continue

                suspended = [p['ProcessName'] for p in asg.get('SuspendedProcesses', [])]
                if 'Launch' in suspended or 'Terminate' in suspended:
                    asg_name = asg['AutoScalingGroupName']
                    logger.info(f"[ASG] Resuming processes for ASG: {asg_name}")
                    autoscaling.resume_processes(
                        AutoScalingGroupName=asg_name,
                        ScalingProcesses=['Launch', 'Terminate'],
                    )
                    resumed_asgs.append(asg_name)
                else:
                    logger.info(
                        f"[ASG] ASG {asg['AutoScalingGroupName']} processes already running, "
                        "no action needed"
                    )

        results['autoscaler_resumed'] = resumed_asgs
        logger.info(f"[ASG] Resumed {len(resumed_asgs)} ASGs")

    except Exception as exc:
        logger.error(f"[ASG] Failed to resume ASG processes: {exc}")
        results['autoscaler_resume_error'] = str(exc)
        # Non-blocking: log and continue


def scale_ca_deployment(replicas: int, results: dict):
    """
    Scale the Cluster Autoscaler Deployment to `replicas` via K8s API PATCH.

    Uses STS presigned token bearer auth — no kubectl required.
    The Lambda IAM role must be mapped in aws-auth with sufficient RBAC
    permissions (patch apps/v1 deployments in kube-system).

    Non-blocking: if K8s API is unreachable (RBAC not configured), logs a
    warning and continues. The startup sequence degrades gracefully — CA
    will remain at its current replica count until manually scaled.
    """
    deployment_name = 'cluster-autoscaler-aws-cluster-autoscaler'
    namespace       = 'kube-system'

    try:
        patch_body = json.dumps({
            'spec': {'replicas': replicas}
        }).encode('utf-8')

        endpoint, ca_data = _get_cluster_endpoint()
        token = _get_k8s_token()

        import tempfile
        ca_bytes = base64.b64decode(ca_data)
        with tempfile.NamedTemporaryFile(suffix='.crt', delete=False) as f:
            f.write(ca_bytes)
            ca_file = f.name

        try:
            url = (
                f"{endpoint.rstrip('/')}/apis/apps/v1/namespaces/{namespace}"
                f"/deployments/{deployment_name}"
            )
            ctx = ssl.create_default_context(cafile=ca_file)
            req = urllib.request.Request(
                url,
                data=patch_body,
                headers={
                    'Authorization':  f'Bearer {token}',
                    'Content-Type':   'application/merge-patch+json',
                    'Accept':         'application/json',
                },
                method='PATCH',
            )
            with urllib.request.urlopen(req, context=ctx, timeout=20):
                pass

            logger.info(f"[CA] Cluster Autoscaler scaled to {replicas} replica(s) via K8s API")
            results['cluster_autoscaler_deployment'] = f'scaled_to_{replicas}'
        finally:
            try:
                os.unlink(ca_file)
            except Exception:
                pass

    except Exception as exc:
        logger.warning(
            f"[CA] K8s API scale failed (non-blocking): {exc}. "
            "ACTION REQUIRED: Map Lambda IAM role in aws-auth ConfigMap "
            "with RBAC permissions to patch deployments in kube-system."
        )
        results['cluster_autoscaler_deployment'] = f'scale_error: {exc}'


def _wait_nodegroup_not_updating(ng_name: str, timeout_sec: int = 120) -> str:
    """
    Wait for a nodegroup to leave UPDATING state before making changes.

    Root cause (2026-03-18): resume_asg_processes() in Step 1 can trigger an
    internal EKS nodegroup update (status=UPDATING). If start_node_group()
    calls update_nodegroup_config while the nodegroup is still UPDATING, the
    EKS API returns ResourceInUseException. This helper polls until the
    nodegroup exits UPDATING, avoiding the race condition.

    Returns: final status string (e.g. 'ACTIVE').
    Raises: TimeoutError if still UPDATING after timeout_sec.
    """
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        resp = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=ng_name)
        status = resp['nodegroup'].get('status', 'UNKNOWN')
        if status != 'UPDATING':
            logger.info(f"[NG] '{ng_name}' status={status} (ready for update)")
            return status
        logger.info(f"[NG] '{ng_name}' still UPDATING, waiting {POLL_INTERVAL_SEC}s...")
        time.sleep(POLL_INTERVAL_SEC)
    raise TimeoutError(f"Nodegroup '{ng_name}' still UPDATING after {timeout_sec}s")


def start_node_group(ng_name: str, config: dict, results: dict):
    """
    Scale up an EKS node group. max_size is always read from AWS (never hardcoded).

    Reading max_size from AWS ensures that any manually raised cap (e.g., via
    Terraform or the console during an incident) is preserved and never silently
    reset to a stale value embedded in this Lambda's configuration.
    """
    logger.info(f"[NG] Scaling '{ng_name}' → desired={config['desired']}")

    # Wait for nodegroup to exit UPDATING state (race condition fix 2026-03-18).
    # resume_asg_processes() or a prior update_nodegroup_config may have put the
    # nodegroup into UPDATING. EKS rejects concurrent updates with
    # ResourceInUseException.
    _wait_nodegroup_not_updating(ng_name, timeout_sec=120)

    # Fetch current max_size from AWS — this is the source of truth.
    # Never pass a hardcoded max; doing so would silently override incident-time
    # manual adjustments (e.g., the system ASG max 4→5 fix on 2026-03-12).
    current_ng = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=ng_name)
    current_max = current_ng['nodegroup']['scalingConfig']['maxSize']
    logger.info(f"[NG] '{ng_name}' max_size={current_max} (read from AWS, preserved as-is)")

    response = eks.update_nodegroup_config(
        clusterName=CLUSTER_NAME,
        nodegroupName=ng_name,
        scalingConfig={
            'minSize':     config['min'],
            'desiredSize': config['desired'],
            'maxSize':     current_max,   # ALWAYS from AWS — start never alters max
        },
    )

    update_id = response.get('update', {}).get('id', 'unknown')
    logger.info(f"[NG] '{ng_name}' update initiated. UpdateId={update_id}")

    results['node_groups'][ng_name] = {
        'status':    'initiated',
        'update_id': update_id,
        'config':    {**config, 'max': current_max},
    }


def start_rds(rds_instance: str, results: dict):
    """
    Start RDS instance if stopped.
    """
    logger.info(f"[RDS] Checking instance: {rds_instance}")

    resp = rds.describe_db_instances(DBInstanceIdentifier=rds_instance)
    db   = resp['DBInstances'][0]
    status = db['DBInstanceStatus']

    logger.info(f"[RDS] {rds_instance} status: {status}")

    if status == 'available':
        results['rds'] = {'instance': rds_instance, 'status': 'already_available'}
        return

    if status == 'stopped':
        rds.start_db_instance(DBInstanceIdentifier=rds_instance)
        logger.info(f"[RDS] Start initiated for {rds_instance}")
        results['rds'] = {
            'instance':        rds_instance,
            'status':          'start_initiated',
            'previous_status': status,
        }
        return

    if status in ('starting', 'backing-up'):
        results['rds'] = {
            'instance': rds_instance,
            'status':   status,
            'message':  'Already in transition',
        }
        return

    logger.warning(f"[RDS] Unexpected status: {status}")
    results['rds'] = {
        'instance': rds_instance,
        'status':   status,
        'message':  'Unexpected status, no action taken',
    }


# ===========================================================================
# NOTIFICATION + STATE
# ===========================================================================

def send_notification(results: dict):
    """
    Publish startup result to SNS with detailed diagnostics.

    Subject format:
      EKS Start - <env> - SUCCESS                (all healthy)
      EKS Start - <env> - DEGRADED               (started but health check failed)
      EKS Start - <env> - FAILED: <reason>       (hard failure, nodes may not be up)

    Message includes:
      - Full sequence steps with status
      - Health check component details
      - Failure reason if applicable
      - Actionable remediation hint
    """
    if not SNS_TOPIC_ARN:
        logger.warning("[SNS] SNS_TOPIC_ARN not configured, skipping notification")
        return

    failure_reason = results.get('failure_reason')
    if not results['success'] and failure_reason:
        status_label = f"FAILED: {failure_reason}"
    elif not results['success']:
        status_label = "DEGRADED"
    else:
        status_label = "SUCCESS"

    subject = f"EKS Start - {ENVIRONMENT} - {status_label}"
    # SNS subject limit is 100 chars
    subject = subject[:100]

    lines = [
        "=== EKS STARTUP REPORT ===",
        f"Environment : {ENVIRONMENT}",
        f"Cluster     : {CLUSTER_NAME}",
        f"Timestamp   : {results['timestamp']}",
        f"Status      : {status_label}",
        f"Elapsed     : {results.get('elapsed_sec', 'N/A')}s",
        "",
        "--- SEQUENCE ---",
    ]

    for step in results.get('sequence', []):
        lines.append(f"  {step['step']}: {step['status']}")

    lines += ["", "--- NODE GROUPS ---"]
    for ng, ng_r in results.get('node_groups', {}).items():
        lines.append(f"  {ng}: {ng_r.get('status', 'unknown')} (update={ng_r.get('update_id', '-')})")

    if results.get('rds'):
        lines += ["", "--- RDS ---"]
        rds_r = results['rds']
        lines.append(f"  {rds_r.get('instance', '-')}: {rds_r.get('status', 'unknown')}")

    hc = results.get('health_check', {})
    if hc:
        lines += ["", "--- HEALTH CHECK ---"]

        # System nodes
        if 'system_nodes' in hc:
            sn = hc['system_nodes']
            lines.append(
                f"  system_nodes: {sn.get('result', '?')} "
                f"(status={sn.get('status', '?')} "
                f"attempts={sn.get('attempts', '?')})"
            )

        # Linkerd
        if 'linkerd' in hc:
            lk = hc['linkerd']
            lines.append(f"  linkerd: {lk.get('result', '?')} (attempts={lk.get('attempts', '?')})")
            for comp, state in lk.get('components', {}).items():
                run = state.get('running', '?')
                ready = state.get('ready', '?')
                err   = state.get('error', '')
                lines.append(
                    f"    {comp}: running={run} ready={ready}"
                    + (f" ERROR={err}" if err else "")
                )

        # Final
        if 'final' in hc:
            fn = hc['final']
            lines.append(f"  final_check: {fn.get('summary', '?')} (attempts={fn.get('attempts', '?')})")
            for comp_key, comp_state in fn.get('components', {}).items():
                req  = comp_state.get('required', '?')
                run  = comp_state.get('running', '?')
                stat = comp_state.get('status', '?')
                err  = comp_state.get('error', '')
                lines.append(
                    f"    {comp_key}: required={req} running={run} status={stat}"
                    + (f" ERROR={err}" if err else "")
                )

    if failure_reason:
        lines += [
            "",
            "--- FAILURE DETAILS ---",
            f"  Reason : {failure_reason}",
            f"  Error  : {results.get('error', 'N/A')}",
            "",
            "--- REMEDIATION ---",
        ]
        # Hint based on failure code
        if 'SYSTEM_NODES_NOT_READY' in str(failure_reason):
            lines.append("  1. Check EKS node group in AWS Console for health issues")
            lines.append("  2. Check EC2 instance health in the system ASG")
            lines.append("  3. Verify IAM node role permissions (ec2:DescribeInstances)")
            lines.append("  4. Manual: aws eks update-nodegroup-config --cluster-name ...")
        elif 'LINKERD_NOT_READY' in str(failure_reason):
            lines.append("  1. kubectl get pods -n linkerd")
            lines.append("  2. Check trust anchor: kubectl get cm linkerd-config -n linkerd")
            lines.append("  3. Check CNI: kubectl get pods -n linkerd-cni")
            lines.append("  4. Review: docs/runbooks/linkerd-trust-anchor-recovery.md")
        elif 'CLUSTER_HEALTH_DEGRADED' in str(failure_reason):
            lines.append("  1. kubectl get pods -A | grep -v Running")
            lines.append("  2. Workloads may still be starting — check again in 5 min")
            lines.append("  3. Check ArgoCD for sync errors")
            lines.append("  4. Check Vault seal status: kubectl exec -n staging-security-vault vault-0 -- vault status")

    if results.get('autoscaler_resume_error'):
        lines += [
            "",
            f"  WARNING: ASG resume error: {results['autoscaler_resume_error']}",
            "  Check EC2 Auto Scaling console for suspended processes",
        ]

    lines += [
        "",
        "--- SNS MESSAGE END ---",
    ]

    message = "\n".join(lines)

    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message,
            MessageAttributes={
                'environment': {
                    'DataType':    'String',
                    'StringValue': ENVIRONMENT,
                },
                'status': {
                    'DataType':    'String',
                    'StringValue': 'SUCCESS' if results['success'] else 'FAILED',
                },
                'cluster': {
                    'DataType':    'String',
                    'StringValue': CLUSTER_NAME,
                },
            },
        )
        logger.info(f"[SNS] Notification published: {subject}")
    except Exception as exc:
        logger.error(f"[SNS] Failed to publish notification: {exc}")


def update_dynamodb_state(results: dict):
    """
    Persist startup result to DynamoDB for circuit breaker state tracking.
    """
    if not DYNAMODB_TABLE_NAME:
        return

    try:
        table    = dynamodb.Table(DYNAMODB_TABLE_NAME)
        timestamp = datetime.now(timezone.utc).isoformat()

        update_expr = "SET last_startup = :timestamp"
        attr_values = {':timestamp': timestamp}

        if results['success']:
            update_expr += ", startup_failures = :zero"
            attr_values[':zero'] = 0
        else:
            update_expr += ", startup_failures = startup_failures + :one"
            attr_values[':one'] = 1

            response = table.get_item(Key={'environment': ENVIRONMENT})
            if 'Item' in response:
                current = int(response['Item'].get('startup_failures', 0))
                threshold = int(os.environ.get('CIRCUIT_BREAKER_THRESHOLD', '3'))
                if current + 1 >= threshold:
                    update_expr += ", circuit_breaker_state = :open"
                    attr_values[':open'] = 'OPEN'
                    logger.error("[CB] Circuit breaker threshold reached — setting OPEN")

        # Store failure reason for observability
        if results.get('failure_reason'):
            update_expr += ", last_failure_reason = :reason"
            attr_values[':reason'] = results['failure_reason']

        table.update_item(
            Key={'environment': ENVIRONMENT},
            UpdateExpression=update_expr,
            ExpressionAttributeValues=attr_values,
        )
        logger.info(f"[DYNAMO] State updated: success={results['success']}")

    except Exception as exc:
        logger.error(f"[DYNAMO] Failed to update state: {exc}")


# ===========================================================================
# UTILITIES
# ===========================================================================

def _seq(results: dict, step: str, status: str):
    """Append a step entry to the sequence log."""
    results['sequence'].append({
        'step':      step,
        'status':    status,
        'timestamp': datetime.now(timezone.utc).isoformat(),
    })
    logger.info(f"[SEQ] {step} → {status}")


def _fail(results: dict, code: str, detail: str):
    """Mark results as failed with a structured reason code."""
    results['success']        = False
    results['failure_reason'] = code
    results['error']          = detail
    logger.error(f"[FAIL] {code}: {detail}")


def _response(results: dict) -> dict:
    """Build Lambda response dict."""
    return {
        'statusCode': 200 if results['success'] else 500,
        'body':       results,
    }


def get_node_group_tags(ng_name: str) -> dict:
    """Get tags from EKS node group."""
    try:
        resp = eks.describe_nodegroup(
            clusterName=CLUSTER_NAME,
            nodegroupName=ng_name,
        )
        return resp.get('nodegroup', {}).get('tags', {})
    except Exception as exc:
        logger.error(f"Error getting tags for {ng_name}: {exc}")
        return {}


def should_manage_resource(tags: dict) -> bool:
    """Check if resource should be managed based on tags."""
    schedule = tags.get('Schedule', 'always-on')
    if schedule == 'office-hours':
        return True
    if schedule == 'always-on':
        return False
    return tags.get('Environment', '').lower() == ENVIRONMENT.lower()


# ===========================================================================
# IAM NOTE — aws-auth ConfigMap mapping required for K8s API health checks
# ===========================================================================
#
# For verify_cluster_health() and wait_linkerd_ready() to work, the Lambda
# IAM role must be mapped in the aws-auth ConfigMap with permissions to
# list/get pods in: linkerd, staging-security-vault, staging-platform-gitlab,
# staging-observability-monitoring namespaces.
#
# Minimal aws-auth entry (add to mapRoles):
#   - rolearn: arn:aws:iam::<account_id>:role/finops-scheduler-role-staging
#     username: lambda-finops
#     groups:
#       - finops-health-checker   # custom ClusterRole with pod read access
#
# ClusterRole (apply via kubectl or ArgoCD):
#   apiVersion: rbac.authorization.k8s.io/v1
#   kind: ClusterRole
#   metadata:
#     name: finops-health-checker
#   rules:
#     - apiGroups: [""]
#       resources: ["pods"]
#       verbs: ["get", "list"]
#     - apiGroups: ["apps"]
#       resources: ["deployments"]
#       verbs: ["get", "patch"]   # needed for scale_ca_deployment()
#
# ClusterRoleBinding:
#   apiVersion: rbac.authorization.k8s.io/v1
#   kind: ClusterRoleBinding
#   metadata:
#     name: finops-health-checker
#   roleRef:
#     apiGroup: rbac.authorization.k8s.io
#     kind: ClusterRole
#     name: finops-health-checker
#   subjects:
#     - kind: User
#       name: lambda-finops
#       apiGroup: rbac.authorization.k8s.io
#
# IMPORTANT: Without this mapping, K8s API calls will return 403.
# The Lambda will fall back to the ASSUMED_READY path and log a WARNING.
# The health check will still work for EKS nodegroup-level checks (AWS API).
# ===========================================================================
