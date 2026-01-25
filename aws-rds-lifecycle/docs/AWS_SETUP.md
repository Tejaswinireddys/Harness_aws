# AWS Setup Guide for RDS Lifecycle Management

## Overview
Complete guide to configure AWS for RDS instance lifecycle management with Harness.

---

## Step 1: Create IAM Policy

### Policy Name: `HarnessRDSLifecyclePolicy`

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "RDSDescribePermissions",
            "Effect": "Allow",
            "Action": [
                "rds:DescribeDBInstances",
                "rds:DescribeDBClusters",
                "rds:DescribeDBSnapshots",
                "rds:DescribeDBClusterSnapshots",
                "rds:DescribeDBEngineVersions",
                "rds:DescribeDBParameterGroups",
                "rds:DescribeDBSubnetGroups",
                "rds:DescribeOptionGroups",
                "rds:ListTagsForResource"
            ],
            "Resource": "*"
        },
        {
            "Sid": "RDSInstanceLifecycle",
            "Effect": "Allow",
            "Action": [
                "rds:StartDBInstance",
                "rds:StopDBInstance",
                "rds:RebootDBInstance"
            ],
            "Resource": "arn:aws:rds:*:*:db:*"
        },
        {
            "Sid": "RDSClusterLifecycle",
            "Effect": "Allow",
            "Action": [
                "rds:StartDBCluster",
                "rds:StopDBCluster"
            ],
            "Resource": "arn:aws:rds:*:*:cluster:*"
        },
        {
            "Sid": "RDSSnapshotPermissions",
            "Effect": "Allow",
            "Action": [
                "rds:CreateDBSnapshot",
                "rds:CreateDBClusterSnapshot"
            ],
            "Resource": [
                "arn:aws:rds:*:*:db:*",
                "arn:aws:rds:*:*:cluster:*",
                "arn:aws:rds:*:*:snapshot:*",
                "arn:aws:rds:*:*:cluster-snapshot:*"
            ]
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

### Create Policy (Console):
1. Go to **IAM Console** → **Policies** → **Create Policy**
2. Select **JSON** tab
3. Paste the policy above
4. Name: `HarnessRDSLifecyclePolicy`
5. Description: `Policy for Harness to manage RDS instance lifecycle`
6. Click **Create Policy**

### Create Policy (CLI):
```bash
aws iam create-policy \
    --policy-name HarnessRDSLifecyclePolicy \
    --policy-document file://templates/iam-policy.json \
    --description "Policy for Harness to manage RDS instance lifecycle"
```

---

## Step 2: Create IAM User

### User Name: `harness-rds-manager`

### Create User (Console):
1. Go to **IAM Console** → **Users** → **Create User**
2. User name: `harness-rds-manager`
3. Select **Access key - Programmatic access**
4. Attach `HarnessRDSLifecyclePolicy`
5. Add tags:
   - `Purpose`: `Harness-Integration`
   - `ManagedBy`: `Platform-Team`
6. Create and download credentials

### Create User (CLI):
```bash
# Create user
aws iam create-user --user-name harness-rds-manager

# Attach policy
aws iam attach-user-policy \
    --user-name harness-rds-manager \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/HarnessRDSLifecyclePolicy

# Create access key
aws iam create-access-key --user-name harness-rds-manager
```

---

## Step 3: Tag RDS Instances (Recommended)

### Recommended Tags:

| Tag Key | Example Values | Purpose |
|---------|----------------|---------|
| `Name` | `myapp-db-prod` | Instance identification |
| `Environment` | `dev/staging/prod` | Environment filtering |
| `ManagedBy` | `Harness` | Identify managed instances |
| `Project` | `project-name` | Project association |
| `AutoStop` | `true/false` | Eligible for auto-stop |
| `CostCenter` | `engineering` | Cost tracking |

### Tag via CLI:
```bash
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-east-1:123456789:db:mydb \
    --tags Key=Environment,Value=dev Key=ManagedBy,Value=Harness
```

---

## Step 4: Verify Setup

```bash
# Set credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"

# Verify identity
echo "Testing STS..."
aws sts get-caller-identity

# Verify RDS describe permission
echo "Testing DescribeDBInstances..."
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output table

# Verify cluster describe permission
echo "Testing DescribeDBClusters..."
aws rds describe-db-clusters --query 'DBClusters[].DBClusterIdentifier' --output table

echo "✅ AWS setup verified!"
```

---

## Step 5: Optional - Read-Only Policy

For users who only need to list instances:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "RDSReadOnly",
            "Effect": "Allow",
            "Action": [
                "rds:DescribeDBInstances",
                "rds:DescribeDBClusters",
                "rds:DescribeDBSnapshots",
                "rds:ListTagsForResource"
            ],
            "Resource": "*"
        }
    ]
}
```

---

## Step 6: Environment-Specific Restrictions (Optional)

Restrict stop actions to non-production:

```json
{
    "Sid": "RestrictProductionStop",
    "Effect": "Deny",
    "Action": [
        "rds:StopDBInstance",
        "rds:StopDBCluster"
    ],
    "Resource": "*",
    "Condition": {
        "StringEquals": {
            "aws:ResourceTag/Environment": "production"
        }
    }
}
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS ACCOUNT                             │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                          IAM                              │ │
│  │                                                           │ │
│  │  ┌─────────────────────┐    ┌───────────────────────────┐│ │
│  │  │   IAM User          │    │  IAM Policy               ││ │
│  │  │   harness-rds-      │───▶│  HarnessRDSLifecycle     ││ │
│  │  │   manager           │    │  Policy                   ││ │
│  │  │                     │    │                           ││ │
│  │  │  Access Key ────────┼────┼──▶ Permissions:           ││ │
│  │  │  Secret Key         │    │    - DescribeDBInstances  ││ │
│  │  │                     │    │    - StartDBInstance      ││ │
│  │  │                     │    │    - StopDBInstance       ││ │
│  │  │                     │    │    - CreateDBSnapshot     ││ │
│  │  └─────────────────────┘    └───────────────────────────┘│ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                          RDS                              │ │
│  │                                                           │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │ │
│  │  │ PostgreSQL  │  │   MySQL     │  │   Aurora    │       │ │
│  │  │ (available) │  │  (stopped)  │  │  Cluster    │       │ │
│  │  │ db.t3.med   │  │  db.t3.sm   │  │ (available) │       │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘       │ │
│  │                                                           │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │ │
│  │  │ SQL Server  │  │  MariaDB    │  │   Oracle    │       │ │
│  │  │ (available) │  │  (stopped)  │  │ (available) │       │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘       │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ API Calls
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      HARNESS PLATFORM                           │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  AWS Connector → RDS Lifecycle Pipeline                   │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `AccessDenied` | Missing permissions | Check IAM policy attachment |
| `DBInstanceNotFound` | Wrong identifier | Verify DB instance name |
| `InvalidDBInstanceState` | Wrong state for action | Check current state first |
| `InvalidParameterCombination` | Read replica stop | Cannot stop read replicas directly |
| `SnapshotQuotaExceeded` | Too many snapshots | Delete old snapshots |
