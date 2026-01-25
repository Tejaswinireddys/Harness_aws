# EC2 Lifecycle Management - Implementation Checklist

Complete step-by-step guide to implement the solution.

---

## Phase 1: AWS Setup

### Step 1.1: Create IAM Policy
- [ ] Login to AWS Console
- [ ] Navigate to IAM → Policies → Create Policy
- [ ] Select JSON tab
- [ ] Paste the policy from `templates/iam-policy.json`
- [ ] Name: `HarnessEC2LifecyclePolicy`
- [ ] Click Create Policy

**CLI Alternative:**
```bash
aws iam create-policy \
    --policy-name HarnessEC2LifecyclePolicy \
    --policy-document file://templates/iam-policy.json
```

### Step 1.2: Create IAM User
- [ ] Navigate to IAM → Users → Create User
- [ ] User name: `harness-ec2-manager`
- [ ] Select "Access key - Programmatic access"
- [ ] Attach policy: `HarnessEC2LifecyclePolicy`
- [ ] Add tags:
  - Key: `Purpose`, Value: `Harness-Integration`
  - Key: `ManagedBy`, Value: `Platform-Team`
- [ ] Create User
- [ ] **IMPORTANT:** Download/Save the Access Key ID and Secret Access Key

**CLI Alternative:**
```bash
# Create user
aws iam create-user --user-name harness-ec2-manager

# Attach policy (replace YOUR_ACCOUNT_ID)
aws iam attach-user-policy \
    --user-name harness-ec2-manager \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/HarnessEC2LifecyclePolicy

# Create access key
aws iam create-access-key --user-name harness-ec2-manager
# SAVE THE OUTPUT!
```

### Step 1.3: Verify AWS Setup
- [ ] Test credentials locally:
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"

# Verify identity
aws sts get-caller-identity

# Verify EC2 access
aws ec2 describe-instances --max-results 1
```

### Step 1.4: Tag EC2 Instances (Optional but Recommended)
- [ ] Tag instances with:
  - `Environment`: dev/staging/production
  - `ManagedBy`: Harness
  - `Project`: your-project-name

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
- [ ] Name: `EC2 Instance Lifecycle Management`
- [ ] Click "Start with YAML"
- [ ] Copy content from `pipelines/ec2-lifecycle-management.yaml`
- [ ] Update these values:
  ```yaml
  orgIdentifier: your_actual_org_id
  projectIdentifier: your_actual_project_id
  ```
- [ ] Save Pipeline

### Step 2.4: Import List Pipeline (Optional)
- [ ] Create another pipeline
- [ ] Name: `EC2 Instance List`
- [ ] Copy content from `pipelines/ec2-list-instances.yaml`
- [ ] Update identifiers
- [ ] Save

### Step 2.5: Configure Notifications (Optional)
- [ ] Navigate to: Project → Project Settings → Notifications
- [ ] Create Slack notification:
  - [ ] Name: `EC2 Lifecycle Alerts`
  - [ ] Webhook URL: [Your Slack Webhook]
  - [ ] Events: Pipeline Success, Pipeline Failure
- [ ] Create Email notification:
  - [ ] Name: `EC2 Lifecycle Email`
  - [ ] Recipients: platform-team@yourcompany.com
  - [ ] Events: All Events

---

## Phase 3: Testing

### Step 3.1: Test List All Action
- [ ] Run pipeline with:
  - Action: `list_all`
  - Region: `us-east-1`
  - Leave other fields empty
- [ ] Verify:
  - [ ] Pipeline completes successfully
  - [ ] Instances are displayed in output
  - [ ] Counts match AWS Console

### Step 3.2: Test List Running Action
- [ ] Run pipeline with:
  - Action: `list_running`
  - Region: `us-east-1`
- [ ] Verify only running instances displayed

### Step 3.3: Test List Stopped Action
- [ ] Run pipeline with:
  - Action: `list_stopped`
  - Region: `us-east-1`
- [ ] Verify only stopped instances displayed

### Step 3.4: Test Stop Action (Dry Run)
- [ ] Run pipeline with:
  - Action: `stop`
  - Region: `us-east-1`
  - Instance IDs: `i-xxx` (use a dev instance)
  - Dry Run: `true`
- [ ] Verify:
  - [ ] No actual changes made
  - [ ] Simulation output shown

### Step 3.5: Test Stop Action (Real)
- [ ] Run pipeline with:
  - Action: `stop`
  - Region: `us-east-1`
  - Instance IDs: `i-xxx` (use a dev instance)
  - Dry Run: `false`
  - Wait for State: `true`
- [ ] Verify:
  - [ ] Instance stops
  - [ ] Verification stage confirms stopped state

### Step 3.6: Test Start Action
- [ ] Run pipeline with:
  - Action: `start`
  - Region: `us-east-1`
  - Instance IDs: `i-xxx` (same instance)
  - Dry Run: `false`
- [ ] Verify:
  - [ ] Instance starts
  - [ ] Verification confirms running state

### Step 3.7: Test Environment Filter
- [ ] Run pipeline with:
  - Action: `list_all`
  - Region: `us-east-1`
  - Environment Filter: `dev`
- [ ] Verify only dev-tagged instances shown

---

## Phase 4: Production Readiness

### Step 4.1: RBAC Setup
- [ ] Create custom role: `EC2 Lifecycle Operator`
- [ ] Create user group: `EC2 Operators`
- [ ] Assign role to group
- [ ] Add team members to group

### Step 4.2: Governance Policies (Optional)
- [ ] Create OPA policy to limit instances per action
- [ ] Create OPA policy to protect production
- [ ] Test policies work as expected

### Step 4.3: Documentation
- [ ] Share README with team
- [ ] Document any custom modifications
- [ ] Create runbook for common operations

### Step 4.4: Monitoring
- [ ] Set up CloudWatch alarms for unusual activity
- [ ] Enable CloudTrail logging
- [ ] Configure alert channels

---

## Quick Reference Commands

### AWS CLI Commands
```bash
# List all instances
aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output table

# List running instances
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --output table

# Start instance
aws ec2 start-instances --instance-ids i-xxx

# Stop instance
aws ec2 stop-instances --instance-ids i-xxx

# Wait for running state
aws ec2 wait instance-running --instance-ids i-xxx

# Wait for stopped state
aws ec2 wait instance-stopped --instance-ids i-xxx
```

### Harness Secret References
```yaml
# Organization level
<+secrets.getValue("org.aws_access_key_id")>
<+secrets.getValue("org.aws_secret_access_key")>

# Project level (if using project secrets instead)
<+secrets.getValue("aws_access_key_id")>
<+secrets.getValue("aws_secret_access_key")>
```

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
