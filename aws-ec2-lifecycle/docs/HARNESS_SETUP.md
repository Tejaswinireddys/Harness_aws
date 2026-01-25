# Harness Setup Guide for EC2 Lifecycle Management

## Overview
Complete step-by-step guide to configure Harness for AWS EC2 instance lifecycle management.

---

## Step 1: Create Organization Secrets

### 1.1 Navigate to Organization Settings
1. Log in to Harness Platform
2. Go to **Account Settings** → **Organizations**
3. Select your organization
4. Go to **Organization Settings** → **Secrets**

### 1.2 Create AWS Access Key Secret

1. Click **+ New Secret** → **Text**
2. Configure:
   - **Name**: `aws_access_key_id`
   - **Identifier**: `aws_access_key_id`
   - **Description**: `AWS Access Key for EC2 Lifecycle Management`
   - **Secret Value**: `<Your AWS Access Key ID>`
   - **Tags**: `aws`, `ec2`, `credentials`
3. Click **Save**

### 1.3 Create AWS Secret Access Key Secret

1. Click **+ New Secret** → **Text**
2. Configure:
   - **Name**: `aws_secret_access_key`
   - **Identifier**: `aws_secret_access_key`
   - **Description**: `AWS Secret Access Key for EC2 Lifecycle Management`
   - **Secret Value**: `<Your AWS Secret Access Key>`
   - **Tags**: `aws`, `ec2`, `credentials`
3. Click **Save**

### Secret Reference Format:
```yaml
# Organization level secrets are referenced as:
<+secrets.getValue("org.aws_access_key_id")>
<+secrets.getValue("org.aws_secret_access_key")>
```

---

## Step 2: Create AWS Cloud Connector

### 2.1 Navigate to Connectors
1. Go to **Project Settings** → **Connectors**
2. Click **+ New Connector** → **Cloud Providers** → **AWS**

### 2.2 Configure AWS Connector

**Overview Tab:**
- **Name**: `aws-ec2-lifecycle-connector`
- **Identifier**: `awsec2lifecycleconnector`
- **Description**: `AWS Connector for EC2 Instance Lifecycle Management`
- **Tags**: `aws`, `ec2`, `lifecycle`

**Credentials Tab:**
- **Credential Type**: `AWS Access Key`
- **Access Key**: Select `org.aws_access_key_id`
- **Secret Key**: Select `org.aws_secret_access_key`

**Connect to Provider Tab:**
- **Connect via**: `Connect through Harness Platform`
- **Test Regions**: Select your primary region (e.g., `us-east-1`)

### 2.3 Connector YAML (Alternative)

```yaml
connector:
  name: aws-ec2-lifecycle-connector
  identifier: awsec2lifecycleconnector
  description: AWS Connector for EC2 Instance Lifecycle Management
  orgIdentifier: your_org_id
  projectIdentifier: your_project_id
  type: Aws
  spec:
    credential:
      type: ManualConfig
      spec:
        accessKey: <+secrets.getValue("org.aws_access_key_id")>
        secretKeyRef: org.aws_secret_access_key
      region: us-east-1
    executeOnDelegate: false
```

---

## Step 3: Create Pipeline Input Templates

### 3.1 Create Input Set for Regions

```yaml
inputSet:
  name: AWS Regions
  identifier: aws_regions
  orgIdentifier: your_org
  projectIdentifier: your_project
  pipeline:
    identifier: ec2_lifecycle_management
    variables:
      - name: aws_region
        type: String
        value: <+input>.allowedValues(us-east-1,us-east-2,us-west-1,us-west-2,eu-west-1,eu-central-1,ap-south-1,ap-southeast-1)
```

### 3.2 Create Input Set for Actions

```yaml
inputSet:
  name: Lifecycle Actions
  identifier: lifecycle_actions
  orgIdentifier: your_org
  projectIdentifier: your_project
  pipeline:
    identifier: ec2_lifecycle_management
    variables:
      - name: action
        type: String
        value: <+input>.allowedValues(list_all,list_running,list_stopped,start,stop)
```

---

## Step 4: Create Custom Stage Templates

### 4.1 Validation Stage Template

Create reusable validation stage:

**Navigation:** Templates → + New Template → Stage

