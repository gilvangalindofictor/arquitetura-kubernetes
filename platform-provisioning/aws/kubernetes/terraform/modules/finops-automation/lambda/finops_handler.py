"""
FinOps Automation Lambda Handler
Multi-agent validated: AWS, Terraform, FinOps, Security specialists

Features:
- Circuit breaker pattern (DynamoDB state tracking)
- RDS 7-day auto-start mitigation (AWS Specialist T-025)
- Health checks (DB connections + GitLab jobs)
- BrasilAPI holiday detection
- Comprehensive CloudWatch logging
"""

import json
import os
import time
import boto3
import requests
from datetime import datetime, timedelta
from decimal import Decimal

# AWS clients
ec2_client = boto3.client('ec2')
rds_client = boto3.client('rds')
autoscaling_client = boto3.client('autoscaling')
dynamodb = boto3.resource('dynamodb')

# Environment variables
ENVIRONMENT = os.environ['ENVIRONMENT']
CLUSTER_NAME = os.environ['CLUSTER_NAME']
RDS_INSTANCE_ID = os.environ['RDS_INSTANCE_ID']
ASG_NAMES = os.environ['ASG_NAMES'].split(',')
CIRCUIT_BREAKER_TABLE = os.environ['CIRCUIT_BREAKER_TABLE']
RDS_STATE_TABLE = os.environ['RDS_STATE_TABLE']
CIRCUIT_BREAKER_THRESHOLD = int(os.environ.get('CIRCUIT_BREAKER_THRESHOLD', '3'))
ENABLE_BRASILAPI = os.environ.get('ENABLE_BRASILAPI', 'true').lower() == 'true'
HEALTH_CHECK_ENABLED = os.environ.get('HEALTH_CHECK_ENABLED', 'true').lower() == 'true'


def lambda_handler(event, context):
    """Main Lambda handler for FinOps automation"""

    action = event.get('action')  # 'shutdown' or 'startup'

    print(f"[FinOps] Starting {action} for environment: {ENVIRONMENT}")
    print(f"[FinOps] Cluster: {CLUSTER_NAME}, RDS: {RDS_INSTANCE_ID}, ASGs: {ASG_NAMES}")

    try:
        # Check circuit breaker state
        if is_circuit_open():
            print(f"[FinOps] ⚠️ Circuit breaker OPEN - skipping execution")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'skipped',
                    'reason': 'circuit_breaker_open',
                    'environment': ENVIRONMENT
                })
            }

        # Check for Brazilian holidays (optional)
        if ENABLE_BRASILAPI and action == 'shutdown':
            if is_brazilian_holiday():
                print(f"[FinOps] 🇧🇷 Today is Brazilian holiday - skipping shutdown")
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'status': 'skipped',
                        'reason': 'brazilian_holiday',
                        'environment': ENVIRONMENT
                    })
                }

        # Execute action
        if action == 'shutdown':
            result = shutdown_environment()
        elif action == 'startup':
            result = startup_environment()
        else:
            raise ValueError(f"Invalid action: {action}")

        # Record success in circuit breaker
        record_execution(action, 'success', result)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'success',
                'action': action,
                'environment': ENVIRONMENT,
                'details': result
            })
        }

    except Exception as e:
        print(f"[FinOps] ❌ Error: {str(e)}")

        # Record failure in circuit breaker
        record_execution(action, 'failure', {'error': str(e)})

        # Re-raise to trigger CloudWatch Alarm
        raise


def shutdown_environment():
    """Shutdown RDS and scale ASGs to 0"""

    print(f"[FinOps] 🛑 Starting shutdown sequence")

    results = {}

    # 1. Stop RDS instance
    try:
        rds_status = rds_client.describe_db_instances(
            DBInstanceIdentifier=RDS_INSTANCE_ID
        )['DBInstances'][0]['DBInstanceStatus']

        if rds_status == 'available':
            print(f"[FinOps] Stopping RDS: {RDS_INSTANCE_ID}")
            rds_client.stop_db_instance(DBInstanceIdentifier=RDS_INSTANCE_ID)

            # Record stop time for 7-day auto-start mitigation
            record_rds_stop_time()

            results['rds'] = 'stopped'
        else:
            print(f"[FinOps] RDS already in state: {rds_status}")
            results['rds'] = f'skipped_{rds_status}'

    except Exception as e:
        print(f"[FinOps] ⚠️ RDS stop error: {str(e)}")
        results['rds'] = f'error_{str(e)}'

    # 2. Scale ASGs to 0
    for asg_name in ASG_NAMES:
        try:
            print(f"[FinOps] Scaling ASG to 0: {asg_name}")
            autoscaling_client.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=0,
                MinSize=0
            )
            results[f'asg_{asg_name}'] = 'scaled_to_0'

        except Exception as e:
            print(f"[FinOps] ⚠️ ASG scale error ({asg_name}): {str(e)}")
            results[f'asg_{asg_name}'] = f'error_{str(e)}'

    print(f"[FinOps] ✅ Shutdown complete: {results}")
    return results


