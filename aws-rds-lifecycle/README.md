# AWS RDS Instance Lifecycle Management with Harness

A comprehensive, enterprise-grade solution for managing AWS RDS database instance lifecycle (Start, Stop, List, Snapshot) using Harness CI/CD platform.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [RDS Lifecycle Considerations](#rds-lifecycle-considerations)
3. [Features](#features)
4. [Prerequisites](#prerequisites)
5. [Quick Start Guide](#quick-start-guide)
6. [Pipeline Usage](#pipeline-usage)
7. [Best Practices](#best-practices)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│                           RDS LIFECYCLE MANAGEMENT ARCHITECTURE                              │
├──────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                              │
│   ┌─────────────┐      ┌──────────────────────────────────────────────────────────────────┐ │
│   │   USER      │      │                      HARNESS PLATFORM                            │ │
│   │   INPUT     │─────▶│                                                                  │ │
│   │  - Action   │      │  ┌──────────────────────────────────────────────────────────────┐│ │
│   │  - Region   │      │  │               RDS LIFECYCLE PIPELINE                         ││ │
│   │  - DB IDs   │      │  │                                                              ││ │
│   │  - Snapshot │      │  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐ ││ │
│   └─────────────┘      │  │  │  1️⃣   │─▶│  2️⃣   │─▶│  3️⃣   │─▶│  4️⃣   │─▶│  5️⃣   │ ││ │
│                        │  │  │ INIT   │  │VALIDATE│  │DISCOVER│  │SNAPSHOT│  │ ACTION │ ││ │
│                        │  │  └────────┘  └────────┘  └────────┘  └────────┘  └────────┘ ││ │
│                        │  │                                                      │       ││ │
│                        │  │                                          ┌───────────▼─────┐ ││ │
│                        │  │                                          │      6️⃣        │ ││ │
│                        │  │                                          │    VERIFY       │ ││ │
│                        │  │                                          └─────────────────┘ ││ │
│                        │  │                                                      │       ││ │
│                        │  │  ORG SECRETS:                            ┌───────────▼─────┐ ││ │
│                        │  │  ├── aws_access_key_id                   │      7️⃣        │ ││ │
│                        │  │  └── aws_secret_access_key               │   SUMMARY       │ ││ │
│                        │  │                                          └─────────────────┘ ││ │
│                        │  └──────────────────────────────────────────────────────────────┘│ │
│                        └──────────────────────────────────────────────────────────────────┘ │
│                                              │                                               │
│                                              │ AWS RDS API Calls                             │
│                                              ▼                                               │
│   ┌──────────────────────────────────────────────────────────────────────────────────────┐  │
│   │                                  AWS ACCOUNT                                          │  │
│   │  ┌────────────────────────────────────────────────────────────────────────────────┐  │  │
│   │  │  IAM User: harness-rds-manager                                                 │  │  │
│   │  │  Policy: HarnessRDSLifecyclePolicy                                             │  │  │
│   │  │  Permissions: DescribeDB*, StartDB*, StopDB*, CreateDBSnapshot                 │  │  │
│   │  └────────────────────────────────────────────────────────────────────────────────┘  │  │
│   │                                         │                                             │  │
│   │  ┌──────────────────────────────────────┴──────────────────────────────────────────┐ │  │
│   │  │                              RDS INSTANCES & CLUSTERS                            │ │  │
│   │  │                                                                                  │ │  │
│   │  │   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                 │ │  │
│   │  │   │   PostgreSQL    │  │     MySQL       │  │  Aurora Cluster │                 │ │  │
│   │  │   │   (available)   │  │   (stopped)     │  │   (available)   │                 │ │  │
│   │  │   │   db.t3.medium  │  │   db.t3.small   │  │   db.r5.large   │                 │ │  │
│   │  │   └─────────────────┘  └─────────────────┘  └─────────────────┘                 │ │  │
│   │  │                                                                                  │ │  │
│   │  │   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                 │ │  │
│   │  │   │   SQL Server    │  │    MariaDB      │  │     Oracle      │                 │ │  │
│   │  │   │   (available)   │  │   (stopped)     │  │   (available)   │                 │ │  │
│   │  │   │   db.m5.large   │  │   db.t3.micro   │  │   db.m5.xlarge  │                 │ │  │
│   │  │   └─────────────────┘  └─────────────────┘  └─────────────────┘                 │ │  │
│   │  └──────────────────────────────────────────────────────────────────────────────────┘ │  │
│   └──────────────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## RDS Lifecycle Considerations

### Important RDS Behaviors

| Behavior | Description | Impact |
|----------|-------------|--------|
| **7-Day Auto-Start** | Stopped RDS instances auto-start after 7 days | Plan for re-stop if needed |
| **Read Replicas** | Cannot be stopped independently | Must stop primary first |
| **Multi-AZ** | Both instances stop/start together | No additional action needed |
| **Aurora Clusters** | Use cluster-level commands | Different API calls |
| **Pending Changes** | Applied during next maintenance or restart | Consider during start |
| **Storage Costs** | Storage charges continue when stopped | Only compute is saved |

### RDS Instance States

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RDS INSTANCE STATE DIAGRAM                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                            ┌─────────────┐                                  │
│                     ┌─────▶│  AVAILABLE  │◀─────┐                          │
│                     │      └──────┬──────┘      │                          │
│                     │             │             │                          │
│              (start)│             │(stop)       │(auto-start               │
│                     │             │             │ after 7 days)            │
│                     │             ▼             │                          │
│              ┌──────┴──────┐    ┌──────────────┴┐                          │
│              │  STARTING   │    │   STOPPING    │                          │
│              └──────┬──────┘    └───────┬───────┘                          │
│                     │                   │                                   │
│                     │                   ▼                                   │
│                     │           ┌─────────────┐                            │
│                     └──────────▶│   STOPPED   │                            │
│                                 └─────────────┘                            │
│                                                                             │
│  Other States: creating, deleting, failed, maintenance, modifying,         │
│                rebooting, renaming, resetting-master-credentials,          │
│                storage-full, storage-optimization, upgrading               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Supported Database Engines

| Engine | Stop/Start Supported | Notes |
|--------|---------------------|-------|
| MySQL | ✅ Yes | Standard RDS |
| PostgreSQL | ✅ Yes | Standard RDS |
| MariaDB | ✅ Yes | Standard RDS |
| Oracle | ✅ Yes | Requires license |
| SQL Server | ✅ Yes | Express, Web, Standard, Enterprise |
| Aurora MySQL | ✅ Yes | Cluster-level operations |
| Aurora PostgreSQL | ✅ Yes | Cluster-level operations |

---

## Features

| Feature | Description |
|---------|-------------|
| **List All Instances** | View all RDS instances with status and details |
| **List Available** | Filter only available (running) instances |
| **List Stopped** | Filter only stopped instances |
| **List Aurora Clusters** | View Aurora clusters separately |
| **Start Instances** | Start one or more stopped instances |
| **Stop Instances** | Stop one or more running instances |
| **Start Clusters** | Start Aurora clusters |
| **Stop Clusters** | Stop Aurora clusters |
| **Create Snapshot** | Optional snapshot before stop |
| **Dry Run Mode** | Simulate actions without changes |
| **State Verification** | Verify instances reach target state |
| **Multi-Region** | Works across AWS regions |
| **Engine Filtering** | Filter by database engine |
| **Notifications** | Slack/Email on completion |

---

## Prerequisites

### AWS Requirements
- [ ] AWS Account with RDS instances
- [ ] IAM User with programmatic access
- [ ] RDS permissions (describe, start, stop, snapshot)

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
    --policy-name HarnessRDSLifecyclePolicy \
    --policy-document file://templates/iam-policy.json

# Create IAM User
aws iam create-user --user-name harness-rds-manager

# Attach Policy
aws iam attach-user-policy \
    --user-name harness-rds-manager \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/HarnessRDSLifecyclePolicy

# Create Access Key
aws iam create-access-key --user-name harness-rds-manager
```

### Step 2: Harness Setup

1. Create Organization Secrets:
   - `aws_access_key_id`
   - `aws_secret_access_key`

2. Import pipeline from `pipelines/rds-lifecycle-management.yaml`

3. Test with `list_all` action

---

## Pipeline Usage

### List All RDS Instances
```
Action: list_all
Region: us-east-1
```

### List Aurora Clusters
```
Action: list_clusters
Region: us-east-1
```

### Stop Instance with Snapshot
```
Action: stop
Region: us-east-1
Instance IDs: mydb-prod,mydb-staging
Create Snapshot: true
```

### Start Instance
```
Action: start
Region: us-east-1
Instance IDs: mydb-dev
```

---

## Best Practices

### Before Stopping
- [ ] Create snapshot (enabled by default)
- [ ] Verify no active connections
- [ ] Notify dependent teams
- [ ] Check for pending modifications

### Production Safety
- [ ] Use dry run mode first
- [ ] Implement approval gates
- [ ] Tag instances properly
- [ ] Monitor 7-day auto-start

### Cost Optimization
- [ ] Stop dev/test instances after hours
- [ ] Schedule automated stop/start
- [ ] Monitor storage costs (continue when stopped)

---

## File Structure

```
aws-rds-lifecycle/
├── README.md
├── docs/
│   ├── AWS_SETUP.md
│   ├── HARNESS_SETUP.md
│   └── IMPLEMENTATION_CHECKLIST.md
├── pipelines/
│   ├── rds-lifecycle-management.yaml     # Main 7-stage pipeline
│   ├── rds-list-instances.yaml           # Simple list pipeline
│   └── rds-scheduled-stop-start.yaml     # Scheduled operations
├── scripts/
│   ├── validate_credentials.sh
│   ├── discover_instances.sh
│   ├── discover_clusters.sh
│   ├── create_snapshot.sh
│   ├── execute_action.sh
│   └── verify_state.sh
└── templates/
    ├── iam-policy.json
    └── iam-policy-readonly.json
```

---

**Version:** 1.0.0
**Author:** Platform Team
