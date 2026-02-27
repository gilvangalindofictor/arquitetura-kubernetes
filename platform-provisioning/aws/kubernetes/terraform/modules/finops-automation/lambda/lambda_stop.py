"""
Lambda Function: Stop EKS Node Groups + RDS
Trigger: EventBridge cron (Segunda-Sexta 18:00 BRT = 21:00 UTC)
Author: FinOps Team
Date: 2026-01-29

Environment Variables:
- CLUSTER_NAME: k8s-platform-cluster
- AWS_REGION: us-east-1
- ENVIRONMENT: dev|staging|prod
- CREATE_RDS_SNAPSHOT: true|false (default: false)
"""

import boto3
import os
import logging
from datetime import datetime

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
eks = boto3.client('eks')
rds = boto3.client('rds')
sns = boto3.client('sns')
dynamodb = boto3.resource('dynamodb')

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

logger.info(f"FinOps Protection: EXCLUDED_NODE_GROUPS={EXCLUDED_NODE_GROUPS}, MIN_SYSTEM_NODES={MIN_SYSTEM_NODES}, ENABLE_SCALING_PROTECTION={ENABLE_SCALING_PROTECTION}")

# Node groups configuration (scale to 0 only if NOT protected)
NODE_GROUPS_CONFIG = {
    'system': {'min': MIN_SYSTEM_NODES if ENABLE_SCALING_PROTECTION else 0, 'desired': MIN_SYSTEM_NODES if ENABLE_SCALING_PROTECTION else 0, 'max': 4},
    'workloads': {'min': 0, 'desired': 0, 'max': 6},
    'critical': {'min': MIN_CRITICAL_NODES if ENABLE_SCALING_PROTECTION else 0, 'desired': MIN_CRITICAL_NODES if ENABLE_SCALING_PROTECTION else 0, 'max': 4}
}


def lambda_handler(event, context):
    """
    Main handler for Lambda function
    """
    logger.info(f"Stopping EKS node groups for environment: {ENVIRONMENT}")
    logger.info(f"Cluster: {CLUSTER_NAME}, Region: {AWS_REGION}")
    logger.info(f"RDS Snapshot: {CREATE_RDS_SNAPSHOT}")

    results = {
        'timestamp': datetime.utcnow().isoformat(),
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

        # Stop node groups (scale to 0 or MIN if protected)
        for ng_name, config in NODE_GROUPS_CONFIG.items():
            try:
                # Check if node group is excluded from scaling
                if ng_name in EXCLUDED_NODE_GROUPS:
                    logger.info(f"Node group {ng_name} is EXCLUDED from scaling (protection enabled)")
                    results['node_groups'][ng_name] = {
                        'status': 'protected',
                        'message': f'Node group excluded from scaling (min={config["min"]}, desired={config["desired"]})',
                        'config': config
                    }
                    continue

                stop_node_group(ng_name, config, results)
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


def stop_node_group(ng_name, config, results):
    """
    Stop (scale to 0) an EKS node group
    """
    logger.info(f"Scaling node group {ng_name} to 0 nodes...")

    response = eks.update_nodegroup_config(
        clusterName=CLUSTER_NAME,
        nodegroupName=ng_name,
        scalingConfig={
            'minSize': config['min'],
            'desiredSize': config['desired'],
            'maxSize': config['max']
        }
    )

    update_id = response.get('update', {}).get('id', 'unknown')

    logger.info(f"Node group {ng_name} scale-down initiated. Update ID: {update_id}")

    results['node_groups'][ng_name] = {
        'status': 'stop_initiated',
        'update_id': update_id,
        'config': config
    }


def create_snapshot(rds_instance, results):
    """
    Create RDS snapshot before stopping
    """
    snapshot_id = f"{rds_instance}-shutdown-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"

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
            'created_at': datetime.utcnow().isoformat()
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

        timestamp = datetime.utcnow().isoformat()

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
