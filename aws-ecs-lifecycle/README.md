# AWS ECS Cluster Lifecycle Management with Harness

A comprehensive, enterprise-grade solution for managing AWS ECS clusters, services, and tasks lifecycle using Harness CI/CD platform.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [ECS Concepts](#ecs-concepts)
3. [Features](#features)
4. [Prerequisites](#prerequisites)
5. [Quick Start Guide](#quick-start-guide)
6. [Pipeline Usage](#pipeline-usage)
7. [Best Practices](#best-practices)

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────────────────────────┐
│                            ECS LIFECYCLE MANAGEMENT ARCHITECTURE                               │
├────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                │
│   ┌─────────────┐      ┌────────────────────────────────────────────────────────────────────┐ │
│   │   USER      │      │                        HARNESS PLATFORM                            │ │
│   │   INPUT     │─────▶│                                                                    │ │
│   │  - Action   │      │  ┌────────────────────────────────────────────────────────────────┐│ │
│   │  - Cluster  │      │  │                ECS LIFECYCLE PIPELINE                          ││ │
│   │  - Service  │      │  │                                                                ││ │
│   │  - Scale    │      │  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐   ││ │
│   └─────────────┘      │  │  │ 1️⃣  │─▶│ 2️⃣  │─▶│ 3️⃣  │─▶│ 4️⃣  │─▶│ 5️⃣  │─▶│ 6️⃣  │   ││ │
│                        │  │  │INIT  │  │VALID │  │DISCO │  │ACTION│  │VERIFY│  │SUMRY │   ││ │
│                        │  │  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘   ││ │
│                        │  │                                                                ││ │
│                        │  │  ORG SECRETS:                                                  ││ │
│                        │  │  ├── aws_access_key_id                                         ││ │
│                        │  │  └── aws_secret_access_key                                     ││ │
│                        │  └────────────────────────────────────────────────────────────────┘│ │
│                        └────────────────────────────────────────────────────────────────────┘ │
│                                              │                                                 │
│                                              │ AWS ECS API Calls                               │
│                                              ▼                                                 │
│   ┌────────────────────────────────────────────────────────────────────────────────────────┐  │
│   │                                    AWS ACCOUNT                                          │  │
│   │                                                                                         │  │
│   │  ┌───────────────────────────────────────────────────────────────────────────────────┐ │  │
│   │  │                              ECS CLUSTERS                                          │ │  │
│   │  │                                                                                    │ │  │
│   │  │   ┌─────────────────────────────────────────────────────────────────────────────┐ │ │  │
│   │  │   │  CLUSTER: production-cluster                                                │ │ │  │
│   │  │   │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │ │ │  │
│   │  │   │  │ Service: api    │  │ Service: web    │  │ Service: worker │             │ │ │  │
│   │  │   │  │ Desired: 3      │  │ Desired: 2      │  │ Desired: 5      │             │ │ │  │
│   │  │   │  │ Running: 3      │  │ Running: 2      │  │ Running: 5      │             │ │ │  │
│   │  │   │  │ [Fargate]       │  │ [Fargate]       │  │ [EC2]           │             │ │ │  │
│   │  │   │  └─────────────────┘  └─────────────────┘  └─────────────────┘             │ │ │  │
│   │  │   └─────────────────────────────────────────────────────────────────────────────┘ │ │  │
│   │  │                                                                                    │ │  │
│   │  │   ┌─────────────────────────────────────────────────────────────────────────────┐ │ │  │
│   │  │   │  CLUSTER: development-cluster                                               │ │ │  │
│   │  │   │  ┌─────────────────┐  ┌─────────────────┐                                   │ │ │  │
│   │  │   │  │ Service: api    │  │ Service: web    │                                   │ │ │  │
│   │  │   │  │ Desired: 1      │  │ Desired: 1      │                                   │ │ │  │
│   │  │   │  │ Running: 1      │  │ Running: 1      │                                   │ │ │  │
│   │  │   │  └─────────────────┘  └─────────────────┘                                   │ │ │  │
│   │  │   └─────────────────────────────────────────────────────────────────────────────┘ │ │  │
│   │  └───────────────────────────────────────────────────────────────────────────────────┘ │  │
│   └────────────────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## ECS Concepts

### Component Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                      ECS COMPONENT HIERARCHY                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                       CLUSTER                            │   │
│  │  Logical grouping of services and tasks                  │   │
│  │                                                          │   │
│  │  ┌───────────────────────────────────────────────────┐  │   │
│  │  │                    SERVICES                        │  │   │
│  │  │  Long-running applications with desired count      │  │   │
│  │  │                                                    │  │   │
│  │  │  ┌─────────────────────────────────────────────┐  │  │   │
│  │  │  │                  TASKS                       │  │  │   │
│  │  │  │  Running instances of task definitions       │  │  │   │
│  │  │  │                                              │  │  │   │
│  │  │  │  ┌───────────────────────────────────────┐  │  │  │   │
│  │  │  │  │            CONTAINERS                  │  │  │  │   │
│  │  │  │  │  Docker containers within tasks        │  │  │  │   │
│  │  │  │  └───────────────────────────────────────┘  │  │  │   │
│  │  │  └─────────────────────────────────────────────┘  │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  │                                                          │   │
│  │  ┌───────────────────────────────────────────────────┐  │   │
│  │  │           CONTAINER INSTANCES (EC2 only)          │  │   │
│  │  │  EC2 instances registered to the cluster          │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Launch Types

| Launch Type | Description | Use Case |
|-------------|-------------|----------|
| **Fargate** | Serverless, AWS manages infrastructure | Most workloads, simpler operations |
| **EC2** | You manage EC2 instances | GPU, Windows, specific instance types |
| **External** | On-premises or external compute | Hybrid deployments |

### Service Lifecycle States

```
┌─────────────────────────────────────────────────────────────────┐
│                    SERVICE STATE DIAGRAM                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│     ┌─────────┐         ┌─────────┐         ┌─────────┐        │
│     │ ACTIVE  │◀───────▶│ DRAINING│────────▶│INACTIVE │        │
│     └────┬────┘         └─────────┘         └─────────┘        │
│          │                                                      │
│          │ (scale)                                              │
│          ▼                                                      │
│     ┌─────────┐                                                 │
│     │ ACTIVE  │  desiredCount: 0 → N (scale up)                │
│     │         │  desiredCount: N → 0 (scale down)              │
│     └─────────┘                                                 │
│                                                                 │
│  Task States: PROVISIONING → PENDING → RUNNING → STOPPED       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Features

| Feature | Description |
|---------|-------------|
| **List Clusters** | View all ECS clusters with status |
| **List Services** | View services in a cluster with task counts |
| **List Tasks** | View running tasks with status details |
| **Scale Up** | Increase service desired count |
| **Scale Down** | Decrease service desired count (0 to stop) |
| **Scale to Zero** | Stop all tasks in a service (cost saving) |
| **Force Deploy** | Trigger new deployment without changes |
| **Stop Tasks** | Stop specific running tasks |
| **Restart Service** | Force new deployment to restart |
| **Drain Instances** | Drain EC2 container instances |
| **Multi-Service** | Scale multiple services at once |
| **Dry Run Mode** | Simulate actions without changes |
| **State Verification** | Verify desired state is reached |

---

## Prerequisites

### AWS Requirements
- [ ] AWS Account with ECS clusters
- [ ] IAM User with programmatic access
- [ ] ECS permissions (describe, update, scale)

### Harness Requirements
- [ ] Harness account with CD module
- [ ] Project with appropriate permissions
- [ ] AWS CLI available in execution environment

---

## Quick Start Guide

### Step 1: AWS Setup

```bash
# Create IAM Policy
aws iam create-policy \
    --policy-name HarnessECSLifecyclePolicy \
    --policy-document file://templates/iam-policy.json

# Create IAM User
aws iam create-user --user-name harness-ecs-manager

# Attach Policy
aws iam attach-user-policy \
    --user-name harness-ecs-manager \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/HarnessECSLifecyclePolicy

# Create Access Key
aws iam create-access-key --user-name harness-ecs-manager
```

### Step 2: Harness Setup

1. Create Organization Secrets:
   - `aws_access_key_id`
   - `aws_secret_access_key`

2. Import pipeline from `pipelines/ecs-lifecycle-management.yaml`

3. Test with `list_clusters` action

---

## Pipeline Usage

### List All Clusters
```
Action: list_clusters
Region: us-east-1
```

### List Services in Cluster
```
Action: list_services
Region: us-east-1
Cluster: production-cluster
```

### Scale Service Up
```
Action: scale_up
Region: us-east-1
Cluster: production-cluster
Service: api-service
Desired Count: 5
```

### Scale to Zero (Stop)
```
Action: scale_down
Region: us-east-1
Cluster: development-cluster
Service: api-service,web-service
Desired Count: 0
```

### Force New Deployment
```
Action: restart
Region: us-east-1
Cluster: production-cluster
Service: api-service
```

---

## Best Practices

### Cost Optimization
- Scale down dev/test services after hours
- Use scale to zero for non-production
- Monitor and right-size task definitions

### Operations
- Use dry run mode before production changes
- Implement approval gates for production
- Tag clusters and services consistently

### Scaling
- Consider Application Auto Scaling for production
- Set appropriate min/max for services
- Monitor CloudWatch metrics

---

## File Structure

```
aws-ecs-lifecycle/
├── README.md
├── docs/
│   ├── AWS_SETUP.md
│   ├── HARNESS_SETUP.md
│   └── IMPLEMENTATION_CHECKLIST.md
├── pipelines/
│   ├── ecs-lifecycle-management.yaml     # Main 6-stage pipeline
│   ├── ecs-list-resources.yaml           # Simple list pipeline
│   └── ecs-scale-services.yaml           # Quick scale pipeline
├── scripts/
│   ├── validate_credentials.sh
│   ├── discover_clusters.sh
│   ├── discover_services.sh
│   ├── scale_service.sh
│   └── verify_state.sh
└── templates/
    ├── iam-policy.json
    └── iam-policy-readonly.json
```

---

**Version:** 1.0.0
**Author:** Platform Team
