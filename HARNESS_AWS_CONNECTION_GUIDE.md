# Harness AWS Connection Guide: EC2 and ECS

This guide provides detailed step-by-step instructions for connecting Harness to AWS EC2 instances and ECS servers.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Part 1: Connecting Harness to AWS EC2 Instances](#part-1-connecting-harness-to-aws-ec2-instances)
3. [Part 2: Connecting Harness to AWS ECS Servers](#part-2-connecting-harness-to-aws-ecs-servers)
4. [Verification and Testing](#verification-and-testing)
5. [Troubleshooting](#troubleshooting)

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

### Detailed Steps: Add AWS IAM Permissions

Use this section if you need to **create and attach a custom policy** instead of using AWS managed policies.

#### Step A: Create a Custom IAM Policy

1. **Open IAM Policies**
   - AWS Console → **IAM** → **Policies**
   - Click **Create policy**
2. **Choose JSON**
   - Select the **JSON** tab
   - Paste the policy below (remove EC2 or ECS actions if not needed)
3. **Review and Create**
   - Click **Next**
   - **Name**: `HarnessAWSAccess` (example)
   - **Description**: `Permissions for Harness EC2/ECS deployments`
   - Click **Create policy**

**Sample policy (EC2 + ECS):**
```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2ReadWrite",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:RebootInstances"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSAccess",
      "Effect": "Allow",
      "Action": [
        "ecs:ListClusters",
        "ecs:DescribeClusters",
        "ecs:ListServices",
        "ecs:DescribeServices",
        "ecs:UpdateService",
        "ecs:RegisterTaskDefinition",
        "ecs:ListTaskDefinitions",
        "ecs:DescribeTaskDefinition",
        "ecs:RunTask",
        "ecs:ListTasks",
        "ecs:DescribeTasks"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassRoleForEcsTasks",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::123456789012:role/YourEcsTaskExecutionRole"
    }
  ]
}
```

> Tip: replace the `iam:PassRole` resource with your **actual task execution role ARN**. You can also scope EC2/ECS resources to specific ARNs for least privilege.

#### Step B: Attach the Policy to a User

1. **IAM → Users → select user**
2. **Permissions tab → Add permissions**
3. Choose **Attach policies directly**
4. Search for `HarnessAWSAccess` (or your policy name)
5. Select it → **Next** → **Add permissions**

#### Step C: Attach the Policy to a Role

1. **IAM → Roles → select role**
2. **Permissions tab → Add permissions**
3. Choose **Attach policies**
4. Search for `HarnessAWSAccess` (or your policy name)
5. Select it → **Add permissions**

---

## Part 1: Connecting Harness to AWS EC2 Instances

### Step 1: Create AWS IAM User or Use Existing Role

#### Option A: Create IAM User (Recommended for Testing)

1. **Log in to AWS Console**
   - Navigate to https://console.aws.amazon.com
   - Sign in with your AWS account credentials

2. **Navigate to IAM Service**
   - In the AWS Console, search for "IAM" in the services search bar
   - Click on "IAM" service

3. **Create New User**
   - Click on "Users" in the left navigation pane
   - Click "Add users" button
   - Enter a username (e.g., `harness-ec2-user`)
   - Select "Provide user access to the AWS Management Console" if you need console access (optional)
   - Click "Next"

4. **Attach Permissions**
   - Select "Attach policies directly"
   - Search for and select:
     - `AmazonEC2FullAccess` (or create a custom policy with the permissions listed above)
   - Click "Next"

5. **Review and Create**
   - Review the user details
   - Click "Create user"

6. **Create Access Keys**
   - Click on the newly created user
   - Go to "Security credentials" tab
   - Click "Create access key"
   - Select "Application running outside AWS" as the use case
   - Click "Next"
   - Add a description tag (optional)
   - Click "Create access key"
   - **IMPORTANT**: Copy both the Access Key ID and Secret Access Key immediately
   - Store them securely (you won't be able to see the secret key again)

#### Option B: Use IAM Role (Recommended for Production)

1. **Create IAM Role**
   - Navigate to IAM → Roles
   - Click "Create role"
   - Select "AWS account" as trusted entity type
   - Select "This account" or "Another AWS account" (if using cross-account)
   - Click "Next"

2. **Attach Permissions**
   - Attach the same policies as mentioned in Option A
   - Click "Next"

3. **Name and Create**
   - Enter role name (e.g., `HarnessEC2Role`)
   - Add description
   - Click "Create role"

4. **Note the Role ARN**
   - Copy the Role ARN (e.g., `arn:aws:iam::123456789012:role/HarnessEC2Role`)
   - You'll need this in Harness

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

### Test EC2 Connection

1. **Test Infrastructure**
   - Go to Infrastructure Definition
   - Click "Test" button
   - Verify instances are discovered

2. **Test Deployment**
   - Create a simple deployment workflow
   - Deploy to EC2 infrastructure
   - Verify deployment succeeds

### Test ECS Connection

1. **Test Cluster Connection**
   - Go to ECS Infrastructure Definition
   - Click "Test" button
   - Verify cluster is accessible

2. **Test Service Discovery**
   - Verify ECS services are listed
   - Verify task definitions are accessible

3. **Test Deployment**
   - Create a simple ECS deployment
   - Deploy a test container
   - Verify tasks are running in ECS console

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
