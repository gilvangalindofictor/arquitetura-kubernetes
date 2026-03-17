"""
Lambda Function: Stop EKS Node Groups + RDS
Trigger: EventBridge cron (Segunda-Sexta 18:00 BRT = 21:00 UTC)
Author: FinOps Team
Date: 2026-01-29
Updated: 2026-03-17

Changelog 2026-03-17:
- GAP-LAMBDA-RC3 FIX: Replaced kubectl subprocess in suspend_cluster_autoscaler()
  with direct K8s API PATCH using STS presigned token bearer auth (same pattern
  as lambda_start.py). kubectl is not available in the Lambda runtime — the old
  code emitted a non-blocking warning on every execution and CA was never scaled
  to 0, allowing it to fight the EKS scale-down during shutdown windows.
  No Lambda layer required; uses only standard library + boto3.

Changelog 2026-03-13:
- BUG-001 FIX: Removed hardcoded NODE_GROUPS_CONFIG (max values were wrong).
  stop_node_group() now reads current max_size from AWS via describe_nodegroup
  and preserves it — never hardcodes max.
- BUG-002 FIX: stop_node_group() no longer passes hardcoded maxSize to EKS API.
- NODE_GROUP_NAMES env var replaces NODE_GROUPS_CONFIG dict.
- Unified _boto_cfg applied to all AWS clients (connect_timeout=10, read_timeout=30).
- datetime.utcnow() replaced with datetime.now(timezone.utc) (Python 3.12+ compliance).

Environment Variables:
- CLUSTER_NAME: k8s-platform-cluster
- AWS_REGION: us-east-1
- ENVIRONMENT: dev|staging|prod
- CREATE_RDS_SNAPSHOT: true|false (default: false)
- NODE_GROUP_NAMES: comma-separated list of node group names (default: system,workloads,critical)
"""

import base64
import boto3
import json
import logging
import os
import ssl
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Shared boto3 config — explicit timeouts for all network calls (Lambda compliance)
_boto_cfg = boto3.session.Config(connect_timeout=10, read_timeout=30)

# AWS clients
eks = boto3.client('eks', config=_boto_cfg)
rds = boto3.client('rds', config=_boto_cfg)
sns = boto3.client('sns', config=_boto_cfg)
dynamodb = boto3.resource('dynamodb', config=_boto_cfg)
autoscaling = boto3.client('autoscaling', config=_boto_cfg)

# Configuration from environment variables
CLUSTER_NAME = os.environ.get('CLUSTER_NAME', 'k8s-platform-cluster')
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
RDS_INSTANCE_ID = os.environ.get('RDS_INSTANCE_ID', '')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', '')
CREATE_RDS_SNAPSHOT = os.environ.get('CREATE_RDS_SNAPSHOT', 'false').lower() == 'true'

# FinOps Protection: Excluded node groups (NEVER scale to 0)
EXCLUDED_NODE_GROUPS = os.environ.get('EXCLUDED_NODE_GROUPS', '').split(',')
EXCLUDED_NODE_GROUPS = [ng.strip() for ng in EXCLUDED_NODE_GROUPS if ng.strip()]
MIN_SYSTEM_NODES = int(os.environ.get('MIN_SYSTEM_NODES', '2'))
MIN_CRITICAL_NODES = int(os.environ.get('MIN_CRITICAL_NODES', '2'))
ENABLE_SCALING_PROTECTION = os.environ.get('ENABLE_SCALING_PROTECTION', 'true').lower() == 'true'
SUSPEND_AUTOSCALER_ON_STOP = os.environ.get('SUSPEND_AUTOSCALER_ON_STOP', 'true').lower() == 'true'

logger.info(f"FinOps Protection: EXCLUDED_NODE_GROUPS={EXCLUDED_NODE_GROUPS}, MIN_SYSTEM_NODES={MIN_SYSTEM_NODES}, ENABLE_SCALING_PROTECTION={ENABLE_SCALING_PROTECTION}, SUSPEND_AUTOSCALER={SUSPEND_AUTOSCALER_ON_STOP}")

