# Harness Setup Guide for RDS Lifecycle Management

## Overview
Complete step-by-step guide to configure Harness for RDS database lifecycle management.

---

## Step 1: Create Organization Secrets

### Navigate to Organization Settings
1. Log in to Harness Platform
2. Go to **Account Settings** → **Organizations**
3. Select your organization
4. Go to **Organization Settings** → **Secrets**

### Create AWS Access Key Secret
1. Click **+ New Secret** → **Text**
2. Configure:
   - **Name**: `aws_access_key_id`
   - **Identifier**: `aws_access_key_id`
   - **Description**: `AWS Access Key for RDS Lifecycle Management`
   - **Secret Value**: `<Your AWS Access Key ID>`
   - **Tags**: `aws`, `rds`, `credentials`
3. Click **Save**

### Create AWS Secret Access Key Secret
1. Click **+ New Secret** → **Text**
2. Configure:
   - **Name**: `aws_secret_access_key`
   - **Identifier**: `aws_secret_access_key`
   - **Description**: `AWS Secret Access Key for RDS Lifecycle Management`
   - **Secret Value**: `<Your AWS Secret Access Key>`
   - **Tags**: `aws`, `rds`, `credentials`
3. Click **Save**

### Secret Reference Format
```yaml
# Organization level secrets are referenced as:
<+secrets.getValue("org.aws_access_key_id")>
<+secrets.getValue("org.aws_secret_access_key")>
```

---

## Step 2: Pipeline Structure

The main pipeline consists of **7 stages**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     RDS LIFECYCLE PIPELINE STAGES                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────┐                                                          │
│  │ 1️⃣ INITIALIZE │  Display configuration, validate inputs                 │
│  └───────┬───────┘                                                          │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 2️⃣ VALIDATE   │  Verify AWS credentials & RDS permissions               │
│  └───────┬───────┘                                                          │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 3️⃣ DISCOVER   │  List RDS instances and Aurora clusters                 │
│  └───────┬───────┘                                                          │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 4️⃣ SNAPSHOT   │  Create pre-stop snapshot (conditional)                 │
│  └───────┬───────┘  Only runs when: action=stop AND create_snapshot=true   │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 5️⃣ EXECUTE    │  Start/Stop databases (conditional)                     │
│  └───────┬───────┘  Only runs when: action=start OR action=stop            │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 6️⃣ VERIFY     │  Confirm databases reached target state                 │
│  └───────┬───────┘  Only runs when: action=start/stop AND dry_run=false    │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────┐                                                          │
│  │ 7️⃣ SUMMARY    │  Generate report & send notifications                   │
│  └───────────────┘                                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 3: Pipeline Variables

| Variable | Type | Required | Allowed Values | Description |
|----------|------|----------|----------------|-------------|
| `action` | String | Yes | `list_all`, `list_available`, `list_stopped`, `list_clusters`, `start`, `stop` | Action to perform |
| `aws_region` | String | Yes | Multiple AWS regions | Target AWS region |
| `db_identifiers` | String | No* | Comma-separated | RDS instance identifiers |
| `cluster_identifiers` | String | No* | Comma-separated | Aurora cluster identifiers |
| `engine_filter` | String | No | `mysql`, `postgres`, `aurora-mysql`, etc. | Filter by engine |
| `create_snapshot` | Boolean | No | `true`, `false` | Create snapshot before stop |
| `dry_run` | Boolean | No | `true`, `false` | Simulate without changes |
| `wait_for_state` | Boolean | No | `true`, `false` | Wait for target state |

*Required for start/stop actions

---

## Step 4: Conditional Stage Execution

### Snapshot Stage Conditions
```yaml
when:
  pipelineStatus: Success
  condition: >
    <+pipeline.variables.action> == "stop" &&
    <+pipeline.variables.create_snapshot> == "true" &&
    <+pipeline.variables.dry_run> == "false"
```

### Execute Action Stage Conditions
```yaml
when:
  pipelineStatus: Success
  condition: >
    <+pipeline.variables.action> == "start" ||
    <+pipeline.variables.action> == "stop"
```

### Verify Stage Conditions
```yaml
when:
  pipelineStatus: Success
  condition: >
    (<+pipeline.variables.action> == "start" ||
     <+pipeline.variables.action> == "stop") &&
    <+pipeline.variables.dry_run> == "false"
```

---

## Step 5: Output Variable References

### From Discovery Stage
```yaml
# Total counts
TOTAL_INSTANCES: <+pipeline.stages.discovery.spec.execution.steps.list_instances.output.outputVariables.TOTAL_INSTANCES>
AVAILABLE_INSTANCES: <+pipeline.stages.discovery.spec.execution.steps.list_instances.output.outputVariables.AVAILABLE_INSTANCES>
STOPPED_INSTANCES: <+pipeline.stages.discovery.spec.execution.steps.list_instances.output.outputVariables.STOPPED_INSTANCES>
CLUSTER_COUNT: <+pipeline.stages.discovery.spec.execution.steps.list_instances.output.outputVariables.CLUSTER_COUNT>

# Instance ID lists
AVAILABLE_IDS: <+pipeline.stages.discovery.spec.execution.steps.list_instances.output.outputVariables.AVAILABLE_IDS>
STOPPED_IDS: <+pipeline.stages.discovery.spec.execution.steps.list_instances.output.outputVariables.STOPPED_IDS>
```

