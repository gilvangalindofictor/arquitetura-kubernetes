#!/usr/bin/env python3
"""
AWS Orphan Resource Detector
Scans for orphaned resources (EBS volumes, Elastic IPs, Snapshots) and sends alerts.
"""

import boto3
import json
import os
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Any

# Thresholds
ORPHAN_AGE_DAYS = 7
REGION = os.environ.get('REGION', 'us-east-1')

def get_orphan_ebs_volumes() -> List[Dict[str, Any]]:
    """Find EBS volumes in 'available' state for >7 days."""
    ec2 = boto3.client('ec2', region_name=REGION)
    orphans = []

    try:
        response = ec2.describe_volumes(
            Filters=[{'Name': 'status', 'Values': ['available']}]
        )

        cutoff_date = datetime.now(timezone.utc) - timedelta(days=ORPHAN_AGE_DAYS)

        for volume in response['Volumes']:
            create_time = volume['CreateTime']
            age_days = (datetime.now(timezone.utc) - create_time).days

            if create_time < cutoff_date:
                size_gb = volume['Size']
                cost_monthly = size_gb * 0.08  # gp3 pricing
                cost_annual_brl = cost_monthly * 12 * 6.0  # BRL conversion

                orphans.append({
                    'ResourceType': 'EBS Volume',
                    'ResourceId': volume['VolumeId'],
                    'State': volume['State'],
                    'Size': f"{size_gb} GB",
                    'VolumeType': volume['VolumeType'],
                    'AgeDays': age_days,
                    'CreatedAt': create_time.isoformat(),
                    'CostMonthly': f"${cost_monthly:.2f}",
                    'CostAnnualBRL': f"R$ {cost_annual_brl:.2f}/ano"
                })
    except Exception as e:
        print(f"Error scanning EBS volumes: {e}")

    return orphans


def get_orphan_elastic_ips() -> List[Dict[str, Any]]:
    """Find Elastic IPs not associated with any instance."""
    ec2 = boto3.client('ec2', region_name=REGION)
    orphans = []

    try:
        response = ec2.describe_addresses()

        for address in response['Addresses']:
            # Elastic IP is orphan if not associated with instance or network interface
            if 'AssociationId' not in address and 'NetworkInterfaceId' not in address:
                # EIPs cost $0.005/hour when not associated = $3.65/month
                cost_monthly = 3.65
                cost_annual_brl = cost_monthly * 12 * 6.0

                orphans.append({
                    'ResourceType': 'Elastic IP',
                    'ResourceId': address['PublicIp'],
                    'AllocationId': address.get('AllocationId', 'N/A'),
                    'State': 'Not Associated',
                    'CostMonthly': f"${cost_monthly:.2f}",
                    'CostAnnualBRL': f"R$ {cost_annual_brl:.2f}/ano"
                })
    except Exception as e:
        print(f"Error scanning Elastic IPs: {e}")

    return orphans


def get_orphan_snapshots() -> List[Dict[str, Any]]:
    """Find EBS snapshots not associated with any AMI (older than 30 days)."""
    ec2 = boto3.client('ec2', region_name=REGION)
    orphans = []

    try:
        # Get all snapshots owned by this account
        response = ec2.describe_snapshots(OwnerIds=['self'])

        # Get all AMIs to check which snapshots are in use
        amis = ec2.describe_images(Owners=['self'])
        ami_snapshot_ids = set()
        for ami in amis['Images']:
            for bdm in ami.get('BlockDeviceMappings', []):
                if 'Ebs' in bdm and 'SnapshotId' in bdm['Ebs']:
                    ami_snapshot_ids.add(bdm['Ebs']['SnapshotId'])

        cutoff_date = datetime.now(timezone.utc) - timedelta(days=30)  # Snapshots: 30 days threshold

        for snapshot in response['Snapshots']:
            snapshot_id = snapshot['SnapshotId']
            start_time = snapshot['StartTime']

            # Check if orphan (not used by any AMI and older than 30 days)
            if snapshot_id not in ami_snapshot_ids and start_time < cutoff_date:
                age_days = (datetime.now(timezone.utc) - start_time).days
                size_gb = snapshot['VolumeSize']
                cost_monthly = size_gb * 0.05  # Snapshot pricing $0.05/GB/month
                cost_annual_brl = cost_monthly * 12 * 6.0

                orphans.append({
                    'ResourceType': 'EBS Snapshot',
                    'ResourceId': snapshot_id,
                    'Description': snapshot.get('Description', 'N/A')[:50],
                    'Size': f"{size_gb} GB",
                    'AgeDays': age_days,
                    'CreatedAt': start_time.isoformat(),
                    'CostMonthly': f"${cost_monthly:.2f}",
                    'CostAnnualBRL': f"R$ {cost_annual_brl:.2f}/ano"
                })
    except Exception as e:
        print(f"Error scanning snapshots: {e}")

    return orphans


