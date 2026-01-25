# RDS Lifecycle Management - Implementation Checklist

Complete step-by-step guide to implement the RDS lifecycle management solution.

---

## Phase 1: AWS Setup

### Step 1.1: Create IAM Policy
- [ ] Login to AWS Console
- [ ] Navigate to IAM → Policies → Create Policy
- [ ] Select JSON tab
- [ ] Paste the policy from `templates/iam-policy.json`
- [ ] Name: `HarnessRDSLifecyclePolicy`
- [ ] Click Create Policy

**CLI Alternative:**
```bash
aws iam create-policy \
    --policy-name HarnessRDSLifecyclePolicy \
    --policy-document file://templates/iam-policy.json
```

### Step 1.2: Create IAM User
- [ ] Navigate to IAM → Users → Create User
- [ ] User name: `harness-rds-manager`
- [ ] Select "Access key - Programmatic access"
- [ ] Attach policy: `HarnessRDSLifecyclePolicy`
- [ ] Add tags:
  - Key: `Purpose`, Value: `Harness-Integration`
  - Key: `ManagedBy`, Value: `Platform-Team`
- [ ] Create User
- [ ] **IMPORTANT:** Download/Save the Access Key ID and Secret Access Key

**CLI Alternative:**
```bash
# Create user
aws iam create-user --user-name harness-rds-manager

# Attach policy (replace YOUR_ACCOUNT_ID)
aws iam attach-user-policy \
    --user-name harness-rds-manager \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/HarnessRDSLifecyclePolicy

# Create access key - SAVE THE OUTPUT!
aws iam create-access-key --user-name harness-rds-manager
```

### Step 1.3: Verify AWS Setup
- [ ] Test credentials locally:
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"

# Verify identity
aws sts get-caller-identity

# Verify RDS access
aws rds describe-db-instances --max-records 5

# Verify cluster access
aws rds describe-db-clusters --max-records 5

echo "✅ AWS setup verified!"
```

### Step 1.4: Tag RDS Instances (Recommended)
- [ ] Tag databases with:
  - `Environment`: dev/staging/production
  - `ManagedBy`: Harness
  - `Project`: your-project-name
  - `AutoStop`: true/false

```bash
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-east-1:123456789:db:mydb \
    --tags Key=Environment,Value=dev Key=ManagedBy,Value=Harness
