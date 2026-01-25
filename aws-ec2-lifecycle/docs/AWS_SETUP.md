# AWS Setup Guide for EC2 Lifecycle Management

## Overview
This guide provides step-by-step instructions to configure AWS for EC2 instance lifecycle management with Harness.

---

## Step 1: Create IAM Policy

Create a custom IAM policy with minimum required permissions for EC2 lifecycle management.

### Policy Name: `HarnessEC2LifecyclePolicy`

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
            "Resource": "arn:aws:ec2:*:*:instance/*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/ManagedBy": "Harness"
                }
            }
        },
        {
            "Sid": "EC2LifecyclePermissionsUnrestricted",
            "Effect": "Allow",
            "Action": [
                "ec2:StartInstances",
                "ec2:StopInstances"
            ],
            "Resource": "arn:aws:ec2:*:*:instance/*"
        }
    ]
}
```

### How to Create (AWS Console):

1. Go to **IAM Console** → **Policies** → **Create Policy**
2. Select **JSON** tab
3. Paste the policy above
4. Name: `HarnessEC2LifecyclePolicy`
5. Description: `Policy for Harness to manage EC2 instance lifecycle (start/stop)`
6. Click **Create Policy**

### How to Create (AWS CLI):

```bash
aws iam create-policy \
    --policy-name HarnessEC2LifecyclePolicy \
    --policy-document file://iam-policy.json \
    --description "Policy for Harness to manage EC2 instance lifecycle"
```

---

## Step 2: Create IAM User

### User Name: `harness-ec2-manager`

### How to Create (AWS Console):

1. Go to **IAM Console** → **Users** → **Create User**
2. User name: `harness-ec2-manager`
3. Select **Access key - Programmatic access**
4. Click **Next: Permissions**
5. Select **Attach existing policies directly**
6. Search and select `HarnessEC2LifecyclePolicy`
7. Click **Next: Tags**
8. Add tags:
   - `Purpose`: `Harness-Integration`
   - `ManagedBy`: `Platform-Team`
9. Click **Create User**
10. **IMPORTANT**: Download or copy the Access Key ID and Secret Access Key

### How to Create (AWS CLI):

```bash
# Create user
aws iam create-user --user-name harness-ec2-manager

# Attach policy
aws iam attach-user-policy \
    --user-name harness-ec2-manager \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/HarnessEC2LifecyclePolicy

# Create access key
aws iam create-access-key --user-name harness-ec2-manager
```

---

## Step 3: Tag EC2 Instances (Optional but Recommended)

For better organization and filtering, tag your EC2 instances:

### Recommended Tags:

| Tag Key | Tag Value | Purpose |
|---------|-----------|---------|
| `ManagedBy` | `Harness` | Identifies instances managed by Harness |
| `Environment` | `dev/staging/prod` | Environment classification |
| `Project` | `<project-name>` | Project association |
| `CostCenter` | `<cost-center>` | Cost tracking |
| `AutoStop` | `true/false` | Eligible for auto-stop |

### Tagging via AWS CLI:

```bash
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=ManagedBy,Value=Harness Key=Environment,Value=dev
```

---

## Step 4: Security Best Practices

### 4.1 Enable CloudTrail Logging

```bash
aws cloudtrail create-trail \
    --name harness-ec2-audit-trail \
    --s3-bucket-name your-cloudtrail-bucket \
    --include-global-service-events
```

### 4.2 Set Up CloudWatch Alarms (Optional)

Monitor unusual EC2 start/stop activity:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "EC2-Lifecycle-High-Activity" \
    --metric-name "EC2-StartStop-Count" \
    --namespace "Harness/EC2Lifecycle" \
    --statistic Sum \
    --period 300 \
    --threshold 50 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1
```

### 4.3 Rotate Access Keys Regularly

Schedule key rotation every 90 days:

```bash
# Create new key
aws iam create-access-key --user-name harness-ec2-manager

# Update Harness secrets with new key

# Delete old key
aws iam delete-access-key \
    --user-name harness-ec2-manager \
    --access-key-id OLD_ACCESS_KEY_ID
```

---

## Step 5: Verify Setup

Run this verification script to ensure everything is configured correctly:

```bash
# Set credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"

# Test describe permissions
echo "Testing DescribeInstances..."
aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --output table

# Test describe instance status
echo "Testing DescribeInstanceStatus..."
aws ec2 describe-instance-status --query 'InstanceStatuses[].InstanceId' --output table

echo "✅ AWS setup verification complete!"
```

---

## Troubleshooting

### Error: "AccessDenied"
- Verify IAM policy is attached to user
- Check policy ARN matches your account ID
- Ensure instance tags match policy conditions

### Error: "InvalidInstanceID"
- Verify instance exists in the specified region
- Check instance ID format (i-xxxxxxxxxxxxxxxxx)

### Error: "IncorrectInstanceState"
- Instance may already be in target state
- Check current instance state before action

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS ACCOUNT                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                      IAM                                 │   │
│  │  ┌─────────────────┐    ┌─────────────────────────────┐ │   │
│  │  │  IAM User       │    │  IAM Policy                 │ │   │
│  │  │  harness-ec2-   │───▶│  HarnessEC2LifecyclePolicy  │ │   │
│  │  │  manager        │    │  - DescribeInstances        │ │   │
│  │  │                 │    │  - StartInstances           │ │   │
│  │  │  Access Key ────┼────┼──▶ StopInstances            │ │   │
│  │  │  Secret Key     │    │                             │ │   │
│  │  └─────────────────┘    └─────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                      EC2                                 │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐           │   │
│  │  │ Instance  │  │ Instance  │  │ Instance  │           │   │
│  │  │ (running) │  │ (stopped) │  │ (running) │           │   │
│  │  │ Tag:Prod  │  │ Tag:Dev   │  │ Tag:Stage │           │   │
│  │  └───────────┘  └───────────┘  └───────────┘           │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ API Calls
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      HARNESS PLATFORM                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  AWS Connector (using org secrets)                       │   │
│  │  └──▶ EC2 Lifecycle Pipeline                            │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```