# Node group names to manage — read from env var, no hardcoded max values (BUG-001 fix)
NODE_GROUP_NAMES = os.environ.get('NODE_GROUP_NAMES', 'system,workloads,critical').split(',')
NODE_GROUP_NAMES = [ng.strip() for ng in NODE_GROUP_NAMES if ng.strip()]


def lambda_handler(event, context):
    """
    Main handler for Lambda function
    """
    logger.info(f"Stopping EKS node groups for environment: {ENVIRONMENT}")
    logger.info(f"Cluster: {CLUSTER_NAME}, Region: {AWS_REGION}")
    logger.info(f"RDS Snapshot: {CREATE_RDS_SNAPSHOT}")

    results = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'environment': ENVIRONMENT,
        'cluster': CLUSTER_NAME,
        'node_groups': {},
        'rds': {},
        'snapshot': {},
        'success': True
    }

    try:
        # Stop RDS (with optional snapshot) if configured
        if RDS_INSTANCE_ID:
            try:
                if CREATE_RDS_SNAPSHOT:
                    create_snapshot(RDS_INSTANCE_ID, results)

                stop_rds(RDS_INSTANCE_ID, results)
            except Exception as e:
                logger.error(f"Error stopping RDS {RDS_INSTANCE_ID}: {str(e)}")
                results['rds'] = {'status': 'error', 'message': str(e)}
                results['success'] = False

        # Suspend Cluster Autoscaler ASG processes to prevent DaemonSet re-scaling
        suspend_cluster_autoscaler(results)

        # Stop node groups (scale to 0; max_size read live from AWS — never hardcoded)
        for ng_name in NODE_GROUP_NAMES:
            try:
                # Check if node group is excluded from scaling
                if ng_name in EXCLUDED_NODE_GROUPS:
                    logger.info(f"Node group {ng_name} is EXCLUDED from scaling (protection enabled)")
                    results['node_groups'][ng_name] = {
                        'status': 'protected',
                        'message': 'Node group excluded from scaling'
                    }
                    continue

                stop_node_group(ng_name, results)
            except Exception as e:
                logger.error(f"Error stopping node group {ng_name}: {str(e)}")
                results['node_groups'][ng_name] = {'status': 'error', 'message': str(e)}
                results['success'] = False

        # Calculate estimated savings
        calculate_savings(results)

        # Update DynamoDB state
        update_dynamodb_state(results)

        # Send notification
        send_notification(results)

        return {
            'statusCode': 200 if results['success'] else 500,
            'body': results
        }

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        results['success'] = False
        results['error'] = str(e)

        send_notification(results)

        return {
            'statusCode': 500,
            'body': results
        }


# ===========================================================================
# K8s API CLIENT — STS token bearer auth (no kubectl required)
# Ported from lambda_start.py — GAP-LAMBDA-RC3 fix (2026-03-17)
# ===========================================================================