```

---

## Phase 2: Harness Setup

### Step 2.1: Create Organization Secrets
- [ ] Login to Harness Platform
- [ ] Navigate to: Account Settings → Organizations → [Your Org] → Secrets

- [ ] Create Secret #1:
  - [ ] Click "+ New Secret" → "Text"
  - [ ] Name: `aws_access_key_id`
  - [ ] Identifier: `aws_access_key_id`
  - [ ] Value: [Paste AWS Access Key ID]
  - [ ] Tags: `aws`, `credentials`
  - [ ] Save

- [ ] Create Secret #2:
  - [ ] Click "+ New Secret" → "Text"
  - [ ] Name: `aws_secret_access_key`
  - [ ] Identifier: `aws_secret_access_key`
  - [ ] Value: [Paste AWS Secret Access Key]
  - [ ] Tags: `aws`, `credentials`
  - [ ] Save

### Step 2.2: Create Project (if needed)
- [ ] Navigate to: Organization → Projects → + New Project
- [ ] Name: `platform` or your preferred name
- [ ] Identifier: `platform`
- [ ] Select modules: CD (Continuous Delivery)
- [ ] Save

### Step 2.3: Import Main Pipeline
- [ ] Navigate to: Project → Pipelines → + Create a Pipeline
- [ ] Name: `RDS Instance Lifecycle Management`
- [ ] Click "Start with YAML"
- [ ] Copy content from `pipelines/rds-lifecycle-management.yaml`
- [ ] Update these values:
  ```yaml
  orgIdentifier: your_actual_org_id
  projectIdentifier: your_actual_project_id
  ```
- [ ] Save Pipeline

### Step 2.4: Import List Pipeline (Optional)
- [ ] Create another pipeline
- [ ] Name: `RDS Instance List`
- [ ] Copy content from `pipelines/rds-list-instances.yaml`
- [ ] Update identifiers
- [ ] Save

### Step 2.5: Configure Notifications (Optional)
- [ ] Navigate to: Project → Project Settings → Notifications
- [ ] Create Slack notification:
  - [ ] Name: `RDS Lifecycle Alerts`
  - [ ] Webhook URL: [Your Slack Webhook]
  - [ ] Events: Pipeline Success, Pipeline Failure

---

## Phase 3: Testing

### Step 3.1: Test List All Action
- [ ] Run pipeline with:
  - Action: `list_all`
  - Region: `us-east-1`
- [ ] Verify:
  - [ ] Pipeline completes successfully
  - [ ] RDS instances are displayed
  - [ ] Aurora clusters are displayed (if any)
  - [ ] Counts match AWS Console

### Step 3.2: Test List Available Action
- [ ] Run pipeline with:
  - Action: `list_available`
  - Region: `us-east-1`
- [ ] Verify only available (running) instances displayed

### Step 3.3: Test List Stopped Action
- [ ] Run pipeline with:
  - Action: `list_stopped`
  - Region: `us-east-1`
- [ ] Verify only stopped instances displayed

### Step 3.4: Test Stop Action (Dry Run)
- [ ] Run pipeline with:
  - Action: `stop`
  - Region: `us-east-1`
  - DB Identifiers: `mydb-dev` (use a dev database)
  - Create Snapshot: `true`
  - Dry Run: `true`
- [ ] Verify:
  - [ ] No actual changes made
  - [ ] Simulation output shown

### Step 3.5: Test Stop Action (Real)
- [ ] Run pipeline with:
  - Action: `stop`
  - Region: `us-east-1`
  - DB Identifiers: `mydb-dev`
  - Create Snapshot: `true`
  - Dry Run: `false`
  - Wait for State: `true`
- [ ] Verify:
  - [ ] Snapshot created
  - [ ] Database stops
  - [ ] Verification confirms stopped state

### Step 3.6: Test Start Action
- [ ] Run pipeline with:
  - Action: `start`
  - Region: `us-east-1`
  - DB Identifiers: `mydb-dev`
  - Dry Run: `false`
- [ ] Verify:
  - [ ] Database starts
  - [ ] Verification confirms available state

### Step 3.7: Test Engine Filter
- [ ] Run pipeline with:
  - Action: `list_all`
  - Region: `us-east-1`
  - Engine Filter: `postgres`
- [ ] Verify only PostgreSQL instances shown

---

## Phase 4: Production Readiness

### Step 4.1: RBAC Setup
- [ ] Create custom role: `RDS Lifecycle Operator`
- [ ] Create user group: `Database Operators`
- [ ] Assign role to group
- [ ] Add team members to group

### Step 4.2: Governance Policies (Optional)
- [ ] Create OPA policy to prevent stopping production
- [ ] Create OPA policy to require snapshot before stop
- [ ] Test policies work as expected

### Step 4.3: Scheduled Operations (Optional)
- [ ] Set up triggers for automated stop/start
- [ ] Configure for dev/test environments
- [ ] Account for 7-day auto-start limitation

### Step 4.4: Documentation
- [ ] Share README with team
- [ ] Document RDS naming conventions
- [ ] Create runbook for common operations
- [ ] Document 7-day auto-start behavior

### Step 4.5: Monitoring
- [ ] Set up CloudWatch alarms for RDS
- [ ] Monitor snapshot storage usage
- [ ] Track cost savings from stopped instances

---

## Quick Reference Commands

### AWS CLI Commands
```bash
# List all RDS instances
aws rds describe-db-instances \
    --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,Engine]' \
    --output table

# List Aurora clusters
aws rds describe-db-clusters \
    --query 'DBClusters[].[DBClusterIdentifier,Status,Engine]' \
    --output table

# Stop instance
aws rds stop-db-instance --db-instance-identifier mydb

# Start instance
aws rds start-db-instance --db-instance-identifier mydb

# Create snapshot
aws rds create-db-snapshot \
    --db-instance-identifier mydb \
    --db-snapshot-identifier mydb-snapshot-$(date +%Y%m%d)

# Wait for available
aws rds wait db-instance-available --db-instance-identifier mydb

# Wait for stopped
aws rds wait db-instance-stopped --db-instance-identifier mydb
```

### Harness Secret References
```yaml
# Organization level
<+secrets.getValue("org.aws_access_key_id")>
<+secrets.getValue("org.aws_secret_access_key")>
```

---

## RDS-Specific Considerations

### 7-Day Auto-Start Reminder
```
┌─────────────────────────────────────────────────────────────────┐
│  ⚠️  CRITICAL: RDS instances auto-start after 7 days!          │
│                                                                 │
│  When you stop an RDS instance, AWS will automatically         │
│  start it again after 7 days. This is by design.               │
│                                                                 │
│  Options:                                                       │
│  • Schedule pipeline to re-stop before 7 days                   │
│  • Use EventBridge to trigger re-stop                          │
│  • Accept the auto-start and plan accordingly                  │
└─────────────────────────────────────────────────────────────────┘
```

### Cannot Stop Read Replicas
- Read replicas cannot be stopped independently
- Must stop the primary instance first
- Pipeline will skip read replicas automatically

### Storage Costs Continue
- When stopped, only compute costs are saved
- Storage costs continue while stopped
- Snapshot costs are separate

---

## Completion Sign-off

| Phase | Status | Date | Completed By |
|-------|--------|------|--------------|
| Phase 1: AWS Setup | ☐ | | |
| Phase 2: Harness Setup | ☐ | | |
| Phase 3: Testing | ☐ | | |
| Phase 4: Production Ready | ☐ | | |

**Implementation Complete:** ☐

**Notes:**
_________________________________
_________________________________
_________________________________
