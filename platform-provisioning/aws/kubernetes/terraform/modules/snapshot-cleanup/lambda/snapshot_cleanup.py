"""
Snapshot Cleanup Lambda
Deletes EBS snapshots older than RETENTION_DAYS that match cleanup criteria:
  - Description contains 'migration', 'temp', 'gp2', or 'test'
  - Created by this account (OwnerIds=['self'])
  - No active AMI dependency

Schedule: Weekly (Monday 03:00 UTC)
Savings: ~R$ 216/ano (prevent migration snapshot accumulation)
"""

import boto3
import json
import os
from datetime import datetime, timedelta, timezone

REGION = os.environ.get("REGION", "us-east-1")
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "30"))
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")

ec2 = boto3.client("ec2", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)


def is_cleanup_candidate(snap: dict) -> bool:
    """Return True if snapshot matches cleanup criteria."""
    description = snap.get("Description", "").lower()
    tags = {t["Key"]: t["Value"] for t in snap.get("Tags", [])}

    # Keywords indicating temporary/migration snapshots
    cleanup_keywords = ["migration", "migrat", "gp2-to-gp3", "gp3-migration",
                        "temp", "test", "created by createvolume"]

    # Skip snapshots explicitly tagged to keep
    if tags.get("Lifecycle") in ("protected", "keep", "permanent"):
        return False
    if tags.get("FinOps:Keep") == "true":
        return False

    return any(kw in description for kw in cleanup_keywords)


def get_ami_snapshot_ids() -> set:
    """Return set of snapshot IDs currently used by registered AMIs."""
    ami_snap_ids = set()
    paginator = ec2.get_paginator("describe_images")
    for page in paginator.paginate(Owners=["self"]):
        for image in page["Images"]:
            for mapping in image.get("BlockDeviceMappings", []):
                ebs = mapping.get("Ebs", {})
                snap_id = ebs.get("SnapshotId")
                if snap_id:
                    ami_snap_ids.add(snap_id)
    return ami_snap_ids


def lambda_handler(event, context):
    cutoff = datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)
    ami_snap_ids = get_ami_snapshot_ids()

    # List all self-owned snapshots
    paginator = ec2.get_paginator("describe_snapshots")
    all_snaps = []
    for page in paginator.paginate(OwnerIds=["self"]):
        all_snaps.extend(page["Snapshots"])

    candidates = []
    skipped_ami = []
    skipped_recent = []
    skipped_protected = []

    for snap in all_snaps:
        snap_id = snap["SnapshotId"]
        age_days = (datetime.now(timezone.utc) - snap["StartTime"]).days

        if snap_id in ami_snap_ids:
            skipped_ami.append(snap_id)
            continue

        if snap["StartTime"] >= cutoff:
            skipped_recent.append(snap_id)
            continue

        if not is_cleanup_candidate(snap):
            skipped_protected.append(snap_id)
            continue

        candidates.append({
            "id": snap_id,
            "description": snap.get("Description", ""),
            "age_days": age_days,
            "size_gb": snap.get("VolumeSize", 0),
        })

    deleted = []
    errors = []

    for snap in candidates:
        print(f"{'[DRY-RUN] ' if DRY_RUN else ''}Deleting {snap['id']}: "
              f"{snap['description'][:60]} (age={snap['age_days']}d, size={snap['size_gb']}GB)")
        if not DRY_RUN:
            try:
                ec2.delete_snapshot(SnapshotId=snap["id"])
                deleted.append(snap)
            except Exception as e:
                print(f"ERROR deleting {snap['id']}: {e}")
                errors.append({"id": snap["id"], "error": str(e)})
        else:
            deleted.append(snap)  # dry-run: count as deleted for reporting

    total_gb = sum(s["size_gb"] for s in deleted)
    savings_monthly_usd = total_gb * 0.05  # $0.05/GB/month for snapshots

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "dry_run": DRY_RUN,
        "retention_days": RETENTION_DAYS,
        "total_snapshots_scanned": len(all_snaps),
        "candidates_found": len(candidates),
        "deleted_count": len(deleted) if not DRY_RUN else 0,
        "dry_run_would_delete": len(deleted) if DRY_RUN else 0,
        "total_gb_freed": total_gb,
        "savings_monthly_usd": round(savings_monthly_usd, 2),
        "skipped_ami_dependency": len(skipped_ami),
        "skipped_recent": len(skipped_recent),
        "skipped_protected": len(skipped_protected),
        "errors": errors,
        "deleted_snapshots": deleted,
    }

    print(json.dumps(report, indent=2))

    # Send SNS notification if topic configured and action taken
    if SNS_TOPIC_ARN and (deleted or errors):
        action = "DRY-RUN Would Delete" if DRY_RUN else "Deleted"
        subject = f"[FinOps] Snapshot Cleanup: {action} {len(deleted)} snapshots ({total_gb}GB)"
        message = (
            f"Snapshot Cleanup Report — {datetime.now(timezone.utc).strftime('%Y-%m-%d')}\n\n"
            f"Mode: {'DRY-RUN' if DRY_RUN else 'LIVE'}\n"
            f"Retention: {RETENTION_DAYS} days\n"
            f"Snapshots scanned: {len(all_snaps)}\n"
            f"Candidates: {len(candidates)}\n"
            f"{'Would delete' if DRY_RUN else 'Deleted'}: {len(deleted)} snapshots ({total_gb} GB)\n"
            f"Estimated savings: ${savings_monthly_usd:.2f}/month\n"
            f"Errors: {len(errors)}\n\n"
        )
        if deleted:
            message += "Snapshots processed:\n"
            for s in deleted[:20]:
                message += f"  - {s['id']}: {s['description'][:50]} ({s['age_days']}d, {s['size_gb']}GB)\n"
            if len(deleted) > 20:
                message += f"  ... and {len(deleted) - 20} more\n"
        if errors:
            message += f"\nErrors:\n"
            for e in errors:
                message += f"  - {e['id']}: {e['error']}\n"

        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message)

    return {"statusCode": 200, "body": json.dumps(report)}
