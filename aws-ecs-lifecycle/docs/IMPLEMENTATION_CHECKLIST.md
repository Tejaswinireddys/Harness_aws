# ECS Lifecycle Management - Implementation Checklist

Complete step-by-step guide to implement the ECS lifecycle management solution.

---

## Phase 1: AWS Setup

### Step 1.1: Create IAM Policy
- [ ] Login to AWS Console
- [ ] Navigate to IAM → Policies → Create Policy
- [ ] Select JSON tab
- [ ] Paste the policy from `templates/iam-policy.json`
- [ ] Name: `HarnessECSLifecyclePolicy`
- [ ] Click Create Policy

**CLI Alternative:**
```bash
aws iam create-policy \
    --policy-name HarnessECSLifecyclePolicy \
    --policy-document file://templates/iam-policy.json
```

### Step 1.2: Create IAM User
- [ ] Create user: `harness-ecs-manager`
- [ ] Attach policy: `HarnessECSLifecyclePolicy`
- [ ] Generate and save access keys

```bash
aws iam create-user --user-name harness-ecs-manager
aws iam attach-user-policy \
    --user-name harness-ecs-manager \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/HarnessECSLifecyclePolicy
aws iam create-access-key --user-name harness-ecs-manager
```

### Step 1.3: Verify AWS Setup
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"

# Verify identity
aws sts get-caller-identity

# Verify ECS access
aws ecs list-clusters
aws ecs list-services --cluster your-cluster

echo "✅ AWS setup verified!"
```

### Step 1.4: Tag ECS Resources (Recommended)
- [ ] Tag clusters and services with:
  - `Environment`: dev/staging/production
  - `ManagedBy`: Harness
  - `Team`: your-team

---

## Phase 2: Harness Setup

### Step 2.1: Create Organization Secrets
- [ ] Navigate to: Account Settings → Organizations → [Your Org] → Secrets
- [ ] Create `aws_access_key_id` secret
- [ ] Create `aws_secret_access_key` secret

### Step 2.2: Import Pipeline
- [ ] Navigate to: Project → Pipelines → + Create Pipeline
- [ ] Copy content from `pipelines/ecs-lifecycle-management.yaml`
- [ ] Update `orgIdentifier` and `projectIdentifier`
- [ ] Save

### Step 2.3: Configure Notifications (Optional)
- [ ] Set up Slack webhook
- [ ] Configure email notifications

---

## Phase 3: Testing

### Step 3.1: Test List Clusters
- [ ] Run pipeline:
  - Action: `list_clusters`
  - Region: `us-east-1`
- [ ] Verify clusters displayed

### Step 3.2: Test List Services
- [ ] Run pipeline:
  - Action: `list_services`
  - Region: `us-east-1`
  - Cluster: `your-cluster`
- [ ] Verify services displayed

### Step 3.3: Test Scale (Dry Run)
- [ ] Run pipeline:
  - Action: `scale_up`
  - Cluster: `dev-cluster`
  - Services: `my-service`
  - Dry Run: `true`
- [ ] Verify no changes made

### Step 3.4: Test Scale (Real)
- [ ] Run pipeline:
  - Action: `scale_to`
  - Cluster: `dev-cluster`
  - Services: `my-service`
  - Desired Count: `2`
  - Dry Run: `false`
- [ ] Verify service scaled

### Step 3.5: Test Stop (Scale to Zero)
- [ ] Run pipeline:
  - Action: `stop`
  - Cluster: `dev-cluster`
  - Services: `my-service`
- [ ] Verify service has 0 running tasks

### Step 3.6: Test Restart
- [ ] Run pipeline:
  - Action: `restart`
  - Cluster: `dev-cluster`
  - Services: `my-service`
- [ ] Verify new deployment triggered

---

## Phase 4: Production Readiness

### Step 4.1: RBAC Setup
- [ ] Create custom role: `ECS Lifecycle Operator`
- [ ] Create user group: `Container Operators`
- [ ] Assign permissions

### Step 4.2: Governance Policies (Optional)
- [ ] Create OPA policy to prevent production stop
- [ ] Create OPA policy for scaling limits

### Step 4.3: Documentation
- [ ] Share README with team
- [ ] Document cluster/service naming conventions
- [ ] Create runbook for common operations

---

## Quick Reference

### AWS CLI Commands
```bash
# List clusters
aws ecs list-clusters

# List services
aws ecs list-services --cluster my-cluster

# Describe service
aws ecs describe-services --cluster my-cluster --services my-service

# Update service (scale)
aws ecs update-service --cluster my-cluster --service my-service --desired-count 3

# Force new deployment
aws ecs update-service --cluster my-cluster --service my-service --force-new-deployment

# Wait for stable
aws ecs wait services-stable --cluster my-cluster --services my-service
```

### ECS Scaling Actions

| Action | Description | Desired Count |
|--------|-------------|---------------|
| `scale_up` | Increase by 1 | current + 1 |
| `scale_down` | Decrease by 1 | current - 1 (min 0) |
| `scale_to` | Set specific count | user-specified |
| `stop` | Scale to zero | 0 |
| `restart` | Force new deployment | unchanged |

---

## Completion Sign-off

| Phase | Status | Date | Completed By |
|-------|--------|------|--------------|
| Phase 1: AWS Setup | ☐ | | |
| Phase 2: Harness Setup | ☐ | | |
| Phase 3: Testing | ☐ | | |
| Phase 4: Production Ready | ☐ | | |

**Implementation Complete:** ☐
