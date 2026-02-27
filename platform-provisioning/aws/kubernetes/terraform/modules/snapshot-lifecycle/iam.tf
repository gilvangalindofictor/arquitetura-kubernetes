# IAM Role and Policies for Data Lifecycle Manager (DLM)
# Least-privilege permissions for snapshot lifecycle management

#------------------------------------------------------------------------------
# IAM Role — DLM Service
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "dlm_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "dlm" {
  name               = "${var.policy_name_prefix}-dlm-lifecycle-role"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume_role.json
  description        = "IAM role for Data Lifecycle Manager snapshot policies"

  tags = merge(var.common_tags, {
    Name    = "${var.policy_name_prefix}-dlm-lifecycle-role"
    Purpose = "DLM snapshot lifecycle management"
  })
}

#------------------------------------------------------------------------------
# IAM Policy — DLM Permissions (Least Privilege)
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "dlm_permissions" {
  # EC2 Snapshot Management
  statement {
    sid    = "SnapshotLifecycleManagement"
    effect = "Allow"

    actions = [
      "ec2:CreateSnapshot",
      "ec2:CreateSnapshots",
      "ec2:DeleteSnapshot",
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:DescribeInstances",
    ]

    resources = ["*"]
  }

  # Snapshot Tagging
  statement {
    sid    = "SnapshotTagging"
    effect = "Allow"

    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]

    resources = [
      "arn:aws:ec2:*::snapshot/*",
      "arn:aws:ec2:*::volume/*",
    ]
  }

  # CloudWatch Events for scheduling (if needed by DLM)
  statement {
    sid    = "CloudWatchEventsAccess"
    effect = "Allow"

    actions = [
      "events:PutRule",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:EnableRule",
      "events:DisableRule",
      "events:PutTargets",
      "events:RemoveTargets",
    ]

    resources = ["arn:aws:events:*:*:rule/AwsDataLifecycleRule.managed-cw-rule.*"]
  }
}

resource "aws_iam_policy" "dlm" {
  name        = "${var.policy_name_prefix}-dlm-lifecycle-policy"
  description = "Least-privilege permissions for DLM snapshot lifecycle management"
  policy      = data.aws_iam_policy_document.dlm_permissions.json

  tags = merge(var.common_tags, {
    Name    = "${var.policy_name_prefix}-dlm-lifecycle-policy"
    Purpose = "DLM snapshot operations"
  })
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = aws_iam_policy.dlm.arn
}
