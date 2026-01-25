# AWS Setup Guide for ECS Lifecycle Management

## Overview
Complete guide to configure AWS for ECS cluster and service lifecycle management with Harness.

---

## Step 1: Create IAM Policy

### Policy Name: `HarnessECSLifecyclePolicy`

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ECSDescribePermissions",
            "Effect": "Allow",
            "Action": [
                "ecs:ListClusters",
                "ecs:DescribeClusters",
                "ecs:ListServices",
                "ecs:DescribeServices",
                "ecs:ListTasks",
                "ecs:DescribeTasks",
                "ecs:ListTaskDefinitions",
                "ecs:DescribeTaskDefinition",
                "ecs:ListContainerInstances",
                "ecs:DescribeContainerInstances"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECSServiceManagement",
            "Effect": "Allow",
            "Action": [
                "ecs:UpdateService"
            ],
            "Resource": "arn:aws:ecs:*:*:service/*/*"
        },
        {
            "Sid": "ECSTaskManagement",
            "Effect": "Allow",
            "Action": [
                "ecs:StopTask"
            ],
            "Resource": "arn:aws:ecs:*:*:task/*/*"
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
4. Name: `HarnessECSLifecyclePolicy`
5. Description: `Policy for Harness to manage ECS lifecycle`
6. Click **Create Policy**

### Create Policy (CLI):
```bash
aws iam create-policy \
    --policy-name HarnessECSLifecyclePolicy \
    --policy-document file://templates/iam-policy.json \
    --description "Policy for Harness to manage ECS cluster lifecycle"
```

---

## Step 2: Create IAM User

### User Name: `harness-ecs-manager`

```bash
# Create user
aws iam create-user --user-name harness-ecs-manager

# Attach policy
aws iam attach-user-policy \
    --user-name harness-ecs-manager \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/HarnessECSLifecyclePolicy

# Create access key - SAVE THE OUTPUT!
aws iam create-access-key --user-name harness-ecs-manager
```

---

## Step 3: Tag ECS Resources (Recommended)

### Recommended Tags:

| Tag Key | Example Values | Purpose |
|---------|----------------|---------|
| `Environment` | `dev`, `staging`, `prod` | Environment filtering |
| `ManagedBy` | `Harness` | Identify managed resources |
| `Project` | `project-name` | Project association |
| `Team` | `platform` | Team ownership |
| `CostCenter` | `engineering` | Cost tracking |
| `AutoScale` | `true/false` | Eligible for auto-scaling |

### Tag Cluster via CLI:
```bash
aws ecs tag-resource \
    --resource-arn arn:aws:ecs:us-east-1:123456789:cluster/my-cluster \
    --tags key=Environment,value=dev key=ManagedBy,value=Harness
```

### Tag Service via CLI:
```bash
aws ecs tag-resource \
    --resource-arn arn:aws:ecs:us-east-1:123456789:service/my-cluster/my-service \
    --tags key=Environment,value=dev key=AutoScale,value=true
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

# Verify ECS cluster access
echo "Testing ListClusters..."
aws ecs list-clusters

# Verify service access
echo "Testing ListServices..."
aws ecs list-services --cluster your-cluster-name

# Verify task access
echo "Testing ListTasks..."
aws ecs list-tasks --cluster your-cluster-name

echo "✅ AWS ECS setup verified!"
```

---

## Step 5: Understanding ECS ARN Patterns

### ARN Formats:
```
# Cluster ARN
arn:aws:ecs:REGION:ACCOUNT_ID:cluster/CLUSTER_NAME

# Service ARN
arn:aws:ecs:REGION:ACCOUNT_ID:service/CLUSTER_NAME/SERVICE_NAME

# Task ARN
arn:aws:ecs:REGION:ACCOUNT_ID:task/CLUSTER_NAME/TASK_ID

# Task Definition ARN
arn:aws:ecs:REGION:ACCOUNT_ID:task-definition/FAMILY:REVISION

# Container Instance ARN
arn:aws:ecs:REGION:ACCOUNT_ID:container-instance/CLUSTER_NAME/INSTANCE_ID
```

---

## Step 6: Restrict by Cluster (Optional)

Limit operations to specific clusters:

```json
{
    "Sid": "ECSServiceManagementRestricted",
    "Effect": "Allow",
    "Action": [
        "ecs:UpdateService"
    ],
    "Resource": [
        "arn:aws:ecs:us-east-1:123456789:service/dev-cluster/*",
        "arn:aws:ecs:us-east-1:123456789:service/staging-cluster/*"
    ]
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
│  │  │   harness-ecs-      │───▶│  HarnessECSLifecycle      ││ │
│  │  │   manager           │    │  Policy                   ││ │
│  │  │                     │    │                           ││ │
│  │  │  Access Key ────────┼────┼──▶ Permissions:           ││ │
│  │  │  Secret Key         │    │    - ListClusters         ││ │
│  │  │                     │    │    - DescribeServices     ││ │
│  │  │                     │    │    - UpdateService        ││ │
│  │  │                     │    │    - StopTask             ││ │
│  │  └─────────────────────┘    └───────────────────────────┘│ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                          ECS                              │ │
│  │                                                           │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Cluster: production                                │ │ │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │ │ │
│  │  │  │ api-service │ │ web-service │ │ worker-svc  │   │ │ │
│  │  │  │ Tasks: 3/3  │ │ Tasks: 2/2  │ │ Tasks: 5/5  │   │ │ │
│  │  │  │ [Fargate]   │ │ [Fargate]   │ │ [EC2]       │   │ │ │
│  │  │  └─────────────┘ └─────────────┘ └─────────────┘   │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                                                           │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Cluster: development                               │ │ │
│  │  │  ┌─────────────┐ ┌─────────────┐                   │ │ │
│  │  │  │ api-service │ │ web-service │                   │ │ │
│  │  │  │ Tasks: 1/1  │ │ Tasks: 0/0  │ ← Scaled to 0    │ │ │
│  │  │  └─────────────┘ └─────────────┘                   │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ API Calls
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      HARNESS PLATFORM                           │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  AWS Connector → ECS Lifecycle Pipeline                   │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `ClusterNotFoundException` | Cluster doesn't exist | Verify cluster name and region |
| `ServiceNotFoundException` | Service doesn't exist | Verify service name in cluster |
| `InvalidParameterException` | Invalid desired count | Check min/max constraints |
| `AccessDeniedException` | Missing permissions | Check IAM policy |
| `ServiceNotActiveException` | Service is draining | Wait for service to stabilize |

---

## Common AWS CLI Commands

```bash
# List all clusters
aws ecs list-clusters --region us-east-1

# Describe cluster
aws ecs describe-clusters --clusters my-cluster --region us-east-1

# List services in cluster
aws ecs list-services --cluster my-cluster --region us-east-1

# Describe service
aws ecs describe-services --cluster my-cluster --services my-service

# Update service desired count
aws ecs update-service --cluster my-cluster --service my-service --desired-count 3

# Force new deployment
aws ecs update-service --cluster my-cluster --service my-service --force-new-deployment

# List running tasks
aws ecs list-tasks --cluster my-cluster --service-name my-service

# Stop a task
aws ecs stop-task --cluster my-cluster --task TASK_ARN

# Drain container instance (EC2 launch type)
aws ecs update-container-instances-state \
    --cluster my-cluster \
    --container-instances INSTANCE_ARN \
    --status DRAINING
```
