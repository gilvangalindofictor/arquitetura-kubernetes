"""
Lambda Function: Start EKS Node Groups + RDS
Trigger: EventBridge cron (Segunda-Sexta 08:00 BRT = 11:00 UTC)
Author: FinOps Team
Date: 2026-01-29

Environment Variables:
- CLUSTER_NAME: k8s-platform-cluster
- AWS_REGION: us-east-1
- ENVIRONMENT: dev|staging|prod
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
autoscaling = boto3.client('autoscaling', config=boto3.session.Config(connect_timeout=10, read_timeout=30))

# Configuration from environment variables
CLUSTER_NAME = os.environ.get('CLUSTER_NAME', 'k8s-platform-cluster')
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
RDS_INSTANCE_ID = os.environ.get('RDS_INSTANCE_ID', '')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', '')
CLUSTER_NAME = os.environ.get('CLUSTER_NAME', 'k8s-platform-cluster')

# Node groups configuration
NODE_GROUPS_CONFIG = {
    'system': {'min': 2, 'desired': 2, 'max': 4},
    'workloads': {'min': 2, 'desired': 3, 'max': 6},
    'critical': {'min': 2, 'desired': 2, 'max': 4}
}


def lambda_handler(event, context):
    """
    Main handler for Lambda function
    """
    logger.info(f"Starting EKS node groups for environment: {ENVIRONMENT}")
    logger.info(f"Cluster: {CLUSTER_NAME}, Region: {AWS_REGION}")

    results = {
        'timestamp': datetime.utcnow().isoformat(),
        'environment': ENVIRONMENT,
        'cluster': CLUSTER_NAME,
        'node_groups': {},
        'rds': {},
        'success': True
    }

    try:
        # Start node groups
        for ng_name, config in NODE_GROUPS_CONFIG.items():
            try:
                start_node_group(ng_name, config, results)
            except Exception as e:
                logger.error(f"Error starting node group {ng_name}: {str(e)}")
                results['node_groups'][ng_name] = {'status': 'error', 'message': str(e)}
                results['success'] = False

        # Resume Cluster Autoscaler ASG processes suspended during shutdown
        resume_cluster_autoscaler(results)

        # Start RDS if configured
        if RDS_INSTANCE_ID:
            try:
                start_rds(RDS_INSTANCE_ID, results)
            except Exception as e:
                logger.error(f"Error starting RDS {RDS_INSTANCE_ID}: {str(e)}")
                results['rds'] = {'status': 'error', 'message': str(e)}
                results['success'] = False

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


def resume_cluster_autoscaler(results):
    """
    Resume Cluster Autoscaler ASG scaling processes (Launch, Terminate)
    that were suspended during shutdown to prevent DaemonSet re-scaling.
    FinOps fix: pair with suspend in lambda_stop.py (2026-03-11)
    """
    try:
        cluster_tag_key = f'k8s.io/cluster-autoscaler/{CLUSTER_NAME}'
        paginator = autoscaling.get_paginator('describe_auto_scaling_groups')
        resumed_asgs = []

        for page in paginator.paginate():
            for asg in page['AutoScalingGroups']:
                # Check if ASG belongs to this cluster
                tags = {t['Key']: t['Value'] for t in asg.get('Tags', [])}
                if cluster_tag_key not in tags:
                    continue

                # Only resume if processes are actually suspended
                suspended = [p['ProcessName'] for p in asg.get('SuspendedProcesses', [])]
                if 'Launch' in suspended or 'Terminate' in suspended:
                    asg_name = asg['AutoScalingGroupName']
                    logger.info(f"Resuming scaling processes for ASG: {asg_name}")
                    autoscaling.resume_processes(
                        AutoScalingGroupName=asg_name,
                        ScalingProcesses=['Launch', 'Terminate']
                    )
                    resumed_asgs.append(asg_name)

        results['autoscaler_resumed'] = resumed_asgs
        logger.info(f"Cluster Autoscaler ASG processes resumed: {len(resumed_asgs)} ASGs")
    except Exception as e:
        logger.error(f"Failed to resume Cluster Autoscaler: {str(e)}")
        results['autoscaler_resume_error'] = str(e)
        # Non-blocking: continue with startup even if this fails


def start_node_group(ng_name, config, results):
    """
    Start (scale up) an EKS node group
    """
    logger.info(f"Scaling node group {ng_name} to {config['desired']} nodes...")

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

    logger.info(f"Node group {ng_name} update initiated. Update ID: {update_id}")

    results['node_groups'][ng_name] = {
        'status': 'initiated',
        'update_id': update_id,
        'config': config
    }


def start_rds(rds_instance, results):
    """
    Start RDS instance if stopped
    """
    logger.info(f"Checking RDS instance: {rds_instance}")

    # Get current status
    response = rds.describe_db_instances(
        DBInstanceIdentifier=rds_instance
    )

    db_instance = response['DBInstances'][0]
    status = db_instance['DBInstanceStatus']

    logger.info(f"RDS {rds_instance} current status: {status}")

    if status == 'available':
        logger.info(f"RDS {rds_instance} is already available")
        results['rds'] = {
            'instance': rds_instance,
            'status': 'already_available',
            'message': 'No action needed'
        }
        return

    if status == 'stopped':
        logger.info(f"Starting RDS instance {rds_instance}...")

        rds.start_db_instance(
            DBInstanceIdentifier=rds_instance
        )

        logger.info(f"RDS {rds_instance} start initiated")

        results['rds'] = {
            'instance': rds_instance,
            'status': 'start_initiated',
            'previous_status': status
        }
        return

    if status in ['starting', 'backing-up']:
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


def update_dynamodb_state(results):
    """
    Update DynamoDB table with startup state and timestamp
    """
    if not DYNAMODB_TABLE_NAME:
        logger.warning("DYNAMODB_TABLE_NAME not configured, skipping state update")
        return

    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)

        timestamp = datetime.utcnow().isoformat()

        # Prepare update expression
        update_expr = "SET last_startup = :timestamp"
        expr_attr_values = {':timestamp': timestamp}

        if results['success']:
            # Success: reset startup_failures counter
            update_expr += ", startup_failures = :zero"
            expr_attr_values[':zero'] = 0
            logger.info("Startup successful, resetting failure counter")
        else:
            # Failure: increment startup_failures counter
            update_expr += ", startup_failures = startup_failures + :one"
            expr_attr_values[':one'] = 1
            logger.warning("Startup failed, incrementing failure counter")

            # Check if circuit breaker should open (after fetching current count)
            response = table.get_item(Key={'environment': ENVIRONMENT})
            if 'Item' in response:
                current_failures = int(response['Item'].get('startup_failures', 0))
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

        logger.info(f"DynamoDB state updated: last_startup={timestamp}, success={results['success']}")

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

    subject = f"EKS Start - {ENVIRONMENT} - {'SUCCESS' if results['success'] else 'FAILED'}"

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
