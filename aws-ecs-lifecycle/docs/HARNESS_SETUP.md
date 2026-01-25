# Harness Setup Guide for ECS Lifecycle Management

## Overview
Complete step-by-step guide to configure Harness for ECS cluster and service lifecycle management.

---

## Step 1: Create Organization Secrets

### Navigate to Organization Settings
1. Log in to Harness Platform
2. Go to **Account Settings** → **Organizations**
3. Select your organization
4. Go to **Organization Settings** → **Secrets**

### Create Secrets
| Secret Name | Identifier | Value |
|-------------|------------|-------|
| `aws_access_key_id` | `aws_access_key_id` | Your AWS Access Key |
| `aws_secret_access_key` | `aws_secret_access_key` | Your AWS Secret Key |

### Secret Reference Format
```yaml
<+secrets.getValue("org.aws_access_key_id")>
<+secrets.getValue("org.aws_secret_access_key")>
```

---

## Step 2: Pipeline Structure

The main pipeline consists of **6 stages**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     ECS LIFECYCLE PIPELINE STAGES                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────┐                                                          │
│  │ 1️⃣ INITIALIZE │  Display configuration, validate inputs                 │
│  └───────┬───────┘                                                          │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 2️⃣ VALIDATE   │  Verify AWS credentials & ECS permissions               │
│  └───────┬───────┘                                                          │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 3️⃣ DISCOVER   │  List clusters and services                             │
│  └───────┬───────┘                                                          │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 4️⃣ EXECUTE    │  Scale/Restart/Stop services (conditional)              │
│  └───────┬───────┘                                                          │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 5️⃣ VERIFY     │  Confirm services reached target state                  │
│  └───────┬───────┘                                                          │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 6️⃣ SUMMARY    │  Generate report & send notifications                   │
│  └───────────────┘                                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 3: Pipeline Variables

| Variable | Type | Required | Allowed Values | Description |
|----------|------|----------|----------------|-------------|
| `action` | String | Yes | `list_clusters`, `list_services`, `list_tasks`, `scale_up`, `scale_down`, `scale_to`, `restart`, `stop` | Action to perform |
| `aws_region` | String | Yes | AWS regions | Target region |
| `cluster_name` | String | No* | Cluster name | ECS cluster |
| `service_names` | String | No* | Comma-separated | Target services |
| `desired_count` | String | No** | Number | Target count |
| `dry_run` | Boolean | No | `true`, `false` | Simulate only |
| `wait_for_stable` | Boolean | No | `true`, `false` | Wait for stability |

*Required for scale/restart/stop actions
**Required for scale_to action

---

## Step 4: Action Types

### Scaling Actions

| Action | Effect | Use Case |
|--------|--------|----------|
| `scale_up` | +1 to desired count | Increase capacity |
| `scale_down` | -1 to desired count (min 0) | Reduce capacity |
| `scale_to` | Set specific count | Exact scaling |
| `stop` | Set to 0 | Stop service (cost saving) |
| `restart` | Force new deployment | Rolling restart |

### List Actions

| Action | Description |
|--------|-------------|
| `list_clusters` | Show all clusters |
| `list_services` | Show services in cluster |
| `list_tasks` | Show running tasks |

---

## Step 5: Conditional Stage Execution

### Execute Stage Conditions
```yaml
when:
  pipelineStatus: Success
  condition: >
    <+pipeline.variables.action> == "scale_up" ||
    <+pipeline.variables.action> == "scale_down" ||
    <+pipeline.variables.action> == "scale_to" ||
    <+pipeline.variables.action> == "restart" ||
    <+pipeline.variables.action> == "stop"
```

### Verify Stage Conditions
```yaml
when:
  pipelineStatus: Success
  condition: >
    (<+pipeline.variables.action> == "scale_up" || ...) &&
    <+pipeline.variables.dry_run> == "false"
```

---

## Step 6: Output Variables

### From Discovery Stage
```yaml
CLUSTER_COUNT: <+pipeline.stages.discovery.spec.execution.steps.list_resources.output.outputVariables.CLUSTER_COUNT>
SERVICE_COUNT: <+pipeline.stages.discovery.spec.execution.steps.list_resources.output.outputVariables.SERVICE_COUNT>
```

### From Execute Stage
```yaml
ACTION_RESULT: <+pipeline.stages.execute_action.spec.execution.steps.execute_service_action.output.outputVariables.ACTION_RESULT>
SUCCESS_COUNT: <+pipeline.stages.execute_action.spec.execution.steps.execute_service_action.output.outputVariables.SUCCESS_COUNT>
```

---

## Step 7: Sample Usage

### List All Clusters
```yaml
action: list_clusters
aws_region: us-east-1
```

### Scale Service Up
```yaml
action: scale_up
aws_region: us-east-1
cluster_name: production-cluster
service_names: api-service
dry_run: false
```

### Scale Multiple Services to Zero (Stop)
```yaml
action: stop
aws_region: us-east-1
cluster_name: dev-cluster
service_names: api-service,web-service,worker-service
```

### Force Restart
```yaml
action: restart
aws_region: us-east-1
cluster_name: production-cluster
service_names: api-service
wait_for_stable: true
```

---

## Step 8: RBAC Configuration

### Create Custom Role
```yaml
role:
  name: ECS Lifecycle Operator
  identifier: ecs_lifecycle_operator
  permissions:
    - resourceType: PIPELINE
      actions:
        - core_pipeline_view
        - core_pipeline_execute
    - resourceType: SECRET
      actions:
        - core_secret_view
```

---

## Verification Checklist

```
□ Organization secrets created
  □ aws_access_key_id
  □ aws_secret_access_key

□ Main pipeline imported
  □ Organization identifier updated
  □ Project identifier updated

□ List pipeline imported (optional)

□ Tested successfully
  □ List clusters action
  □ List services action
  □ Scale action (dry run)
  □ Scale action (real)

□ Notifications configured (optional)
□ RBAC configured (optional)
```
