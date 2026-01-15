# Quick Reference Checklist: Harness AWS Connection

## EC2 Connection - Quick Steps

### 1. AWS Setup (5 minutes)
- [ ] Create IAM user with EC2 permissions OR use existing IAM role
- [ ] Generate Access Key ID and Secret Access Key (if using IAM user)
- [ ] Note Role ARN (if using IAM role)
- [ ] Verify EC2 instances are running and accessible

### 2. Harness Cloud Provider Setup (3 minutes)
- [ ] Navigate: Setup → Cloud Providers → New Cloud Provider → AWS
- [ ] Enter name: `AWS-EC2-Connection`
- [ ] Select type: "AWS Access Key" or "IAM Role"
- [ ] Enter credentials (Access Key + Secret OR Role ARN)
- [ ] Select region
- [ ] Click "Test" → Verify success
- [ ] Click "Submit"

### 3. Harness Infrastructure Setup (5 minutes)
- [ ] Navigate: Application → Environment → Infrastructure Definition
- [ ] Click "Add Infrastructure"
- [ ] Select: AWS → AWS EC2
- [ ] Configure:
  - Name: `EC2-Production`
  - Cloud Provider: Select created provider
  - Region: Select your region
  - VPC: Select VPC ID
  - Host Connection Type: SSH/WinRM/SSM
- [ ] Click "Submit"

### 4. Connection Attributes (3 minutes)
- [ ] For SSH: Create SSH key secret in Setup → Secrets Management
- [ ] For WinRM: Create WinRM credentials secret
- [ ] For SSM: Ensure instances have SSM agent + IAM role
- [ ] Attach secret to infrastructure definition
- [ ] Test connection → Verify instances discovered

**Total Time: ~16 minutes**

---

## ECS Connection - Quick Steps

### 1. AWS Setup (5 minutes)
- [ ] Verify ECS cluster exists and is running
- [ ] Note cluster name and region
- [ ] Verify task execution role exists (with `ecs-tasks.amazonaws.com`)
- [ ] Note task execution role ARN
- [ ] Note task role ARN (if applicable)

### 2. Harness Cloud Provider Setup (2 minutes)
- [ ] Use existing AWS cloud provider OR create new one
- [ ] Ensure provider has ECS permissions
- [ ] Test connection

### 3. Harness Infrastructure Setup (3 minutes)
- [ ] Navigate: Application → Environment → Infrastructure Definition
- [ ] Click "Add Infrastructure"
- [ ] Select: AWS → AWS ECS
- [ ] Configure:
  - Name: `ECS-Production`
  - Cloud Provider: Select provider
  - Region: Select region
  - Cluster Name: Enter cluster name
- [ ] Click "Submit"

### 4. Service Definition Setup (10 minutes)
- [ ] Navigate: Service → Service Definition
- [ ] Select: AWS ECS
- [ ] Configure Task Definition:
  - Family name
  - Network mode
  - Task Role ARN
  - Execution Role ARN
  - CPU and Memory
  - Container definitions (image, ports, env vars)
- [ ] Configure Service:
  - Service name
  - Desired count
  - Launch type (EC2/Fargate)
- [ ] Save

### 5. Workflow Setup (5 minutes)
- [ ] Create ECS deployment workflow
- [ ] Configure deployment steps
- [ ] Test deployment

**Total Time: ~25 minutes**

---

## Required IAM Permissions Summary

### EC2 Minimum Permissions
```
ec2:DescribeInstances
ec2:DescribeInstanceStatus
ec2:DescribeSecurityGroups
ec2:DescribeVpcs
ec2:DescribeSubnets
ec2:DescribeTags
```

### ECS Minimum Permissions
```
ecs:ListClusters
ecs:DescribeClusters
ecs:ListServices
ecs:DescribeServices
ecs:UpdateService
ecs:RegisterTaskDefinition
ecs:DescribeTaskDefinition
iam:PassRole
```

---

## Common Commands

### AWS CLI - Test EC2 Access
```bash
aws ec2 describe-instances --region us-east-1
```

### AWS CLI - Test ECS Access
```bash
aws ecs list-clusters --region us-east-1
aws ecs describe-clusters --clusters your-cluster-name --region us-east-1
```

### Verify SSM Agent
```bash
# On EC2 instance
sudo systemctl status amazon-ssm-agent
```

---

## Troubleshooting Quick Fixes

| Issue | Quick Fix |
|-------|-----------|
| Cannot discover instances | Check IAM permissions, verify region |
| SSH connection fails | Verify security group allows port 22, check key |
| SSM connection fails | Verify SSM agent running, check IAM role |
| ECS cluster not found | Verify cluster name, check region |
| Task fails to start | Check task execution role, verify image exists |
| Service update fails | Check service capacity, verify auto scaling |

---

## Support Contacts

- **Harness Documentation**: https://docs.harness.io
- **AWS Support**: https://console.aws.amazon.com/support
- **Harness Community**: https://community.harness.io