### From Snapshot Stage
```yaml
SNAPSHOT_STATUS: <+pipeline.stages.create_snapshot.spec.execution.steps.create_pre_stop_snapshot.output.outputVariables.SNAPSHOT_STATUS>
CREATED_SNAPSHOTS: <+pipeline.stages.create_snapshot.spec.execution.steps.create_pre_stop_snapshot.output.outputVariables.CREATED_SNAPSHOTS>
```

### From Execute Stage
```yaml
ACTION_RESULT: <+pipeline.stages.execute_action.spec.execution.steps.execute_database_action.output.outputVariables.ACTION_RESULT>
SUCCESS_COUNT: <+pipeline.stages.execute_action.spec.execution.steps.execute_database_action.output.outputVariables.SUCCESS_COUNT>
FAILED_COUNT: <+pipeline.stages.execute_action.spec.execution.steps.execute_database_action.output.outputVariables.FAILED_COUNT>
```

---

## Step 6: Notification Configuration

### Slack Notification
```yaml
notificationRules:
  - name: RDS Pipeline Success
    identifier: rds_pipeline_success
    pipelineEvents:
      - type: PipelineSuccess
    notificationMethod:
      type: Slack
      spec:
        webhookUrl: <+variable.slack_webhook_url>
    enabled: true

  - name: RDS Pipeline Failure
    identifier: rds_pipeline_failure
    pipelineEvents:
      - type: PipelineFailed
    notificationMethod:
      type: Slack
      spec:
        webhookUrl: <+variable.slack_webhook_url>
    enabled: true
```

### Email Notification
```yaml
notificationRules:
  - name: RDS Lifecycle Email
    identifier: rds_lifecycle_email
    pipelineEvents:
      - type: AllEvents
    notificationMethod:
      type: Email
      spec:
        userGroups:
          - account.databaseadmins
        recipients:
          - dba-team@yourcompany.com
```

---

## Step 7: RBAC Configuration

### Create Custom Role
**Navigation:** Account Settings → Access Control → Roles → + New Role

```yaml
role:
  name: RDS Lifecycle Operator
  identifier: rds_lifecycle_operator
  permissions:
    - resourceType: PIPELINE
      actions:
        - core_pipeline_view
        - core_pipeline_execute
    - resourceType: SECRET
      actions:
        - core_secret_view
    - resourceType: CONNECTOR
      actions:
        - core_connector_view
```

### Create User Group
```yaml
userGroup:
  name: Database Operators
  identifier: database_operators
  users:
    - dba1@company.com
    - dba2@company.com
  roleBindings:
    - roleIdentifier: rds_lifecycle_operator
      resourceGroupIdentifier: _all_project_level_resources
```

---

## Step 8: Governance Policies (OPA)

### Prevent Stopping Production Databases
```rego
package pipeline

deny[msg] {
    input.pipeline.variables.action == "stop"
    input.pipeline.variables.db_identifiers
    contains(input.pipeline.variables.db_identifiers, "prod")
    not input.pipeline.variables.emergency_override == "true"
    msg := "Cannot stop production databases without emergency_override=true"
}
```

### Require Snapshot Before Stop
```rego
package pipeline

deny[msg] {
    input.pipeline.variables.action == "stop"
    input.pipeline.variables.create_snapshot == "false"
    input.pipeline.variables.dry_run == "false"
    msg := "Snapshot must be enabled when stopping databases"
}
```

---

## Verification Checklist

```
□ Organization secrets created
  □ aws_access_key_id
  □ aws_secret_access_key

□ Main pipeline imported and configured
  □ Organization identifier updated
  □ Project identifier updated

□ List pipeline imported (optional)

□ Notifications configured
  □ Success notifications
  □ Failure notifications

□ RBAC configured
  □ Custom role created
  □ User group assigned

□ Governance policies applied (optional)
  □ Production protection policy
  □ Snapshot requirement policy

□ Testing completed
  □ List all action tested
  □ Start action tested (dry run)
  □ Stop action tested (dry run)
  □ Real start/stop tested on dev
```

---

## Quick Reference

### Environment Variables in Scripts
```yaml
envVariables:
  AWS_ACCESS_KEY_ID: <+secrets.getValue("org.aws_access_key_id")>
  AWS_SECRET_ACCESS_KEY: <+secrets.getValue("org.aws_secret_access_key")>
  AWS_REGION: <+pipeline.variables.aws_region>
  ACTION: <+pipeline.variables.action>
  DB_IDENTIFIERS: <+pipeline.variables.db_identifiers>
  CLUSTER_IDENTIFIERS: <+pipeline.variables.cluster_identifiers>
  DRY_RUN: <+pipeline.variables.dry_run>
```

### Common Pipeline Expressions
```yaml
# Check if action is list-type
<+pipeline.variables.action>.startsWith("list")

# Check if databases specified
<+pipeline.variables.db_identifiers> != ""

# Combine conditions
<+pipeline.variables.action> == "stop" && <+pipeline.variables.dry_run> == "false"
```