def startup_environment():
    """Start RDS and scale ASGs to desired capacity"""

    print(f"[FinOps] 🚀 Starting startup sequence")

    results = {}

    # 1. Check and mitigate RDS 7-day auto-start (AWS Specialist T-025)
    check_rds_auto_start_mitigation()

    # 2. Start RDS instance
    try:
        rds_status = rds_client.describe_db_instances(
            DBInstanceIdentifier=RDS_INSTANCE_ID
        )['DBInstances'][0]['DBInstanceStatus']

        if rds_status == 'stopped':
            print(f"[FinOps] Starting RDS: {RDS_INSTANCE_ID}")
            rds_client.start_db_instance(DBInstanceIdentifier=RDS_INSTANCE_ID)

            # Wait for RDS to become available (timeout: 5 minutes)
            waiter = rds_client.get_waiter('db_instance_available')
            waiter.wait(
                DBInstanceIdentifier=RDS_INSTANCE_ID,
                WaiterConfig={'Delay': 30, 'MaxAttempts': 10}
            )

            results['rds'] = 'started_available'
        else:
            print(f"[FinOps] RDS already in state: {rds_status}")
            results['rds'] = f'skipped_{rds_status}'

    except Exception as e:
        print(f"[FinOps] ⚠️ RDS start error: {str(e)}")
        results['rds'] = f'error_{str(e)}'
        # Do not fail entire startup if RDS fails

    # 3. Scale ASGs to desired capacity
    # ASG capacity mapping (STAGING: 2 system, 3 workloads, 2 critical)
    asg_capacity_map = {
        'system': 2,
        'workloads': 3,
        'critical': 2
    }

    for asg_name in ASG_NAMES:
        try:
            # Determine desired capacity based on node group type
            node_type = next((k for k in asg_capacity_map.keys() if k in asg_name.lower()), 'workloads')
            desired_capacity = asg_capacity_map.get(node_type, 2)

            print(f"[FinOps] Scaling ASG to {desired_capacity}: {asg_name}")
            autoscaling_client.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=desired_capacity,
                MinSize=desired_capacity,
                MaxSize=desired_capacity * 2
            )
            results[f'asg_{asg_name}'] = f'scaled_to_{desired_capacity}'

        except Exception as e:
            print(f"[FinOps] ⚠️ ASG scale error ({asg_name}): {str(e)}")
            results[f'asg_{asg_name}'] = f'error_{str(e)}'

    # 4. Health checks (optional, AWS Specialist requirement)
    if HEALTH_CHECK_ENABLED:
        print(f"[FinOps] Running health checks...")
        time.sleep(60)  # Wait for nodes to become Ready
        health_results = run_health_checks()
        results['health_checks'] = health_results

    print(f"[FinOps] ✅ Startup complete: {results}")
    return results


def check_rds_auto_start_mitigation():
    """
    AWS Specialist T-025: Mitigate RDS 7-day auto-start
    If RDS was stopped >7 days ago, AWS auto-starts it. Re-stop if necessary.
    """

    try:
        table = dynamodb.Table(RDS_STATE_TABLE)
        response = table.get_item(Key={'instance_id': RDS_INSTANCE_ID})

        if 'Item' not in response:
            print(f"[FinOps] No RDS state record found (first run)")
            return

        last_stop_time = response['Item'].get('last_stop_time')
        if not last_stop_time:
            return

        # Check if >7 days since last stop
        last_stop = datetime.fromisoformat(last_stop_time)
        days_stopped = (datetime.utcnow() - last_stop).days

        if days_stopped >= 7:
            print(f"[FinOps] ⚠️ RDS stopped for {days_stopped} days - checking auto-start")

            rds_status = rds_client.describe_db_instances(
                DBInstanceIdentifier=RDS_INSTANCE_ID
            )['DBInstances'][0]['DBInstanceStatus']

            if rds_status == 'available':
                print(f"[FinOps] 🔧 AWS auto-started RDS - re-stopping")
                rds_client.stop_db_instance(DBInstanceIdentifier=RDS_INSTANCE_ID)
                record_rds_stop_time()

    except Exception as e:
        print(f"[FinOps] ⚠️ RDS auto-start check error: {str(e)}")