def _get_k8s_token() -> str:
    """
    Generate a short-lived STS presigned token for K8s API authentication.

    Uses SigV4QueryAuth (presigned URL) — identical to `aws eks get-token`.
    Token lifetime: 60 seconds.
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


def _scale_ca_deployment(replicas: int, results: dict):
    """
    Scale the Cluster Autoscaler Deployment via K8s API PATCH (no kubectl).

    Uses STS presigned token bearer auth — same pattern as lambda_start.py.
    The Lambda IAM role must be mapped in aws-auth with sufficient RBAC
    permissions (patch apps/v1 deployments in kube-system).
    """
    deployment_name = 'cluster-autoscaler-aws-cluster-autoscaler'
    namespace       = 'kube-system'

    patch_body = json.dumps({'spec': {'replicas': replicas}}).encode('utf-8')
    endpoint, ca_data = _get_cluster_endpoint()
    token = _get_k8s_token()

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
                'Authorization': f'Bearer {token}',
                'Content-Type':  'application/merge-patch+json',
                'Accept':        'application/json',
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


def suspend_cluster_autoscaler(results):
    """
    Suspend Cluster Autoscaler by:
    1. Scaling down the CA Deployment to 0 replicas (prevents active CA from restoring desired counts)
    2. Suspending ASG Launch/Terminate processes (prevents DaemonSet Pending pods from triggering scale-up)
    Fix 2026-03-12: CA was restoring workloads nodegroup from desired=0 to desired=6 during shutdown.
    Fix 2026-03-17: Step 1 now uses K8s API PATCH (STS bearer token) — kubectl not available in Lambda.
    FinOps fix: weekend costs $38-39/dia → $8-12/dia (2026-03-11)
    """
    if not SUSPEND_AUTOSCALER_ON_STOP:
        logger.info("Cluster Autoscaler suspension disabled, skipping")
        return

    # Step 1: Scale down CA Deployment to 0 replicas via K8s API
    # GAP-LAMBDA-RC3 fix (2026-03-17): replaced kubectl subprocess (not in Lambda runtime)
    # with direct K8s API PATCH using STS presigned token bearer auth.
    # This is the critical fix: CA Pod must stop running BEFORE nodegroup scale-down,
    # otherwise CA actively restores desired counts after each EKS API call.
    try:
        _scale_ca_deployment(0, results)
    except Exception as e:
        logger.warning(f"[CA] K8s API scale-to-0 failed (non-blocking): {e}")
        results['cluster_autoscaler_deployment'] = f'suspend_error: {e}'

    # Step 2: Suspend ASG scaling processes (belt-and-suspenders)
    try:
        cluster_tag_key = f'k8s.io/cluster-autoscaler/{CLUSTER_NAME}'
        paginator = autoscaling.get_paginator('describe_auto_scaling_groups')
        suspended_asgs = []

        for page in paginator.paginate():
            for asg in page['AutoScalingGroups']:
                tags = {t['Key']: t['Value'] for t in asg.get('Tags', [])}
                if cluster_tag_key in tags:
                    asg_name = asg['AutoScalingGroupName']
                    logger.info(f"Suspending scaling processes for ASG: {asg_name}")
                    autoscaling.suspend_processes(
                        AutoScalingGroupName=asg_name,
                        ScalingProcesses=['Launch', 'Terminate']
                    )
                    suspended_asgs.append(asg_name)

        results['autoscaler_suspended'] = suspended_asgs
        logger.info(f"Cluster Autoscaler ASG processes suspended: {len(suspended_asgs)} ASGs")
    except Exception as e:
        logger.error(f"Failed to suspend Cluster Autoscaler ASG processes: {str(e)}")
        results['autoscaler_suspend_error'] = str(e)
        # Non-blocking: continue with shutdown even if this fails


def stop_node_group(ng_name, results):
    """
    Stop (scale to 0) an EKS node group.

    BUG-001/BUG-002 FIX (2026-03-13):
    - max_size is read live from describe_nodegroup — never hardcoded.
    - Only minSize and desiredSize are set to 0; maxSize is preserved unchanged.
    - minSize is always forced to 0 during shutdown: a minSize > 0 causes the
      EKS API to reject desiredSize=0. Protection is a startup concern, not shutdown.
    """
    logger.info(f"Describing node group {ng_name} to read current max_size...")

    describe_resp = eks.describe_nodegroup(
        clusterName=CLUSTER_NAME,
        nodegroupName=ng_name
    )
    scaling = describe_resp['nodegroup']['scalingConfig']
    current_max = scaling['maxSize']
    current_desired = scaling['desiredSize']

    logger.info(f"Node group {ng_name}: current scalingConfig={scaling}. Setting minSize=0, desiredSize=0, preserving maxSize={current_max}.")

    response = eks.update_nodegroup_config(
        clusterName=CLUSTER_NAME,
        nodegroupName=ng_name,
        scalingConfig={
            'minSize': 0,        # Always 0 during shutdown — minSize > 0 blocks desiredSize=0
            'desiredSize': 0,
            'maxSize': current_max  # Preserved from live AWS state — never hardcoded
        }
    )

    update_id = response.get('update', {}).get('id', 'unknown')

    logger.info(f"Node group {ng_name} scale-down initiated (minSize=0, desiredSize=0, maxSize={current_max}). Update ID: {update_id}")

    results['node_groups'][ng_name] = {
        'status': 'stop_initiated',
        'update_id': update_id,
        'previous_desired': current_desired,
        'preserved_max': current_max,
        'config': {'min': 0, 'desired': 0, 'max': current_max}
    }


def create_snapshot(rds_instance, results):
    """
    Create RDS snapshot before stopping
    """
    snapshot_id = f"{rds_instance}-shutdown-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}"

    logger.info(f"Creating RDS snapshot: {snapshot_id}")

    try:
        response = rds.create_db_snapshot(
            DBSnapshotIdentifier=snapshot_id,
            DBInstanceIdentifier=rds_instance,
            Tags=[
                {'Key': 'Environment', 'Value': ENVIRONMENT},
                {'Key': 'Type', 'Value': 'shutdown-snapshot'},
                {'Key': 'CreatedBy', 'Value': 'lambda-stop-nodes'}
            ]
        )

        snapshot_status = response['DBSnapshot']['Status']

        logger.info(f"Snapshot {snapshot_id} created with status: {snapshot_status}")

        results['snapshot'] = {
            'snapshot_id': snapshot_id,
            'instance': rds_instance,
            'status': snapshot_status,
            'created_at': datetime.now(timezone.utc).isoformat()
        }

    except Exception as e:
        logger.error(f"Failed to create snapshot: {str(e)}")
        results['snapshot'] = {
            'status': 'error',
            'message': str(e)
        }
        # Don't fail the whole operation if snapshot fails
        # We'll still try to stop the RDS


def stop_rds(rds_instance, results):
    """
    Stop RDS instance
    """
    logger.info(f"Checking RDS instance: {rds_instance}")

    # Get current status
    response = rds.describe_db_instances(
        DBInstanceIdentifier=rds_instance
    )

    db_instance = response['DBInstances'][0]
    status = db_instance['DBInstanceStatus']

    logger.info(f"RDS {rds_instance} current status: {status}")

    if status == 'stopped':
        logger.info(f"RDS {rds_instance} is already stopped")
        results['rds'] = {
            'instance': rds_instance,
            'status': 'already_stopped',
            'message': 'No action needed'
        }
        return

    if status == 'available':
        logger.info(f"Stopping RDS instance {rds_instance}...")

        rds.stop_db_instance(
            DBInstanceIdentifier=rds_instance
        )

        logger.info(f"RDS {rds_instance} stop initiated")

        results['rds'] = {
            'instance': rds_instance,
            'status': 'stop_initiated',
            'previous_status': status
        }
        return

    if status in ['stopping', 'backing-up']:
        logger.info(f"RDS {rds_instance} is already {status}")
        results['rds'] = {
            'instance': rds_instance,
            'status': status,
            'message': 'Already in transition'
        }
        return

    # Unexpected status
    logger.warning(f"RDS {rds_instance} in unexpected status: {status}")
    results['rds'] = {
        'instance': rds_instance,
        'status': status,
        'message': 'Unexpected status, no action taken'
    }


def calculate_savings(results):
    """
    Calculate estimated daily savings
    """
    # Based on STARTUP-SHUTDOWN-STRATEGY.md
    ec2_hourly_cost = 0.2914  # 7 nodes × $30.37/730h
    data_transfer_daily = 0.75
    alb_lcu_daily = 0.33
    rds_hourly_cost = 0.0685  # $50/730h

    daily_savings = (ec2_hourly_cost * 24) + data_transfer_daily + alb_lcu_daily

    if results.get('rds', {}).get('status') in ['stop_initiated', 'already_stopped']:
        daily_savings += (rds_hourly_cost * 24)

    monthly_savings = daily_savings * 22  # 22 business days

    results['savings'] = {
        'daily_usd': round(daily_savings, 2),
        'monthly_usd': round(monthly_savings, 2),
        'annual_usd': round(monthly_savings * 12, 2),
        'currency': 'USD',
        'note': 'Estimated savings based on 8h/day office hours'
    }

    logger.info(f"Estimated savings: ${daily_savings:.2f}/day, ${monthly_savings:.2f}/month")


def update_dynamodb_state(results):
    """
    Update DynamoDB table with shutdown state and timestamp
    """
    if not DYNAMODB_TABLE_NAME:
        logger.warning("DYNAMODB_TABLE_NAME not configured, skipping state update")
        return

    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)

        timestamp = datetime.now(timezone.utc).isoformat()

        # Prepare update expression
        update_expr = "SET last_shutdown = :timestamp, last_stop_time = :timestamp"
        expr_attr_values = {':timestamp': timestamp}

        if results['success']:
            # Success: reset shutdown_failures counter
            update_expr += ", shutdown_failures = :zero"
            expr_attr_values[':zero'] = 0
            logger.info("Shutdown successful, resetting failure counter")
        else:
            # Failure: increment shutdown_failures counter
            update_expr += ", shutdown_failures = shutdown_failures + :one"
            expr_attr_values[':one'] = 1
            logger.warning("Shutdown failed, incrementing failure counter")

            # Check if circuit breaker should open (after fetching current count)
            response = table.get_item(Key={'environment': ENVIRONMENT})
            if 'Item' in response:
                current_failures = int(response['Item'].get('shutdown_failures', 0))
                if current_failures + 1 >= 3:  # Threshold
                    update_expr += ", circuit_breaker_state = :open"
                    expr_attr_values[':open'] = 'OPEN'
                    logger.error("Circuit breaker threshold reached! Setting state to OPEN")

        # Update DynamoDB
        table.update_item(
            Key={'environment': ENVIRONMENT},
            UpdateExpression=update_expr,
            ExpressionAttributeValues=expr_attr_values
        )

        logger.info(f"DynamoDB state updated: last_shutdown={timestamp}, success={results['success']}")

    except Exception as e:
        logger.error(f"Failed to update DynamoDB state: {str(e)}")
        # Don't fail the whole operation if DynamoDB update fails


def send_notification(results):
    """
    Send notification via SNS
    """
    if not SNS_TOPIC_ARN:
        logger.warning("SNS_TOPIC_ARN not configured, skipping notification")
        return

    subject = f"EKS Stop - {ENVIRONMENT} - {'SUCCESS' if results['success'] else 'FAILED'}"

    message_lines = [
        f"Environment: {ENVIRONMENT}",
        f"Cluster: {CLUSTER_NAME}",
        f"Timestamp: {results['timestamp']}",
        "",
        "Node Groups:",
    ]

    for ng_name, ng_result in results.get('node_groups', {}).items():
        message_lines.append(f"  - {ng_name}: {ng_result.get('status', 'unknown')}")

    if results.get('rds'):
        message_lines.append("")
        message_lines.append("RDS:")
        rds_result = results['rds']
        message_lines.append(f"  - {rds_result.get('instance', 'unknown')}: {rds_result.get('status', 'unknown')}")

    if results.get('snapshot'):
        message_lines.append("")
        message_lines.append("Snapshot:")
        snapshot_result = results['snapshot']
        message_lines.append(f"  - {snapshot_result.get('snapshot_id', 'unknown')}: {snapshot_result.get('status', 'unknown')}")

    if results.get('savings'):
        message_lines.append("")
        message_lines.append("Estimated Savings:")
        savings = results['savings']
        message_lines.append(f"  - Daily: ${savings['daily_usd']}")
        message_lines.append(f"  - Monthly: ${savings['monthly_usd']}")
        message_lines.append(f"  - Annual: ${savings['annual_usd']}")

    message_lines.append("")
    message_lines.append("Next Start: Tomorrow 08:00 BRT (11:00 UTC)")

    message = "\n".join(message_lines)

    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        logger.info("Notification sent successfully")
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")


def get_node_group_tags(ng_name):
    """
    Get tags from node group to verify if it should be managed
    """
    try:
        response = eks.describe_nodegroup(
            clusterName=CLUSTER_NAME,
            nodegroupName=ng_name
        )

        tags = response.get('nodegroup', {}).get('tags', {})
        return tags

    except Exception as e:
        logger.error(f"Error getting tags for node group {ng_name}: {str(e)}")
        return {}


def should_manage_resource(tags):
    """
    Check if resource should be managed based on tags
    """
    schedule = tags.get('Schedule', 'always-on')

    if schedule == 'office-hours':
        return True

    if schedule == 'always-on':
        logger.info(f"Resource tagged as 'always-on', skipping")
        return False

    # Default: manage if environment matches
    environment = tags.get('Environment', '')
    return environment.lower() == ENVIRONMENT.lower()
