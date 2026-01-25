# AWS EC2 Instance Lifecycle Management with Harness

A comprehensive, enterprise-grade solution for managing AWS EC2 instance lifecycle (Start, Stop, List) using Harness CI/CD platform.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Features](#features)
3. [Prerequisites](#prerequisites)
4. [Quick Start Guide](#quick-start-guide)
5. [AWS Setup (Detailed)](#aws-setup-detailed)
6. [Harness Setup (Detailed)](#harness-setup-detailed)
7. [Pipeline Usage](#pipeline-usage)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                          EC2 LIFECYCLE MANAGEMENT ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│   ┌─────────────┐      ┌─────────────────────────────────────────────────────────────┐ │
│   │   USER      │      │                    HARNESS PLATFORM                          │ │
│   │   INPUT     │─────▶│                                                              │ │
│   │  - Action   │      │  ┌─────────────────────────────────────────────────────────┐│ │
│   │  - Region   │      │  │              EC2 LIFECYCLE PIPELINE                      ││ │
│   │  - IDs      │      │  │                                                          ││ │
│   └─────────────┘      │  │  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐  ││ │
│                        │  │  │   1️⃣   │──▶│   2️⃣   │──▶│   3️⃣   │──▶│   4️⃣   │  ││ │
│                        │  │  │  INIT   │   │VALIDATE │   │DISCOVER │   │ ACTION  │  ││ │
│                        │  │  └─────────┘   └─────────┘   └─────────┘   └─────────┘  ││ │
│                        │  │                                                │         ││ │
│                        │  │                                          ┌─────▼───────┐││ │
│                        │  │                                          │     5️⃣     │││ │
│                        │  │                                          │   VERIFY    │││ │
│                        │  │                                          └─────────────┘││ │
│                        │  │                                                │         ││ │
│                        │  │  ORG SECRETS:                            ┌─────▼───────┐││ │
│                        │  │  ├── aws_access_key_id                   │     6️⃣     │││ │
│                        │  │  └── aws_secret_access_key               │  SUMMARY    │││ │
│                        │  │                                          └─────────────┘││ │
│                        │  └─────────────────────────────────────────────────────────┘│ │
│                        └─────────────────────────────────────────────────────────────┘ │
│                                              │                                          │
│                                              │ AWS API Calls                            │
│                                              ▼                                          │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐  │
│   │                               AWS ACCOUNT                                        │  │
│   │  ┌─────────────────────────────────────────────────────────────────────────┐    │  │
│   │  │  IAM User: harness-ec2-manager                                          │    │  │
│   │  │  Policy: HarnessEC2LifecyclePolicy                                      │    │  │
│   │  │  Permissions: DescribeInstances, StartInstances, StopInstances          │    │  │
│   │  └─────────────────────────────────────────────────────────────────────────┘    │  │
│   │                                         │                                        │  │
│   │  ┌──────────────────────────────────────┴────────────────────────────────────┐  │  │
│   │  │                              EC2 INSTANCES                                 │  │  │
│   │  │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │  │  │
│   │  │   │ Running │  │ Stopped │  │ Running │  │ Stopped │  │ Running │        │  │  │
│   │  │   │ (prod)  │  │  (dev)  │  │(staging)│  │ (test)  │  │  (dev)  │        │  │  │
│   │  │   └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘        │  │  │
│   │  └───────────────────────────────────────────────────────────────────────────┘  │  │
│   └─────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Features

| Feature | Description |
|---------|-------------|
| **List All Instances** | View all EC2 instances with their current state |
| **List Running** | Filter and display only running instances |
| **List Stopped** | Filter and display only stopped instances |
| **Start Instances** | Start one or more stopped instances |
| **Stop Instances** | Stop one or more running instances |
| **Dry Run Mode** | Simulate actions without making changes |
| **State Verification** | Verify instances reach target state |
| **Environment Filtering** | Filter by Environment tag |
| **Multi-Region Support** | Works across AWS regions |
| **Notifications** | Slack/Email notifications on completion |
| **RBAC** | Role-based access control |
| **Audit Trail** | Complete execution history |

---

## Prerequisites

### AWS Requirements
- [ ] AWS Account with EC2 instances
- [ ] IAM User with programmatic access
- [ ] EC2 permissions (describe, start, stop)

### Harness Requirements
- [ ] Harness account with CD module enabled
- [ ] Project with appropriate permissions
- [ ] AWS CLI available in pipeline execution environment

---

## Quick Start Guide

### Step 1: AWS Setup (5 minutes)

```bash
# 1. Create IAM Policy
aws iam create-policy \
    --policy-name HarnessEC2LifecyclePolicy \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ec2:DescribeInstances",
                    "ec2:DescribeInstanceStatus",
                    "ec2:StartInstances",
                    "ec2:StopInstances"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": "sts:GetCallerIdentity",
                "Resource": "*"
            }
        ]
    }'

# 2. Create IAM User
aws iam create-user --user-name harness-ec2-manager

# 3. Attach Policy
aws iam attach-user-policy \
    --user-name harness-ec2-manager \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/HarnessEC2LifecyclePolicy

# 4. Create Access Key (SAVE THE OUTPUT!)
aws iam create-access-key --user-name harness-ec2-manager
```

### Step 2: Harness Setup (10 minutes)

1. **Create Organization Secrets:**
   - Go to: Organization → Settings → Secrets
   - Create `aws_access_key_id` (Text secret)
   - Create `aws_secret_access_key` (Text secret)

2. **Import Pipeline:**
   - Go to: Project → Pipelines → + Create Pipeline
   - Select YAML editor
   - Copy content from `pipelines/ec2-lifecycle-management.yaml`
   - Update `orgIdentifier` and `projectIdentifier`
   - Save

3. **Test Execution:**
   - Run pipeline with action: `list_all`
   - Verify instances are displayed

---

## AWS Setup (Detailed)

### IAM Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EC2DescribePermissions",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeTags",
                "ec2:DescribeRegions"
            ],
            "Resource": "*"
        },
        {
            "Sid": "EC2LifecyclePermissions",
            "Effect": "Allow",
            "Action": [
                "ec2:StartInstances",
                "ec2:StopInstances"
            ],
            "Resource": "arn:aws:ec2:*:*:instance/*"
        },
        {
            "Sid": "STSPermissions",
            "Effect": "Allow",
            "Action": "sts:GetCallerIdentity",
            "Resource": "*"
        }
    ]
}
```

### Recommended Instance Tagging

| Tag Key | Example Values | Purpose |
|---------|----------------|---------|
| `Name` | `web-server-1` | Instance identification |
| `Environment` | `dev`, `staging`, `prod` | Environment filtering |
| `ManagedBy` | `Harness` | Identify managed instances |
| `Project` | `project-name` | Project association |
| `CostCenter` | `engineering` | Cost tracking |

---

## Harness Setup (Detailed)

### 1. Create Organization Secrets

Navigate to: **Organization Settings → Secrets**

| Secret Name | Identifier | Description |
|-------------|------------|-------------|
| `aws_access_key_id` | `aws_access_key_id` | AWS Access Key ID |
| `aws_secret_access_key` | `aws_secret_access_key` | AWS Secret Access Key |

**Reference in Pipeline:**
```yaml
AWS_ACCESS_KEY_ID: <+secrets.getValue("org.aws_access_key_id")>
AWS_SECRET_ACCESS_KEY: <+secrets.getValue("org.aws_secret_access_key")>
```

### 2. Pipeline Structure

The main pipeline consists of 6 stages:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PIPELINE STAGE FLOW                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌───────────────┐                                                      │
│  │ 1️⃣ INITIALIZE │  Display configuration and validate inputs          │
│  └───────┬───────┘                                                      │
│          │                                                               │
│          ▼                                                               │
│  ┌───────────────┐                                                      │
│  │ 2️⃣ VALIDATE   │  Validate AWS credentials and permissions           │
│  └───────┬───────┘                                                      │
│          │                                                               │
│          ▼                                                               │
│  ┌───────────────┐                                                      │
│  │ 3️⃣ DISCOVER   │  List EC2 instances based on filters                │
│  └───────┬───────┘                                                      │
│          │                                                               │
│          ▼                                                               │
│  ┌───────────────┐                                                      │
│  │ 4️⃣ EXECUTE    │  Start/Stop instances (conditional)                 │
│  └───────┬───────┘                                                      │
│          │                                                               │
│          ▼                                                               │
│  ┌───────────────┐                                                      │
│  │ 5️⃣ VERIFY     │  Verify target state achieved (conditional)         │
│  └───────┬───────┘                                                      │
│          │                                                               │
│          ▼                                                               │
│  ┌───────────────┐                                                      │
│  │ 6️⃣ SUMMARY    │  Generate report and send notifications             │
│  └───────────────┘                                                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3. Pipeline Variables

| Variable | Type | Required | Options | Description |
|----------|------|----------|---------|-------------|
| `action` | String | Yes | `list_all`, `list_running`, `list_stopped`, `start`, `stop` | Action to perform |
| `aws_region` | String | Yes | Multiple AWS regions | Target AWS region |
| `instance_ids` | String | No (Required for start/stop) | Comma-separated | Instance IDs to act on |
| `environment_filter` | String | No | `dev`, `staging`, `production` | Filter by Environment tag |
| `dry_run` | Boolean | No | `true`, `false` | Simulate without changes |
| `wait_for_state` | Boolean | No | `true`, `false` | Wait for target state |
| `notify_on_completion` | Boolean | No | `true`, `false` | Send notifications |

---

## Pipeline Usage

### List All Instances

```
Action: list_all
Region: us-east-1
```

**Output:**
```
┌────────────────────┬─────────────┬───────────────┬──────────────────┐
│ Instance ID        │ State       │ Type          │ Private IP       │
├────────────────────┼─────────────┼───────────────┼──────────────────┤
│ i-0abc123def456789 │ running     │ t3.medium     │ 10.0.1.100       │
│ i-0def456abc789012 │ stopped     │ t3.small      │ 10.0.1.101       │
│ i-0ghi789def012345 │ running     │ t3.large      │ 10.0.2.50        │
└────────────────────┴─────────────┴───────────────┴──────────────────┘

Summary: 3 total | 2 running | 1 stopped
```

### Start Instances

```
Action: start
Region: us-east-1
Instance IDs: i-0abc123def456789,i-0def456abc789012
Dry Run: false
Wait for State: true
```

### Stop Instances

```
Action: stop
Region: us-east-1
Instance IDs: i-0abc123def456789
Dry Run: true  # Test first!
```

---

## Troubleshooting

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `AccessDenied` | Missing IAM permissions | Verify policy attached to IAM user |
| `InvalidInstanceID` | Instance doesn't exist | Check instance ID and region |
| `IncorrectInstanceState` | Instance already in target state | No action needed |
| `UnauthorizedOperation` | Insufficient permissions | Check IAM policy |

### Validation Commands

```bash
# Test AWS credentials
aws sts get-caller-identity

# Test EC2 describe permission
aws ec2 describe-instances --region us-east-1 --max-results 1

# Test start permission (dry run)
aws ec2 start-instances --instance-ids i-xxx --dry-run

# Test stop permission (dry run)
aws ec2 stop-instances --instance-ids i-xxx --dry-run
```

---

## Best Practices

### Security
- [ ] Rotate AWS access keys every 90 days
- [ ] Use least-privilege IAM policy
- [ ] Enable CloudTrail for audit logging
- [ ] Use environment filtering for production protection

### Operations
- [ ] Always use dry run mode first for destructive actions
- [ ] Set up notifications for pipeline failures
- [ ] Tag instances consistently for filtering
- [ ] Review execution logs regularly

### Governance
- [ ] Implement OPA policies for production protection
- [ ] Define RBAC roles for different user groups
- [ ] Set up approval gates for production actions

---

## File Structure

```
aws-ec2-lifecycle/
├── README.md                           # This file
├── docs/
│   ├── AWS_SETUP.md                   # Detailed AWS setup guide
│   └── HARNESS_SETUP.md               # Detailed Harness setup guide
├── pipelines/
│   ├── ec2-lifecycle-management.yaml  # Main pipeline
│   └── ec2-list-instances.yaml        # Simple list pipeline
├── scripts/
│   ├── validate_credentials.sh        # Credential validation
│   ├── discover_instances.sh          # Instance discovery
│   ├── execute_action.sh              # Start/Stop execution
│   └── verify_state.sh                # State verification
└── templates/
    └── (stage templates for reuse)
```

---

## Support

For issues or feature requests, contact the Platform Team.

---

**Version:** 1.0.0
**Last Updated:** 2025-01-24
**Author:** Platform Team