def format_alert_message(orphans_by_type: Dict[str, List[Dict[str, Any]]]) -> str:
    """Format orphan resources into human-readable alert message."""
    total_orphans = sum(len(orphans) for orphans in orphans_by_type.values())

    if total_orphans == 0:
        return "✅ AWS Orphan Resource Scan - No orphans detected\n\nAll resources are in use. No action required."

    # Calculate total cost
    total_cost_brl = 0.0
    for orphans in orphans_by_type.values():
        for orphan in orphans:
            cost_str = orphan.get('CostAnnualBRL', 'R$ 0.00/ano')
            cost_value = float(cost_str.replace('R$ ', '').replace('/ano', '').replace(',', ''))
            total_cost_brl += cost_value

    message = f"⚠️ AWS Orphan Resource Alert - {total_orphans} resources detected\n\n"
    message += f"💰 Estimated waste: R$ {total_cost_brl:.2f}/ano\n\n"
    message += "="*70 + "\n\n"

    for resource_type, orphans in orphans_by_type.items():
        if orphans:
            message += f"## {resource_type} ({len(orphans)} found)\n\n"

            for i, orphan in enumerate(orphans, 1):
                message += f"{i}. {orphan['ResourceId']}\n"
                for key, value in orphan.items():
                    if key not in ['ResourceType', 'ResourceId']:
                        message += f"   - {key}: {value}\n"
                message += "\n"

            message += "-"*70 + "\n\n"

    message += "\n🔧 Recommended Actions:\n"
    message += "1. Review resources listed above\n"
    message += "2. Delete confirmed orphans via AWS Console or CLI\n"
    message += "3. Update Terraform if resources should be managed\n\n"
    message += "📊 FinOps Dashboard: Check Grafana for cost trends\n"
    message += "📚 Runbook: docs/operations/finops-orphan-cleanup.md\n"

    return message


def send_sns_alert(message: str, topic_arn: str):
    """Send alert to SNS topic."""
    sns = boto3.client('sns', region_name=REGION)

    try:
        response = sns.publish(
            TopicArn=topic_arn,
            Subject='AWS Orphan Resource Alert',
            Message=message
        )
        print(f"SNS alert sent: MessageId={response['MessageId']}")
    except Exception as e:
        print(f"Error sending SNS alert: {e}")
        raise


def lambda_handler(event, context):
    """Lambda entry point - scan for orphan resources and alert."""
    print("Starting orphan resource scan...")

    # Scan for orphans
    orphans_by_type = {
        'EBS Volumes': get_orphan_ebs_volumes(),
        'Elastic IPs': get_orphan_elastic_ips(),
        'EBS Snapshots': get_orphan_snapshots()
    }

    # Summary
    total_orphans = sum(len(orphans) for orphans in orphans_by_type.values())
    print(f"Scan complete: {total_orphans} orphan resources found")
    for resource_type, orphans in orphans_by_type.items():
        print(f"  - {resource_type}: {len(orphans)}")

    # Format and send alert
    message = format_alert_message(orphans_by_type)

    # Get SNS topic ARN from environment variable
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not topic_arn:
        # Fallback: construct from account ID
        account_id = context.invoked_function_arn.split(':')[4]
        topic_arn = f"arn:aws:sns:{REGION}:{account_id}:orphan-detector-alerts"
        print(f"WARNING: SNS_TOPIC_ARN not found in environment, using fallback: {topic_arn}")

    send_sns_alert(message, topic_arn)

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Orphan scan complete',
            'total_orphans': total_orphans,
            'details': orphans_by_type
        })
    }


# For local testing
if __name__ == '__main__':
    class MockContext:
        invoked_function_arn = 'arn:aws:lambda:us-east-1:891377105802:function:test'

    result = lambda_handler({}, MockContext())
    print(json.dumps(result, indent=2))