```yaml
template:
  name: AWS Validation Stage
  identifier: aws_validation_stage
  versionLabel: v1.0.0
  type: Stage
  spec:
    type: Custom
    spec:
      execution:
        steps:
          - step:
              type: ShellScript
              name: Validate AWS Credentials
              identifier: validate_aws_credentials
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      echo "╔══════════════════════════════════════════════════════════════╗"
                      echo "║           AWS CREDENTIALS VALIDATION                         ║"
                      echo "╚══════════════════════════════════════════════════════════════╝"

                      # Validate credentials by calling STS
                      CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>&1) || {
                        echo "❌ ERROR: Invalid AWS credentials"
                        echo "Please verify your AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
                        exit 1
                      }

                      ACCOUNT_ID=$(echo $CALLER_IDENTITY | jq -r '.Account')
                      USER_ARN=$(echo $CALLER_IDENTITY | jq -r '.Arn')

                      echo "✅ AWS Credentials Valid"
                      echo "   Account ID: $ACCOUNT_ID"
                      echo "   User ARN:   $USER_ARN"
                      echo ""

                      # Validate region
                      echo "🌍 Validating Region: $AWS_REGION"
                      aws ec2 describe-availability-zones --region $AWS_REGION > /dev/null 2>&1 || {
                        echo "❌ ERROR: Invalid region: $AWS_REGION"
                        exit 1
                      }
                      echo "✅ Region validated successfully"
                envVariables:
                  AWS_ACCESS_KEY_ID: <+secrets.getValue("org.aws_access_key_id")>
                  AWS_SECRET_ACCESS_KEY: <+secrets.getValue("org.aws_secret_access_key")>
                  AWS_REGION: <+pipeline.variables.aws_region>
              timeout: 2m
              failureStrategies:
                - onFailure:
                    errors:
                      - AllErrors
                    action:
                      type: Abort
```

---

## Step 5: Environment Variables Configuration

### 5.1 Create Variable Group (Optional)

For shared variables across pipelines:

```yaml
variableGroup:
  name: EC2 Lifecycle Variables
  identifier: ec2_lifecycle_vars
  orgIdentifier: your_org
  variables:
    - name: default_region
      type: String
      value: us-east-1
    - name: max_instances_per_action
      type: String
      value: "10"
    - name: notification_channel
      type: String
      value: slack
```

---

## Step 6: Notification Configuration

### 6.1 Configure Slack Notification

1. Go to **Project Settings** → **Notifications**
2. Click **+ New Notification**
3. Configure:
   - **Name**: `EC2 Lifecycle Alerts`
   - **Channel**: Slack
   - **Webhook URL**: Your Slack webhook URL
   - **Events**: Pipeline Success, Pipeline Failure, Stage Failure

### 6.2 Configure Email Notification

```yaml
notificationRules:
  - name: EC2 Lifecycle Email
    identifier: ec2_lifecycle_email
    pipelineEvents:
      - type: AllEvents
    notificationMethod:
      type: Email
      spec:
        userGroups:
          - account.platformteam
        recipients:
          - platform-team@yourcompany.com
```

---

## Step 7: RBAC Configuration

### 7.1 Create Custom Role for EC2 Lifecycle

**Navigation:** Account Settings → Access Control → Roles → + New Role

```yaml
role:
  name: EC2 Lifecycle Operator
  identifier: ec2_lifecycle_operator
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

### 7.2 Create User Group

```yaml
userGroup:
  name: EC2 Operators
  identifier: ec2_operators
  users:
    - user1@company.com
    - user2@company.com
  roleBindings:
    - roleIdentifier: ec2_lifecycle_operator
      resourceGroupIdentifier: _all_project_level_resources
```

---

## Step 8: Governance & Policy Setup

### 8.1 OPA Policy for Instance Limits

Create policy to limit number of instances per action:

```rego
package pipeline

deny[msg] {
    input.pipeline.variables.instance_ids != ""
    instance_count := count(split(input.pipeline.variables.instance_ids, ","))
    instance_count > 10
    msg := sprintf("Cannot perform action on more than 10 instances at once. Requested: %d", [instance_count])
}
```

### 8.2 OPA Policy for Production Protection

```rego
package pipeline

deny[msg] {
    input.pipeline.variables.action == "stop"
    input.pipeline.variables.environment == "production"
    not input.pipeline.variables.emergency_override == "true"
    msg := "Stopping production instances requires emergency_override=true"
}
```

---

## Verification Checklist

```
□ Organization secrets created
  □ aws_access_key_id
  □ aws_secret_access_key

□ AWS Connector configured and tested

□ Pipeline templates created
  □ Validation stage template
  □ Discovery stage template
  □ Action stage template
  □ Verification stage template

□ Input sets configured
  □ Region selection
  □ Action selection

□ Notifications configured
  □ Success notifications
  □ Failure notifications

□ RBAC configured
  □ Custom role created
  □ User group assigned

□ Governance policies applied
  □ Instance limit policy
  □ Production protection policy
```

---

## Quick Reference

### Secret References
```yaml
AWS_ACCESS_KEY_ID: <+secrets.getValue("org.aws_access_key_id")>
AWS_SECRET_ACCESS_KEY: <+secrets.getValue("org.aws_secret_access_key")>
```

### Variable References
```yaml
Region: <+pipeline.variables.aws_region>
Action: <+pipeline.variables.action>
Instance IDs: <+pipeline.variables.instance_ids>
Environment: <+pipeline.variables.environment>
```

### Output References
```yaml
# From discovery stage
Running Instances: <+pipeline.stages.discovery.spec.execution.steps.list_instances.output.outputVariables.running_instances>
Stopped Instances: <+pipeline.stages.discovery.spec.execution.steps.list_instances.output.outputVariables.stopped_instances>
Total Count: <+pipeline.stages.discovery.spec.execution.steps.list_instances.output.outputVariables.total_count>
```