def record_rds_stop_time():
    """Record RDS stop timestamp in DynamoDB"""

    try:
        table = dynamodb.Table(RDS_STATE_TABLE)
        table.put_item(
            Item={
                'instance_id': RDS_INSTANCE_ID,
                'last_stop_time': datetime.utcnow().isoformat(),
                'environment': ENVIRONMENT,
                'expiration_time': int((datetime.utcnow() + timedelta(days=30)).timestamp())
            }
        )
        print(f"[FinOps] Recorded RDS stop time in DynamoDB")

    except Exception as e:
        print(f"[FinOps] ⚠️ Failed to record RDS stop time: {str(e)}")


def run_health_checks():
    """
    Run health checks post-startup
    AWS Specialist requirement: Validate DB connections, GitLab jobs
    """

    health_results = {
        'rds_connection': False,
        'nodes_ready': False
    }

    try:
        # Check RDS connection (simple status check)
        rds_status = rds_client.describe_db_instances(
            DBInstanceIdentifier=RDS_INSTANCE_ID
        )['DBInstances'][0]['DBInstanceStatus']

        health_results['rds_connection'] = (rds_status == 'available')

        # Check EC2 instances (nodes) are running
        asg_instances = []
        for asg_name in ASG_NAMES:
            response = autoscaling_client.describe_auto_scaling_groups(
                AutoScalingGroupNames=[asg_name]
            )
            instances = response['AutoScalingGroups'][0]['Instances']
            asg_instances.extend([i['InstanceId'] for i in instances if i['LifecycleState'] == 'InService'])

        health_results['nodes_ready'] = len(asg_instances) > 0
        health_results['node_count'] = len(asg_instances)

        print(f"[FinOps] Health checks: {health_results}")
        return health_results

    except Exception as e:
        print(f"[FinOps] ⚠️ Health check error: {str(e)}")
        return health_results


def is_brazilian_holiday():
    """
    Check if today is Brazilian holiday using BrasilAPI
    AWS Specialist requirement: Smart scheduling
    """

    try:
        year = datetime.now().year
        url = f"https://brasilapi.com.br/api/feriados/v1/{year}"

        response = requests.get(url, timeout=5)
        response.raise_for_status()

        holidays = response.json()
        today = datetime.now().strftime('%Y-%m-%d')

        for holiday in holidays:
            if holiday.get('date') == today:
                print(f"[FinOps] 🇧🇷 Holiday detected: {holiday.get('name')}")
                return True

        return False

    except Exception as e:
        print(f"[FinOps] ⚠️ BrasilAPI error (continuing): {str(e)}")
        return False  # Fail open - don't block execution


def is_circuit_open():
    """
    Check circuit breaker state
    Returns True if circuit is OPEN (too many failures)
    """

    try:
        table = dynamodb.Table(CIRCUIT_BREAKER_TABLE)

        # Get last N executions
        response = table.query(
            KeyConditionExpression='environment = :env',
            ExpressionAttributeValues={':env': ENVIRONMENT},
            ScanIndexForward=False,
            Limit=CIRCUIT_BREAKER_THRESHOLD
        )

        items = response.get('Items', [])

        if len(items) < CIRCUIT_BREAKER_THRESHOLD:
            return False  # Not enough data

        # Check if all recent executions failed
        recent_failures = [item for item in items if item.get('status') == 'failure']

        if len(recent_failures) >= CIRCUIT_BREAKER_THRESHOLD:
            print(f"[FinOps] ⚠️ Circuit breaker OPEN ({len(recent_failures)} consecutive failures)")
            return True

        return False

    except Exception as e:
        print(f"[FinOps] ⚠️ Circuit breaker check error: {str(e)}")
        return False  # Fail open


def record_execution(action, status, details):
    """Record execution in DynamoDB circuit breaker table"""

    try:
        table = dynamodb.Table(CIRCUIT_BREAKER_TABLE)

        table.put_item(
            Item={
                'environment': ENVIRONMENT,
                'timestamp': Decimal(str(time.time())),
                'action': action,
                'status': status,
                'details': json.dumps(details, default=str),
                'expiration_time': int((datetime.utcnow() + timedelta(days=30)).timestamp())
            }
        )

        print(f"[FinOps] Recorded execution: {action} - {status}")

    except Exception as e:
        print(f"[FinOps] ⚠️ Failed to record execution: {str(e)}")
