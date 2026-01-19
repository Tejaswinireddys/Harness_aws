# Harness AWS Connection Guide: EC2 and ECS

This guide provides detailed step-by-step instructions for connecting Harness to AWS EC2 instances and ECS servers.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [EC2 Only Setup](#ec2-only-setup-start-here) ← **Start here for EC2**
3. [ECS Setup (Add Later)](#ecs-setup-add-later-when-needed) ← Optional, for ECS
4. [Part 1: Connecting Harness to AWS EC2 Instances](#part-1-connecting-harness-to-aws-ec2-instances)
5. [Part 2: Connecting Harness to AWS ECS Servers](#part-2-connecting-harness-to-aws-ecs-servers)
6. [Verification and Testing](#verification-and-testing)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required AWS Resources
- AWS Account with appropriate permissions
- EC2 instances running and accessible
- ECS cluster created (if using ECS)
- IAM user or role with necessary permissions

### Required Harness Resources
- Harness account with appropriate permissions
- Access to Harness UI (Manager or Admin role)

### Scope Note: Project vs Organization Permissions
If you only have **project-level permissions**, you can still create the AWS connector and all deployment entities as long as:
- You have access to the **Project** and the target **Environment(s)**.
- Your role includes **Connector: Create/Edit** at the **Project** scope.
- You can create **Services**, **Environments**, **Infrastructure Definitions**, and **Workflows/Pipelines** in the Project.

If you do not have those project-level permissions, ask an Org/Admin to grant them or to create the connector at the Org scope and share it with your project.

### AWS IAM Permissions Required

**For EC2:**
- `ec2:DescribeInstances`
- `ec2:DescribeInstanceStatus`
- `ec2:DescribeSecurityGroups`
- `ec2:DescribeVpcs`
- `ec2:DescribeSubnets`
- `ec2:DescribeTags`
- `ec2:RunInstances` (if deploying)
- `ec2:TerminateInstances` (if deploying)
- `ec2:StartInstances`
- `ec2:StopInstances`
- `ec2:RebootInstances`

**For ECS:**
- `ecs:ListClusters`
- `ecs:DescribeClusters`
- `ecs:ListServices`
- `ecs:DescribeServices`
- `ecs:UpdateService`
- `ecs:RegisterTaskDefinition`
- `ecs:ListTaskDefinitions`
- `ecs:DescribeTaskDefinition`
- `ecs:RunTask`
- `ecs:ListTasks`
- `ecs:DescribeTasks`
- `ec2:DescribeInstances` (for ECS instances)
- `iam:PassRole` (for ECS task execution roles)

---

## Complete Step-by-Step: Create IAM Role for Harness

This section provides **beginner-friendly, detailed instructions** to create the IAM role Harness needs.

> **Choose Your Path:**
> - **EC2 Only** — Follow Steps 1, 2, and 3. Skip ECS steps.
> - **EC2 + ECS** — Follow all steps.

---

## EC2 ONLY SETUP (Start Here)

If you only need EC2 connectivity now, follow these steps. You can add ECS later.

---

### Step 1: Find Your AWS Account ID

You will need your 12-digit AWS Account ID.

1. Open your browser and go to **https://console.aws.amazon.com**
2. Sign in with your AWS credentials
3. Click your **account name** in the top-right corner of the console
4. You will see **Account ID: 123456789012** (12 digits)
5. **Write this down** — you will use it later

---

### Step 2: Create the Harness EC2 Role

This is the IAM role Harness will use to connect to your EC2 instances.

1. In the AWS Console, type **IAM** in the search bar at the top
2. Click **IAM** to open the IAM Dashboard
3. In the left menu, click **Roles**
4. Click the **Create role** button (top right)

5. **Select trusted entity**
   - Under "Trusted entity type", select **AWS account**
   - Select **This account** (your own account)
   - Click **Next**

6. **Add permissions — attach managed policy**
   - In the search box, type **AmazonEC2FullAccess**
   - Check the box next to **AmazonEC2FullAccess**
   - You should now have **1 policy selected**
   - Click **Next**

7. **Name, review, and create**
   - Role name: **HarnessEC2Role**
   - Description: `Role for Harness to deploy to EC2 instances`
   - Scroll down and click **Create role**

8. **Confirm creation**
   - You should see a green banner: "Role HarnessEC2Role created"

---

### Step 3: Get the Role ARN for Harness

1. In IAM → Roles, search for **HarnessEC2Role**
2. Click on **HarnessEC2Role** to open it
3. At the top, find **ARN** — it looks like:
   ```
   arn:aws:iam::YOUR_ACCOUNT_ID:role/HarnessEC2Role
   ```
4. Click the **copy icon** next to it
5. **Save this ARN** — you will paste it into Harness

---

### (Alternative) Step 3B: Create Access Keys Instead of Using Role

If you prefer to use Access Keys instead of assuming a role:

1. Go to IAM → **Users**
2. Click **Create user**
3. User name: **harness-ec2-user**
4. Click **Next**
5. Select **Attach policies directly**
6. Search and check: **AmazonEC2FullAccess**
7. Click **Next** → **Create user**
8. Click on the new user → **Security credentials** tab
9. Under "Access keys", click **Create access key**
10. Select **Application running outside AWS**
11. Click **Next** → **Create access key**
12. **IMPORTANT: Copy both values NOW** (you cannot see the secret again):
    - **Access Key ID**: `AKIA...` (20 characters)
    - **Secret Access Key**: `wJalr...` (40 characters)
13. Store these securely

---

## EC2 Setup Complete!

You now have everything needed to connect Harness to EC2. Skip to:
- [Part 1: Connecting Harness to AWS EC2 Instances](#part-1-connecting-harness-to-aws-ec2-instances)

---

---

## ECS SETUP (Add Later When Needed)

When you're ready to add ECS connectivity, follow these additional steps.

---

### Step 4: Check If ecsTaskExecutionRole Already Exists

AWS often creates this role automatically when you first use ECS.

1. In IAM → Roles, search for **ecsTaskExecutionRole**
2. **If you see it in the list:**
   - Click on **ecsTaskExecutionRole**
   - At the top, find **ARN** — it looks like:
     ```
     arn:aws:iam::123456789012:role/ecsTaskExecutionRole
     ```
   - **Copy and save this ARN** — you will need it in Step 6
   - Skip to **Step 6**
3. **If you do NOT see it:**
   - Continue to **Step 5** to create it

---

### Step 5: Create ecsTaskExecutionRole (Only If It Does Not Exist)

1. In IAM → Roles, click **Create role**

2. **Select trusted entity**
   - Under "Trusted entity type", select **AWS service**
   - Under "Use case", find and select **Elastic Container Service**
   - Below that, select **Elastic Container Service Task**
   - Click **Next**

3. **Add permissions**
   - In the search box, type **AmazonECSTaskExecutionRolePolicy**
   - Check the box next to **AmazonECSTaskExecutionRolePolicy**
   - Click **Next**

4. **Name, review, and create**
   - Role name: **ecsTaskExecutionRole** (use this exact name)
   - Description: `Allows ECS tasks to call AWS services on your behalf`
   - Scroll down and click **Create role**

5. **Get the ARN**
   - After creation, click on **ecsTaskExecutionRole** in the roles list
   - At the top, copy the **ARN**:
     ```
     arn:aws:iam::YOUR_ACCOUNT_ID:role/ecsTaskExecutionRole
     ```
   - **Save this ARN** — you will need it in Step 7

---

### Step 6: Add ECS Permissions to Your Harness Role

If you created **HarnessEC2Role** earlier, add ECS permissions to it.

1. In IAM → Roles, search for **HarnessEC2Role**
2. Click on **HarnessEC2Role**
3. Click **Permissions** tab
4. Click **Add permissions** → **Attach policies**
5. Search for **AmazonECSFullAccess**
6. Check the box next to **AmazonECSFullAccess**
7. Click **Add permissions**

You should now see **2 policies** attached:
- AmazonEC2FullAccess
- AmazonECSFullAccess

---

### Step 7: Add the iam:PassRole Permission (Required for ECS)

Harness needs permission to "pass" the ecsTaskExecutionRole to ECS when running tasks.

1. You should be on the **HarnessEC2Role** page (or your Harness role)
   - If not, go to IAM → Roles → click **HarnessEC2Role**

2. Click the **Permissions** tab

3. Click **Add permissions** → **Create inline policy**

4. Click the **JSON** tab

5. **Delete everything** in the text box and paste this:

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::YOUR_ACCOUNT_ID:role/ecsTaskExecutionRole"
    }
  ]
}
```

6. **Replace YOUR_ACCOUNT_ID** with your actual 12-digit account ID from Step 1
   - Example: If your account ID is `111122223333`, the Resource becomes:
     ```
     arn:aws:iam::111122223333:role/ecsTaskExecutionRole
     ```

7. Click **Next**

8. Policy name: **AllowPassRoleForEcsTasks**

9. Click **Create policy**

10. You should now see **3 policies** attached to HarnessEC2Role:
    - AmazonEC2FullAccess
    - AmazonECSFullAccess
    - AllowPassRoleForEcsTasks

---

## ECS Setup Complete!

You can now proceed to:
- [Part 2: Connecting Harness to AWS ECS Servers](#part-2-connecting-harness-to-aws-ecs-servers)

---

---

## Summary: What You Created

### For EC2 Only:

| Item | Name | Purpose |
|------|------|---------|
| IAM Role | **HarnessEC2Role** | Harness uses this to access EC2 |
| Policy | AmazonEC2FullAccess | Allows EC2 operations |

### For EC2 + ECS:

| Item | Name | Purpose |
|------|------|---------|
| IAM Role | **HarnessEC2Role** | Harness uses this to access EC2 and ECS |
| Policy | AmazonEC2FullAccess | Allows EC2 operations |
| Policy | AmazonECSFullAccess | Allows ECS operations |
| Inline Policy | AllowPassRoleForEcsTasks | Allows passing task execution role |
| IAM Role | **ecsTaskExecutionRole** | ECS uses this to pull images and write logs |

---

## Part 1: Connecting Harness to AWS EC2 Instances

### Step 1: Verify Your IAM Setup Is Complete

Before continuing, confirm you have completed the **EC2 Only Setup** above:

- [ ] **HarnessEC2Role** created with **AmazonEC2FullAccess** attached
- [ ] **Role ARN copied** (or Access Key ID + Secret Access Key if using a user)

### Step 2: Configure AWS Cloud Provider in Harness

1. **Log in to Harness**
   - Navigate to your Harness instance URL
   - Sign in with your credentials

2. **Navigate to Cloud Providers**
   - Click on "Setup" in the left navigation menu
   - Click on "Cloud Providers" under "Connectors"
   - **If you only have project-level permissions**: make sure the **Project** is selected in the scope switcher, then create the connector at **Project** scope

3. **Add New Cloud Provider**
   - Click "New Cloud Provider" button
   - Select "AWS" from the list of cloud providers

4. **Configure AWS Connection**

   **If using IAM User (Access Keys):**
   - **Name**: Enter a descriptive name (e.g., `AWS-EC2-Connection`)
   - **Type**: Select "AWS Access Key"
   - **Access Key**: Paste the Access Key ID from Step 1
   - **Secret Key**: Paste the Secret Access Key from Step 1
   - **Region**: Select your primary AWS region (e.g., `us-east-1`)
   - **Use IRSA**: Leave unchecked (unless using IAM Roles for Service Accounts)
   - **Use Assume IAM Role on Delegate**: Leave unchecked (unless using delegate-based role assumption)
   - **Assume IAM Role on Delegate**: Leave empty (unless using)
   - **Test Connection**: Click "Test" to verify connectivity
   - Click "Submit" if test is successful

   **If using IAM Role:**
   - **Name**: Enter a descriptive name (e.g., `AWS-EC2-Connection-Role`)
   - **Type**: Select "IAM Role"
   - **Role ARN**: Paste the Role ARN from Step 1
   - **External ID**: Enter if required (for cross-account access)
   - **Region**: Select your primary AWS region
   - **Use IRSA**: Check if using IAM Roles for Service Accounts
   - **Test Connection**: Click "Test" to verify connectivity
   - Click "Submit" if test is successful

5. **Verify Connection**
   - You should see a success message
   - The cloud provider should appear in your list

### Step 3: Configure EC2 Infrastructure in Harness

1. **Navigate to Infrastructure**
   - Go to your Harness Application
   - Select an Environment (or create a new one)
   - Click on "Infrastructure Definition"
   - **Project-level access**: ensure the Environment and Infrastructure are created in your **Project** scope

2. **Add Infrastructure**
   - Click "Add Infrastructure"
   - Select "AWS" as the infrastructure type
   - Select "AWS EC2" as the deployment type

3. **Configure EC2 Infrastructure**
   - **Name**: Enter infrastructure name (e.g., `EC2-Production`)
   - **Cloud Provider**: Select the AWS cloud provider created in Step 2
   - **Region**: Select the AWS region where your EC2 instances are located
   - **VPC**: Select the VPC ID where your instances are located
   - **Subnet**: Select the subnet ID (optional, can be auto-selected)
   - **Security Group**: Select security group(s) for your instances
   - **Host Connection Type**: Choose one:
     - **SSH**: For SSH-based connections
     - **WinRM**: For Windows instances
     - **AWS Systems Manager (SSM)**: For managed instances
   - **Host Connection Attributes**: Configure based on connection type:
     - **For SSH**: Provide SSH key or credentials
     - **For WinRM**: Provide WinRM credentials
     - **For SSM**: Ensure instances have SSM agent installed
   - Click "Submit"

### Step 4: Set Up Host Connection Attributes

#### For SSH Connection:

1. **Create SSH Connection Attribute**
   - Navigate to Setup → Secrets Management
   - Click "Add Secret"
   - Select "SSH Key File" or "SSH Password"
   - **For SSH Key**:
     - Upload your private key file
     - Enter a name (e.g., `EC2-SSH-Key`)
     - Click "Submit"
   - **For SSH Password**:
     - Enter username and password
     - Enter a name (e.g., `EC2-SSH-Credentials`)
     - Click "Submit"

2. **Attach to Infrastructure**
   - Go back to Infrastructure Definition
   - Edit the infrastructure created in Step 3
   - In "Host Connection Attributes", select the SSH secret created above
   - Save the changes

#### For WinRM Connection:

1. **Create WinRM Connection Attribute**
   - Navigate to Setup → Secrets Management
   - Click "Add Secret"
   - Select "WinRM Credentials"
   - Enter:
     - Username (e.g., `Administrator`)
     - Password
     - Domain (if applicable)
   - Enter a name (e.g., `EC2-WinRM-Credentials`)
   - Click "Submit"

2. **Attach to Infrastructure**
   - Edit the infrastructure
   - In "Host Connection Attributes", select the WinRM secret
   - Save the changes

#### For AWS Systems Manager (SSM):

1. **Ensure SSM Agent is Installed**
   - SSM agent is pre-installed on Amazon Linux 2, Ubuntu 16.04+, and Windows Server 2016+
   - For other instances, install SSM agent manually

2. **Attach IAM Role to EC2 Instances**
   - The EC2 instances need an IAM role with `AmazonSSMManagedInstanceCore` policy
   - Attach this role to your EC2 instances

3. **Configure in Harness**
   - No additional credentials needed
   - Harness will use the IAM role attached to instances

### Step 5: Verify EC2 Instance Discovery

1. **Test Instance Discovery**
   - In the Infrastructure Definition, click "Test"
   - Harness should discover your EC2 instances
   - Verify that your instances appear in the list

2. **Filter Instances (Optional)**
   - You can filter instances by:
     - Tags (e.g., `Environment: Production`)
     - Instance IDs
     - Auto Scaling Groups
   - Configure filters in the Infrastructure Definition

---

## Part 2: Connecting Harness to AWS ECS Servers

### Step 1: Prepare ECS Cluster

1. **Verify ECS Cluster Exists**
   - Log in to AWS Console
   - Navigate to ECS service
   - Verify your ECS cluster exists and is running
   - Note the cluster name and region

2. **Verify ECS Service (if applicable)**
   - If you have existing ECS services, note their names
   - Ensure services are running and healthy

3. **Verify Task Execution Role**
   - Navigate to IAM → Roles
   - Ensure you have a task execution role with:
     - `ecs-tasks.amazonaws.com` as trusted entity
     - `AmazonECSTaskExecutionRolePolicy` attached
   - Note the role ARN

4. **Verify Task Role (if needed)**
   - Ensure you have a task role for your containers
   - Note the role ARN

### Step 2: Configure AWS Cloud Provider for ECS

1. **Use Existing or Create New Cloud Provider**
   - If you already created an AWS cloud provider in Part 1, you can reuse it
   - Or create a new one following the same steps from Part 1, Step 2
   - Ensure the IAM user/role has ECS permissions (listed in Prerequisites)

2. **Verify Permissions**
   - The cloud provider should have permissions for both EC2 and ECS
   - Test the connection to ensure it works

### Step 3: Configure ECS Infrastructure in Harness

1. **Navigate to Infrastructure**
   - Go to your Harness Application
   - Select an Environment (or create a new one)
   - Click on "Infrastructure Definition"
   - **Project-level access**: ensure the Environment and Infrastructure are created in your **Project** scope

2. **Add ECS Infrastructure**
   - Click "Add Infrastructure"
   - Select "AWS" as the infrastructure type
   - Select "AWS ECS" as the deployment type

3. **Configure ECS Infrastructure**
   - **Name**: Enter infrastructure name (e.g., `ECS-Production`)
   - **Cloud Provider**: Select the AWS cloud provider
   - **Region**: Select the AWS region where your ECS cluster is located
   - **Cluster Name**: Enter or select your ECS cluster name
   - **VPC**: Select the VPC ID (optional, for network configuration)
   - **Subnet**: Select subnet IDs (optional)
   - **Security Group**: Select security group(s) (optional)
   - Click "Submit"

### Step 4: Configure ECS Service Definition

1. **Create ECS Service Definition**
   - Navigate to your Service in Harness
   - Click on "Service Definition"
   - Select "AWS ECS" as the deployment type

2. **Configure Task Definition**
   - **Task Definition**: You can either:
     - **Use Existing**: Select an existing task definition from AWS
     - **Create New**: Define a new task definition in Harness
   
3. **If Creating New Task Definition:**
   - **Family**: Enter task definition family name
   - **Network Mode**: Select (bridge, host, awsvpc, none)
   - **Task Role ARN**: Enter the task role ARN (from Step 1.4)
   - **Execution Role ARN**: Enter the task execution role ARN (from Step 1.3)
   - **CPU**: Specify CPU units (e.g., `512` for 0.5 vCPU)
   - **Memory**: Specify memory (e.g., `1024` for 1 GB)
   - **Container Definitions**: Add containers:
     - Click "Add Container"
     - **Name**: Container name
     - **Image**: Docker image (e.g., `nginx:latest`)
     - **CPU**: CPU units for container
     - **Memory**: Memory for container
     - **Port Mappings**: Add port mappings
     - **Environment Variables**: Add if needed
     - **Log Configuration**: Configure CloudWatch logs if needed
     - Click "Submit"

4. **Configure Service Definition**
   - **Service Name**: Enter ECS service name
   - **Desired Count**: Number of tasks to run
   - **Launch Type**: Select (EC2 or Fargate)
   - **Load Balancer**: Configure if using load balancer
   - **Service Discovery**: Configure if using service discovery
   - **Auto Scaling**: Configure if using auto scaling

### Step 5: Configure ECS Deployment Strategy

1. **Navigate to Workflow**
   - Go to your Workflow in Harness
   - Select or create an ECS deployment workflow
   - **Project-level access**: workflows/pipelines are created within your **Project** scope

2. **Configure Deployment Steps**
   - **Setup Container Instances**: Ensure container instances are available
   - **Deploy Containers**: Configure deployment steps
   - **Verify Service**: Add verification steps
   - **Rollback**: Configure rollback steps

3. **Common ECS Deployment Strategies:**
   - **Blue/Green**: Deploy new version alongside old, then switch
   - **Rolling Update**: Gradually replace old tasks with new ones
   - **Canary**: Deploy to subset first, then full deployment

---

## Verification and Testing

This section walks you through testing the AWS connection and running a connectivity test pipeline.

---

### Test 1: Verify AWS Connector Connection

This is the first test to confirm Harness can reach AWS with your credentials.

1. **Open Harness and go to your Project**
   - Log in to Harness
   - In the left sidebar, click **Projects**
   - Click on your project name

2. **Navigate to Connectors**
   - In the left menu, click **Project Setup** (or **Project Settings**)
   - Click **Connectors**

3. **Find your AWS Connector**
   - Look for the AWS connector you created (e.g., `AWS-EC2-Connection`)
   - Click on it to open

4. **Run Connection Test**
   - Click the **Test** button (usually in the top right or at the bottom)
   - Wait for the test to complete

5. **Check the result**
   - ✅ **Success**: You see "Connection Successful" or a green checkmark
   - ❌ **Failure**: You see an error message — go to [Troubleshooting](#troubleshooting)

---

### Test 2: Verify EC2 Instance Discovery

This confirms Harness can see your EC2 instances.

1. **Go to your Environment**
   - In the left menu, click **Environments**
   - Click on your environment (e.g., `Production`)

2. **Open Infrastructure Definition**
   - Click on the **Infrastructure Definitions** tab
   - Click on your EC2 infrastructure (e.g., `EC2-Production`)

3. **Test Instance Discovery**
   - Look for a **Test** or **Validate** button
   - Click it
   - Harness will query AWS for EC2 instances

4. **Check the result**
   - ✅ **Success**: You see a list of your EC2 instances
   - ❌ **Failure**: Check your VPC, subnet, region, and security group settings

---

### Test 3: Run a Connectivity Test Pipeline (EC2)

This pipeline runs a simple shell command on your EC2 instance to verify end-to-end connectivity.

#### Step 3.1: Create a New Pipeline

1. In the left menu, click **Pipelines**
2. Click **+ Create Pipeline**
3. Name: **EC2-Connectivity-Test**
4. Click **Start**

#### Step 3.2: Add a Stage

1. Click **+ Add Stage**
2. Stage type: **Deploy** (or **Custom** if available)
3. Stage name: **Test EC2 Connection**
4. Deployment type: **Secure Shell (SSH)**
5. Click **Set Up Stage**

#### Step 3.3: Configure the Service

1. Click **+ Add Service** (or select an existing one)
2. Service name: **connectivity-test-service**
3. Deployment type: **Secure Shell**
4. For artifacts, you can skip or add a dummy artifact
5. Click **Save**

#### Step 3.4: Configure the Environment and Infrastructure

1. Click on the **Environment** tab in the stage
2. Select your environment (e.g., `Production`)
3. Select your EC2 infrastructure definition
4. Harness should show your EC2 instances

#### Step 3.5: Add a Shell Script Step

1. In the **Execution** tab, click **+ Add Step**
2. Step type: **Shell Script**
3. Name: **Echo Test**
4. Script type: **Bash**
5. Script:
```
#!/bin/bash
echo "=== Connectivity Test ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "User: $(whoami)"
echo "=== Test Successful ==="
```
6. Click **Apply Changes**

#### Step 3.6: Save and Run the Pipeline

1. Click **Save** (top right)
2. Click **Run**
3. In the "Run Pipeline" dialog, click **Run Pipeline**

#### Step 3.7: Check the Results

1. Watch the pipeline execution
2. Click on the **Echo Test** step when it completes
3. Expand the **Output** section
4. You should see:
```
=== Connectivity Test ===
Hostname: ip-10-0-1-123
Date: Mon Jan 19 12:00:00 UTC 2026
User: ec2-user
=== Test Successful ===
```

5. **If successful**: Your Harness-to-EC2 connection is working!
6. **If failed**: Check the error message and go to [Troubleshooting](#troubleshooting)

---

### Test 4: Run a Connectivity Test Pipeline (ECS)

This pipeline deploys a simple container to verify ECS connectivity.

#### Step 4.1: Create a New Pipeline

1. Click **Pipelines** → **+ Create Pipeline**
2. Name: **ECS-Connectivity-Test**
3. Click **Start**

#### Step 4.2: Add an ECS Stage

1. Click **+ Add Stage**
2. Stage type: **Deploy**
3. Stage name: **Test ECS Connection**
4. Deployment type: **Amazon ECS**
5. Click **Set Up Stage**

#### Step 4.3: Configure the Service

1. Click **+ Add Service**
2. Service name: **ecs-test-service**
3. Deployment type: **Amazon ECS**
4. For the container image, use: **nginx:latest** (a simple public image)
5. Click **Save**

#### Step 4.4: Configure the Environment and Infrastructure

1. Select your environment
2. Select your ECS infrastructure definition
3. Confirm the cluster name appears

#### Step 4.5: Configure the Execution

1. In **Execution**, add an **ECS Rolling Deploy** step (or use the default)
2. Use default settings

#### Step 4.6: Save and Run

1. Click **Save**
2. Click **Run** → **Run Pipeline**

#### Step 4.7: Verify in AWS Console

1. After the pipeline completes, open AWS Console
2. Go to **ECS** → **Clusters** → your cluster
3. Click on **Tasks** tab
4. You should see a running task with the nginx container

5. **If successful**: Your Harness-to-ECS connection is working!
6. **If failed**: Check the error in Harness and go to [Troubleshooting](#troubleshooting)

---

### Quick Connectivity Test Summary

| Test | What It Proves |
|------|----------------|
| Connector Test | Harness can authenticate to AWS |
| Infrastructure Test | Harness can discover EC2 instances |
| EC2 Pipeline | Harness can SSH to EC2 and run commands |
| ECS Pipeline | Harness can deploy containers to ECS |

---

## Troubleshooting

### Common EC2 Issues

**Issue: Cannot discover EC2 instances**
- **Solution**: 
  - Verify IAM permissions are correct
  - Check that instances are in the correct region
  - Verify VPC and subnet selections
  - Check security group rules allow connections

**Issue: Cannot connect via SSH**
- **Solution**:
  - Verify SSH key is correct
  - Check security group allows SSH (port 22)
  - Verify instance is running
  - Check network connectivity

**Issue: Cannot connect via SSM**
- **Solution**:
  - Verify SSM agent is installed and running
  - Check IAM role has `AmazonSSMManagedInstanceCore` policy
  - Verify instances are registered in Systems Manager

### Common ECS Issues

**Issue: Cannot access ECS cluster**
- **Solution**:
  - Verify IAM permissions include ECS permissions
  - Check cluster name is correct
  - Verify region is correct
  - Check cluster is in active state

**Issue: Task fails to start**
- **Solution**:
  - Verify task execution role has correct permissions
  - Check task role ARN is correct
  - Verify container image is accessible
  - Check resource limits (CPU/memory)
  - Review CloudWatch logs

**Issue: Service update fails**
- **Solution**:
  - Verify service has enough capacity
  - Check auto scaling limits
  - Verify load balancer configuration
  - Check security group rules

### General Troubleshooting Steps

1. **Check Harness Delegate**
   - Ensure Harness delegate is running
   - Verify delegate can reach AWS endpoints
   - Check delegate logs for errors

2. **Verify AWS Credentials**
   - Test AWS credentials using AWS CLI
   - Verify credentials haven't expired
   - Check IAM policy restrictions

3. **Check Network Connectivity**
   - Verify VPC configuration
   - Check security group rules
   - Verify route tables
   - Test connectivity from delegate to AWS

4. **Review Logs**
   - Check Harness execution logs
   - Review AWS CloudWatch logs
   - Check delegate logs

---

## Additional Resources

### AWS Documentation
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS IAM Documentation](https://docs.aws.amazon.com/iam/)

### Harness Documentation
- [Harness AWS Cloud Provider](https://docs.harness.io/article/4o7o207ih7-add-aws-cloud-provider)
- [Harness EC2 Deployments](https://docs.harness.io/article/ec2-deployments)
- [Harness ECS Deployments](https://docs.harness.io/article/ecs-deployments)

### Best Practices

1. **Security**
   - Use IAM roles instead of access keys when possible
   - Rotate credentials regularly
   - Use least privilege principle for IAM permissions
   - Enable MFA for AWS accounts

2. **Cost Optimization**
   - Use appropriate instance types
   - Implement auto scaling
   - Use spot instances where applicable
   - Monitor and optimize resource usage

3. **High Availability**
   - Deploy across multiple availability zones
   - Use load balancers
   - Implement health checks
   - Set up monitoring and alerting

---

## Summary Checklist

### EC2 Connection Checklist
- [ ] AWS IAM user/role created with EC2 permissions
- [ ] Access keys or role ARN obtained
- [ ] AWS cloud provider configured in Harness
- [ ] Connection tested successfully
- [ ] EC2 infrastructure definition created
- [ ] Host connection attributes configured (SSH/WinRM/SSM)
- [ ] Instances discovered and verified

### ECS Connection Checklist
- [ ] ECS cluster exists and is running
- [ ] Task execution role created and configured
- [ ] Task role created (if needed)
- [ ] AWS cloud provider has ECS permissions
- [ ] ECS infrastructure definition created
- [ ] ECS service definition configured
- [ ] Task definition created or selected
- [ ] Deployment workflow configured
- [ ] Test deployment successful

---

**Document Version**: 1.0  
**Last Updated**: [Current Date]  
**Author**: Harness Configuration Guide
