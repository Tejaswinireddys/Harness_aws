# Harness CD: ECS & EC2 Deployment Patterns Guide

## Complete Guide for ECS EC2-Based and EC2 Shell Script Deployments

---

## Executive Summary

This document extends the enterprise architecture to cover two additional deployment patterns:
1. **ECS EC2-Based Deployments** - Container deployments on ECS with EC2 launch type
2. **EC2 Instance Shell Script Deployments** - Traditional application deployments using shell scripts

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [GitHub Repository Structure](#2-github-repository-structure)
3. [ECS EC2 Deployment Pattern](#3-ecs-ec2-deployment-pattern)
4. [EC2 Shell Script Deployment Pattern](#4-ec2-shell-script-deployment-pattern)
5. [Harness Project Structure](#5-harness-project-structure)
6. [Pipeline Templates](#6-pipeline-templates)
7. [Complete Examples](#7-complete-examples)
8. [Delegate Configuration](#8-delegate-configuration)
9. [Secrets Management](#9-secrets-management)
10. [Best Practices](#10-best-practices)

---

## 1. Architecture Overview

### 1.1 Multi-Pattern Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    HARNESS CD MULTI-PATTERN ARCHITECTURE                         │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                         HARNESS PLATFORM                                 │   │
│  │                                                                          │   │
│  │   Organization: platform-engineering                                     │   │
│  │   ├── Project: rabbitmq-cluster      (Ansible Deployment)               │   │
│  │   ├── Project: webapp-ecs            (ECS EC2 Deployment)               │   │
│  │   └── Project: backend-services      (EC2 Shell Script Deployment)      │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      DELEGATE LAYER                                      │   │
│  │                                                                          │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │   │
│  │  │ Ansible         │  │ ECS/AWS         │  │ Shell Script    │         │   │
│  │  │ Delegate        │  │ Delegate        │  │ Delegate        │         │   │
│  │  │                 │  │                 │  │                 │         │   │
│  │  │ Tags:           │  │ Tags:           │  │ Tags:           │         │   │
│  │  │ - ansible       │  │ - ecs           │  │ - shell         │         │   │
│  │  │ - linux         │  │ - aws           │  │ - linux         │         │   │
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘         │   │
│  └───────────┼────────────────────┼────────────────────┼────────────────────┘   │
│              │                    │                    │                        │
│              ▼                    ▼                    ▼                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                │
│  │  RHEL 8 VMs     │  │  AWS ECS        │  │  AWS EC2        │                │
│  │  (RabbitMQ)     │  │  (Containers)   │  │  (Applications) │                │
│  │                 │  │                 │  │                 │                │
│  │  ┌───┐┌───┐┌───┐│  │  ┌───┐┌───┐┌───┐│  │  ┌───┐┌───┐┌───┐│                │
│  │  │VM1││VM2││VM3││  │  │C1 ││C2 ││C3 ││  │  │EC1││EC2││EC3││                │
│  │  └───┘└───┘└───┘│  │  └───┘└───┘└───┘│  │  └───┘└───┘└───┘│                │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                │
│                                                                                  │
│  Deployment Method:    Deployment Method:    Deployment Method:                │
│  Ansible Playbooks     ECS Service Update    SSH + Shell Scripts               │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Deployment Pattern Comparison

| Aspect | Ansible (RabbitMQ) | ECS EC2 | EC2 Shell Script |
|--------|-------------------|---------|------------------|
| **Target** | RHEL VMs | ECS Cluster | EC2 Instances |
| **Method** | Ansible Playbooks | ECS Task Definition | Shell Scripts |
| **Artifact** | Config Files | Docker Image | JAR/WAR/Binary |
| **Scaling** | Manual | Auto Scaling | Auto Scaling Group |
| **Rollback** | Ansible Rollback | Previous Task Def | Script Rollback |

---

## 2. GitHub Repository Structure

### 2.1 Complete Organization Structure

```
github.com/acme-corp/
│
├── infra-shared/                          # Shared infrastructure code
│   ├── harness-templates/                 # Shared Harness templates
│   ├── scripts/                           # Common shell scripts
│   └── ansible-collections/               # Shared Ansible collections
│
├── rabbitmq-deployment/                   # Ansible-based (existing)
│   └── ansible/
│       ├── inventory/
│       ├── playbooks/
│       └── roles/
│
├── webapp-ecs/                            # ECS EC2 deployment
│   ├── app/                               # Application source code
│   │   ├── Dockerfile
│   │   ├── src/
│   │   └── package.json
│   ├── infra/
│   │   ├── task-definition.json
│   │   ├── service-definition.json
│   │   └── ecs-params.yml
│   ├── scripts/
│   │   ├── build.sh
│   │   ├── deploy.sh
│   │   └── rollback.sh
│   └── .harness/
│       └── pipelines/
│           └── deploy-ecs.yaml
│
└── backend-services/                      # EC2 Shell Script deployment
    ├── app/
    │   ├── target/                        # Built artifacts
    │   └── src/
    ├── scripts/
    │   ├── deploy.sh
    │   ├── rollback.sh
    │   ├── healthcheck.sh
    │   ├── start-service.sh
    │   └── stop-service.sh
    ├── config/
    │   ├── dev/
    │   │   └── application.properties
    │   ├── staging/
    │   │   └── application.properties
    │   └── production/
    │       └── application.properties
    └── .harness/
        └── pipelines/
            └── deploy-ec2.yaml
```

### 2.2 ECS Deployment Repository Structure

```
webapp-ecs/
│
├── README.md
├── .gitignore
│
├── app/                                   # Application code
│   ├── Dockerfile
│   ├── docker-compose.yml                 # Local development
│   ├── package.json
│   ├── src/
│   │   ├── index.js
│   │   └── ...
│   └── tests/
│
├── infra/                                 # ECS Infrastructure definitions
│   ├── task-definitions/
│   │   ├── dev.json
│   │   ├── staging.json
│   │   └── production.json
│   ├── service-definitions/
│   │   ├── dev.json
│   │   ├── staging.json
│   │   └── production.json
│   └── ecs-params/
│       ├── dev.yml
│       ├── staging.yml
│       └── production.yml
│
├── scripts/
│   ├── build-and-push.sh                  # Build Docker image and push to ECR
│   ├── deploy-service.sh                  # Deploy ECS service
│   ├── rollback-service.sh                # Rollback to previous version
│   ├── scale-service.sh                   # Scale ECS service
│   └── healthcheck.sh                     # Service health check
│
└── .harness/
    ├── pipelines/
    │   ├── deploy-ecs-pipeline.yaml
    │   └── rollback-ecs-pipeline.yaml
    └── templates/
        └── ecs-deploy-stage.yaml
```

### 2.3 EC2 Shell Script Repository Structure

```
backend-services/
│
├── README.md
├── .gitignore
│
├── app/                                   # Application code
│   ├── pom.xml                            # Maven build file
│   ├── build.gradle                       # Or Gradle build file
│   ├── src/
│   │   └── main/
│   │       ├── java/
│   │       └── resources/
│   └── target/                            # Build output
│       └── app.jar
│
├── scripts/
│   ├── deploy/
│   │   ├── deploy.sh                      # Main deployment script
│   │   ├── pre-deploy.sh                  # Pre-deployment checks
│   │   ├── post-deploy.sh                 # Post-deployment validation
│   │   └── install-dependencies.sh        # Install required packages
│   ├── service/
│   │   ├── start.sh                       # Start application
│   │   ├── stop.sh                        # Stop application
│   │   ├── restart.sh                     # Restart application
│   │   └── status.sh                      # Check service status
│   ├── rollback/
│   │   ├── rollback.sh                    # Main rollback script
│   │   └── restore-backup.sh              # Restore from backup
│   └── utils/
│       ├── healthcheck.sh                 # Health check script
│       ├── backup.sh                      # Backup current version
│       └── cleanup.sh                     # Cleanup old versions
│
├── config/
│   ├── dev/
│   │   ├── application.properties
│   │   └── logback.xml
│   ├── staging/
│   │   ├── application.properties
│   │   └── logback.xml
│   └── production/
│       ├── application.properties
│       └── logback.xml
│
├── systemd/
│   └── backend-service.service            # Systemd service file
│
└── .harness/
    ├── pipelines/
    │   ├── deploy-ec2-pipeline.yaml
    │   └── rollback-ec2-pipeline.yaml
    └── templates/
        └── ec2-shell-deploy-stage.yaml
```

---

## 3. ECS EC2 Deployment Pattern

### 3.1 ECS Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        ECS EC2 DEPLOYMENT ARCHITECTURE                           │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                          AWS CLOUD                                       │   │
│  │                                                                          │   │
│  │  ┌──────────────────┐          ┌──────────────────────────────────┐    │   │
│  │  │  Amazon ECR      │          │     Application Load Balancer    │    │   │
│  │  │                  │          │                                  │    │   │
│  │  │  webapp:v1.0.0   │          │  ┌──────────┐  ┌──────────┐     │    │   │
│  │  │  webapp:v1.1.0   │          │  │ Target   │  │ Target   │     │    │   │
│  │  │  webapp:latest   │          │  │ Group 1  │  │ Group 2  │     │    │   │
│  │  └────────┬─────────┘          │  │ (Blue)   │  │ (Green)  │     │    │   │
│  │           │                    │  └────┬─────┘  └────┬─────┘     │    │   │
│  │           │ Pull Image         └───────┼─────────────┼───────────┘    │   │
│  │           │                            │             │                 │   │
│  │           ▼                            ▼             ▼                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │   │
│  │  │                    ECS CLUSTER (EC2 Launch Type)                 │  │   │
│  │  │                                                                  │  │   │
│  │  │  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │  │   │
│  │  │  │  EC2 Instance 1  │  │  EC2 Instance 2  │  │ EC2 Instance 3│  │  │   │
│  │  │  │  (t3.large)      │  │  (t3.large)      │  │ (t3.large)    │  │  │   │
│  │  │  │                  │  │                  │  │               │  │  │   │
│  │  │  │  ┌────────────┐  │  │  ┌────────────┐  │  │ ┌───────────┐ │  │  │   │
│  │  │  │  │ Container  │  │  │  │ Container  │  │  │ │ Container │ │  │  │   │
│  │  │  │  │ webapp:v1  │  │  │  │ webapp:v1  │  │  │ │ webapp:v1 │ │  │  │   │
│  │  │  │  │            │  │  │  │            │  │  │ │           │ │  │  │   │
│  │  │  │  │ Port: 8080 │  │  │  │ Port: 8080 │  │  │ │Port: 8080 │ │  │  │   │
│  │  │  │  └────────────┘  │  │  └────────────┘  │  │ └───────────┘ │  │  │   │
│  │  │  │                  │  │                  │  │               │  │  │   │
│  │  │  │  ECS Agent       │  │  ECS Agent       │  │ ECS Agent     │  │  │   │
│  │  │  └──────────────────┘  └──────────────────┘  └───────────────┘  │  │   │
│  │  │                                                                  │  │   │
│  │  │  Auto Scaling Group: Min 2, Max 6, Desired 3                     │  │   │
│  │  └─────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 ECS Task Definition Example

**`infra/task-definitions/production.json`**:

```json
{
  "family": "webapp-production",
  "networkMode": "bridge",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "webapp",
      "image": "${ECR_REPO_URI}:${IMAGE_TAG}",
      "cpu": 512,
      "memory": 1024,
      "memoryReservation": 512,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "hostPort": 0,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "ENVIRONMENT",
          "value": "production"
        },
        {
          "name": "LOG_LEVEL",
          "value": "INFO"
        }
      ],
      "secrets": [
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db-password"
        },
        {
          "name": "API_KEY",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/api-key"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/webapp-production",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "webapp"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ],
  "requiresCompatibilities": ["EC2"],
  "tags": [
    {
      "key": "Environment",
      "value": "production"
    },
    {
      "key": "Application",
      "value": "webapp"
    }
  ]
}
```

### 3.3 ECS Deployment Scripts

**`scripts/deploy-service.sh`**:

```bash
#!/bin/bash
set -e

# =============================================================================
# ECS Service Deployment Script
# =============================================================================

# Configuration
CLUSTER_NAME="${ECS_CLUSTER_NAME}"
SERVICE_NAME="${ECS_SERVICE_NAME}"
TASK_DEFINITION_FILE="${TASK_DEFINITION_FILE}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ECR_REPO_URI="${ECR_REPO_URI}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "═══════════════════════════════════════════════════════════════"
echo "       ECS Service Deployment"
echo "═══════════════════════════════════════════════════════════════"
echo "Cluster: ${CLUSTER_NAME}"
echo "Service: ${SERVICE_NAME}"
echo "Image Tag: ${IMAGE_TAG}"
echo "═══════════════════════════════════════════════════════════════"

# Step 1: Substitute variables in task definition
echo "Step 1: Preparing task definition..."
TASK_DEF_JSON=$(cat ${TASK_DEFINITION_FILE} | \
  sed "s|\${ECR_REPO_URI}|${ECR_REPO_URI}|g" | \
  sed "s|\${IMAGE_TAG}|${IMAGE_TAG}|g")

# Step 2: Register new task definition
echo "Step 2: Registering new task definition..."
NEW_TASK_DEF=$(aws ecs register-task-definition \
  --cli-input-json "${TASK_DEF_JSON}" \
  --region ${AWS_REGION} \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "New task definition: ${NEW_TASK_DEF}"

# Step 3: Get current task definition for rollback
echo "Step 3: Saving current task definition for rollback..."
CURRENT_TASK_DEF=$(aws ecs describe-services \
  --cluster ${CLUSTER_NAME} \
  --services ${SERVICE_NAME} \
  --region ${AWS_REGION} \
  --query 'services[0].taskDefinition' \
  --output text)

echo "Current task definition (for rollback): ${CURRENT_TASK_DEF}"
echo "${CURRENT_TASK_DEF}" > /tmp/rollback-task-def.txt

# Step 4: Update service with new task definition
echo "Step 4: Updating ECS service..."
aws ecs update-service \
  --cluster ${CLUSTER_NAME} \
  --service ${SERVICE_NAME} \
  --task-definition ${NEW_TASK_DEF} \
  --region ${AWS_REGION} \
  --force-new-deployment

# Step 5: Wait for service stability
echo "Step 5: Waiting for service to stabilize..."
aws ecs wait services-stable \
  --cluster ${CLUSTER_NAME} \
  --services ${SERVICE_NAME} \
  --region ${AWS_REGION}

# Step 6: Verify deployment
echo "Step 6: Verifying deployment..."
RUNNING_COUNT=$(aws ecs describe-services \
  --cluster ${CLUSTER_NAME} \
  --services ${SERVICE_NAME} \
  --region ${AWS_REGION} \
  --query 'services[0].runningCount' \
  --output text)

DESIRED_COUNT=$(aws ecs describe-services \
  --cluster ${CLUSTER_NAME} \
  --services ${SERVICE_NAME} \
  --region ${AWS_REGION} \
  --query 'services[0].desiredCount' \
  --output text)

echo "Running tasks: ${RUNNING_COUNT} / Desired: ${DESIRED_COUNT}"

if [ "${RUNNING_COUNT}" -eq "${DESIRED_COUNT}" ]; then
  echo "═══════════════════════════════════════════════════════════════"
  echo "       Deployment Successful!"
  echo "═══════════════════════════════════════════════════════════════"
  exit 0
else
  echo "ERROR: Deployment verification failed!"
  exit 1
fi
```

**`scripts/rollback-service.sh`**:

```bash
#!/bin/bash
set -e

# =============================================================================
# ECS Service Rollback Script
# =============================================================================

CLUSTER_NAME="${ECS_CLUSTER_NAME}"
SERVICE_NAME="${ECS_SERVICE_NAME}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "═══════════════════════════════════════════════════════════════"
echo "       ECS Service Rollback"
echo "═══════════════════════════════════════════════════════════════"

# Option 1: Rollback to saved task definition
if [ -f "/tmp/rollback-task-def.txt" ]; then
  ROLLBACK_TASK_DEF=$(cat /tmp/rollback-task-def.txt)
  echo "Rolling back to: ${ROLLBACK_TASK_DEF}"
else
  # Option 2: Get previous task definition revision
  echo "Finding previous task definition..."

  CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster ${CLUSTER_NAME} \
    --services ${SERVICE_NAME} \
    --region ${AWS_REGION} \
    --query 'services[0].taskDefinition' \
    --output text)

  TASK_FAMILY=$(echo ${CURRENT_TASK_DEF} | cut -d'/' -f2 | cut -d':' -f1)
  CURRENT_REVISION=$(echo ${CURRENT_TASK_DEF} | cut -d':' -f7)
  PREVIOUS_REVISION=$((CURRENT_REVISION - 1))

  ROLLBACK_TASK_DEF="arn:aws:ecs:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):task-definition/${TASK_FAMILY}:${PREVIOUS_REVISION}"
  echo "Rolling back to: ${ROLLBACK_TASK_DEF}"
fi

# Update service with previous task definition
aws ecs update-service \
  --cluster ${CLUSTER_NAME} \
  --service ${SERVICE_NAME} \
  --task-definition ${ROLLBACK_TASK_DEF} \
  --region ${AWS_REGION} \
  --force-new-deployment

# Wait for stability
echo "Waiting for rollback to complete..."
aws ecs wait services-stable \
  --cluster ${CLUSTER_NAME} \
  --services ${SERVICE_NAME} \
  --region ${AWS_REGION}

echo "═══════════════════════════════════════════════════════════════"
echo "       Rollback Completed!"
echo "═══════════════════════════════════════════════════════════════"
```

---

## 4. EC2 Shell Script Deployment Pattern

### 4.1 EC2 Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     EC2 SHELL SCRIPT DEPLOYMENT ARCHITECTURE                     │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      HARNESS DELEGATE                                    │   │
│  │                                                                          │   │
│  │  Delegate VM (with AWS CLI and SSH access)                              │   │
│  │  ├── AWS CLI configured with IAM role                                   │   │
│  │  ├── SSH private key for EC2 instances                                  │   │
│  │  └── Git access for pulling scripts                                     │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │                                             │
│                                   │ SSH (Port 22)                               │
│                                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    TARGET EC2 INSTANCES                                  │   │
│  │                                                                          │   │
│  │  Auto Scaling Group: backend-services-asg                               │   │
│  │                                                                          │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐      │   │
│  │  │  EC2 Instance 1  │  │  EC2 Instance 2  │  │  EC2 Instance 3  │      │   │
│  │  │  backend-svc-01  │  │  backend-svc-02  │  │  backend-svc-03  │      │   │
│  │  │                  │  │                  │  │                  │      │   │
│  │  │  /opt/app/       │  │  /opt/app/       │  │  /opt/app/       │      │   │
│  │  │  ├── current/    │  │  ├── current/    │  │  ├── current/    │      │   │
│  │  │  │   └── app.jar │  │  │   └── app.jar │  │  │   └── app.jar │      │   │
│  │  │  ├── releases/   │  │  ├── releases/   │  │  ├── releases/   │      │   │
│  │  │  │   ├── v1.0/   │  │  │   ├── v1.0/   │  │  │   ├── v1.0/   │      │   │
│  │  │  │   └── v1.1/   │  │  │   └── v1.1/   │  │  │   └── v1.1/   │      │   │
│  │  │  └── config/     │  │  └── config/     │  │  └── config/     │      │   │
│  │  │                  │  │                  │  │                  │      │   │
│  │  │  systemd:        │  │  systemd:        │  │  systemd:        │      │   │
│  │  │  backend-service │  │  backend-service │  │  backend-service │      │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘      │   │
│  │                                                                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      ▲                                          │
│                                      │                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      APPLICATION LOAD BALANCER                           │   │
│  │                                                                          │   │
│  │  ┌─────────────────────────────────────────────────────────────┐       │   │
│  │  │  Target Group: backend-services-tg                          │       │   │
│  │  │  Health Check: /health                                      │       │   │
│  │  │  Port: 8080                                                 │       │   │
│  │  └─────────────────────────────────────────────────────────────┘       │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 EC2 Deployment Scripts

**`scripts/deploy/deploy.sh`**:

```bash
#!/bin/bash
set -e

# =============================================================================
# EC2 Application Deployment Script
# =============================================================================

# Configuration from environment variables
APP_NAME="${APP_NAME:-backend-service}"
DEPLOY_USER="${DEPLOY_USER:-deployer}"
APP_DIR="${APP_DIR:-/opt/app}"
ARTIFACT_URL="${ARTIFACT_URL}"
VERSION="${VERSION:-latest}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
CONFIG_DIR="${CONFIG_DIR:-/opt/app/config}"
TARGET_HOSTS="${TARGET_HOSTS}"  # Comma-separated list of hosts

echo "═══════════════════════════════════════════════════════════════"
echo "       EC2 Application Deployment"
echo "═══════════════════════════════════════════════════════════════"
echo "Application: ${APP_NAME}"
echo "Version: ${VERSION}"
echo "Environment: ${ENVIRONMENT}"
echo "Target Hosts: ${TARGET_HOSTS}"
echo "═══════════════════════════════════════════════════════════════"

# Convert comma-separated hosts to array
IFS=',' read -ra HOSTS <<< "${TARGET_HOSTS}"

# Function to deploy to a single host
deploy_to_host() {
  local HOST=$1
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Deploying to: ${HOST}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Step 1: Create release directory
  ssh -o StrictHostKeyChecking=no ${DEPLOY_USER}@${HOST} << ENDSSH
    set -e
    RELEASE_DIR="${APP_DIR}/releases/${VERSION}"

    echo "Creating release directory: \${RELEASE_DIR}"
    sudo mkdir -p \${RELEASE_DIR}
    sudo chown ${DEPLOY_USER}:${DEPLOY_USER} \${RELEASE_DIR}
ENDSSH

  # Step 2: Download artifact
  ssh -o StrictHostKeyChecking=no ${DEPLOY_USER}@${HOST} << ENDSSH
    set -e
    RELEASE_DIR="${APP_DIR}/releases/${VERSION}"

    echo "Downloading artifact..."
    cd \${RELEASE_DIR}
    curl -fsSL -o app.jar "${ARTIFACT_URL}"

    echo "Artifact downloaded successfully"
ENDSSH

  # Step 3: Copy configuration
  ssh -o StrictHostKeyChecking=no ${DEPLOY_USER}@${HOST} << ENDSSH
    set -e
    RELEASE_DIR="${APP_DIR}/releases/${VERSION}"

    echo "Copying configuration for ${ENVIRONMENT}..."
    cp ${CONFIG_DIR}/${ENVIRONMENT}/application.properties \${RELEASE_DIR}/
    cp ${CONFIG_DIR}/${ENVIRONMENT}/logback.xml \${RELEASE_DIR}/ 2>/dev/null || true
ENDSSH

  # Step 4: Stop current service
  ssh -o StrictHostKeyChecking=no ${DEPLOY_USER}@${HOST} << ENDSSH
    set -e

    echo "Stopping current service..."
    sudo systemctl stop ${APP_NAME} || true

    # Wait for graceful shutdown
    sleep 5
ENDSSH

  # Step 5: Switch symlink
  ssh -o StrictHostKeyChecking=no ${DEPLOY_USER}@${HOST} << ENDSSH
    set -e
    RELEASE_DIR="${APP_DIR}/releases/${VERSION}"

    echo "Switching to new version..."

    # Backup current symlink
    if [ -L "${APP_DIR}/current" ]; then
      PREVIOUS_VERSION=\$(readlink ${APP_DIR}/current)
      echo "\${PREVIOUS_VERSION}" > ${APP_DIR}/.previous_version
    fi

    # Update symlink
    sudo rm -f ${APP_DIR}/current
    sudo ln -s \${RELEASE_DIR} ${APP_DIR}/current

    echo "Symlink updated: ${APP_DIR}/current -> \${RELEASE_DIR}"
ENDSSH

  # Step 6: Start service
  ssh -o StrictHostKeyChecking=no ${DEPLOY_USER}@${HOST} << ENDSSH
    set -e

    echo "Starting service..."
    sudo systemctl start ${APP_NAME}

    # Wait for service to start
    sleep 10

    # Check service status
    if sudo systemctl is-active --quiet ${APP_NAME}; then
      echo "Service started successfully"
    else
      echo "ERROR: Service failed to start"
      sudo journalctl -u ${APP_NAME} -n 50 --no-pager
      exit 1
    fi
ENDSSH

  # Step 7: Health check
  ssh -o StrictHostKeyChecking=no ${DEPLOY_USER}@${HOST} << ENDSSH
    set -e

    echo "Running health check..."
    MAX_RETRIES=10
    RETRY_COUNT=0

    while [ \$RETRY_COUNT -lt \$MAX_RETRIES ]; do
      if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        echo "Health check passed!"
        exit 0
      fi

      RETRY_COUNT=\$((RETRY_COUNT + 1))
      echo "Health check attempt \${RETRY_COUNT}/${MAX_RETRIES} failed, retrying..."
      sleep 5
    done

    echo "ERROR: Health check failed after \${MAX_RETRIES} attempts"
    exit 1
ENDSSH

  echo "✓ Deployment to ${HOST} completed successfully"
}

# Deploy to each host (rolling deployment)
FAILED_HOSTS=()

for HOST in "${HOSTS[@]}"; do
  if deploy_to_host "${HOST}"; then
    echo "✓ ${HOST} - SUCCESS"
  else
    echo "✗ ${HOST} - FAILED"
    FAILED_HOSTS+=("${HOST}")
  fi
done

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "       Deployment Summary"
echo "═══════════════════════════════════════════════════════════════"
echo "Total hosts: ${#HOSTS[@]}"
echo "Failed hosts: ${#FAILED_HOSTS[@]}"

if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
  echo ""
  echo "Failed on: ${FAILED_HOSTS[*]}"
  echo ""
  echo "Deployment completed with errors!"
  exit 1
else
  echo ""
  echo "All deployments successful!"
  exit 0
fi
```

**`scripts/rollback/rollback.sh`**:

```bash
#!/bin/bash
set -e

# =============================================================================
# EC2 Application Rollback Script
# =============================================================================

APP_NAME="${APP_NAME:-backend-service}"
DEPLOY_USER="${DEPLOY_USER:-deployer}"
APP_DIR="${APP_DIR:-/opt/app}"
TARGET_HOSTS="${TARGET_HOSTS}"

echo "═══════════════════════════════════════════════════════════════"
echo "       EC2 Application Rollback"
echo "═══════════════════════════════════════════════════════════════"

IFS=',' read -ra HOSTS <<< "${TARGET_HOSTS}"

rollback_host() {
  local HOST=$1
  echo ""
  echo "Rolling back: ${HOST}"

  ssh -o StrictHostKeyChecking=no ${DEPLOY_USER}@${HOST} << ENDSSH
    set -e

    # Get previous version
    if [ -f "${APP_DIR}/.previous_version" ]; then
      PREVIOUS_VERSION=\$(cat ${APP_DIR}/.previous_version)
    else
      # Find the second newest release
      PREVIOUS_VERSION=\$(ls -t ${APP_DIR}/releases | head -2 | tail -1)
      PREVIOUS_VERSION="${APP_DIR}/releases/\${PREVIOUS_VERSION}"
    fi

    echo "Rolling back to: \${PREVIOUS_VERSION}"

    # Stop service
    sudo systemctl stop ${APP_NAME} || true

    # Update symlink
    sudo rm -f ${APP_DIR}/current
    sudo ln -s \${PREVIOUS_VERSION} ${APP_DIR}/current

    # Start service
    sudo systemctl start ${APP_NAME}

    # Health check
    sleep 10
    if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
      echo "Rollback successful - service is healthy"
    else
      echo "WARNING: Service may not be healthy after rollback"
    fi
ENDSSH
}

for HOST in "${HOSTS[@]}"; do
  rollback_host "${HOST}"
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "       Rollback Completed"
echo "═══════════════════════════════════════════════════════════════"
```

**`scripts/utils/healthcheck.sh`**:

```bash
#!/bin/bash
# =============================================================================
# EC2 Application Health Check Script
# =============================================================================

TARGET_HOSTS="${TARGET_HOSTS}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-http://localhost:8080/health}"
TIMEOUT="${TIMEOUT:-10}"

IFS=',' read -ra HOSTS <<< "${TARGET_HOSTS}"

echo "═══════════════════════════════════════════════════════════════"
echo "       EC2 Application Health Check"
echo "═══════════════════════════════════════════════════════════════"

HEALTHY_COUNT=0
UNHEALTHY_COUNT=0

for HOST in "${HOSTS[@]}"; do
  echo -n "Checking ${HOST}... "

  RESULT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=${TIMEOUT} deployer@${HOST} \
    "curl -sf ${HEALTH_ENDPOINT} 2>/dev/null" || echo "FAILED")

  if [ "${RESULT}" != "FAILED" ]; then
    echo "✓ HEALTHY"
    HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
  else
    echo "✗ UNHEALTHY"
    UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
  fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Health Check Summary:"
echo "  Healthy: ${HEALTHY_COUNT}"
echo "  Unhealthy: ${UNHEALTHY_COUNT}"
echo "  Total: ${#HOSTS[@]}"
echo "═══════════════════════════════════════════════════════════════"

if [ ${UNHEALTHY_COUNT} -gt 0 ]; then
  exit 1
fi
```

### 4.3 Systemd Service File

**`systemd/backend-service.service`**:

```ini
[Unit]
Description=Backend Service Application
After=network.target

[Service]
Type=simple
User=appuser
Group=appuser
WorkingDirectory=/opt/app/current

# Java application configuration
ExecStart=/usr/bin/java \
    -Xms512m \
    -Xmx2048m \
    -XX:+UseG1GC \
    -Dspring.profiles.active=${ENVIRONMENT} \
    -Dlogging.config=/opt/app/current/logback.xml \
    -jar /opt/app/current/app.jar

ExecStop=/bin/kill -TERM $MAINPID

# Restart configuration
Restart=on-failure
RestartSec=10
TimeoutStartSec=120
TimeoutStopSec=30

# Environment
Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk
Environment=ENVIRONMENT=production

# Logging
StandardOutput=append:/var/log/backend-service/stdout.log
StandardError=append:/var/log/backend-service/stderr.log

# Security
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/app /var/log/backend-service

[Install]
WantedBy=multi-user.target
```

---

## 5. Harness Project Structure

### 5.1 Multi-Project Organization

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    HARNESS ORGANIZATION STRUCTURE                                │
│                                                                                  │
│  Organization: platform-engineering                                             │
│  │                                                                               │
│  ├── Project: rabbitmq-cluster                                                  │
│  │   ├── Service: rabbitmq-cluster-service                                      │
│  │   ├── Environments: dev, staging, production                                 │
│  │   ├── Pipelines: deploy-rabbitmq, upgrade-rabbitmq                          │
│  │   └── Deployment Type: Ansible                                               │
│  │                                                                               │
│  ├── Project: webapp-ecs                                                        │
│  │   ├── Service: webapp-ecs-service                                            │
│  │   ├── Environments: dev, staging, production                                 │
│  │   ├── Pipelines: deploy-ecs, rollback-ecs                                   │
│  │   └── Deployment Type: ECS (EC2 Launch Type)                                │
│  │                                                                               │
│  └── Project: backend-services                                                  │
│      ├── Service: backend-api-service                                           │
│      ├── Environments: dev, staging, production                                 │
│      ├── Pipelines: deploy-ec2, rollback-ec2                                   │
│      └── Deployment Type: Shell Script (SSH Deployment)                        │
│                                                                                  │
│  Shared Resources (Org Level):                                                  │
│  ├── Templates: ansible-deploy-stage, ecs-deploy-stage, ec2-shell-deploy-stage │
│  ├── Connectors: github-org-connector, aws-org-connector                        │
│  ├── Secrets: platform-ssh-key, aws-credentials                                 │
│  └── Delegates: platform-delegate (ansible), aws-delegate (ecs/ec2)            │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Creating the ECS Project

```yaml
# Project: webapp-ecs

# Service Definition
service:
  name: webapp-ecs-service
  identifier: webapp_ecs_service
  serviceDefinition:
    type: ECS
    spec:
      manifests:
        - manifest:
            identifier: taskDefinition
            type: EcsTaskDefinition
            spec:
              store:
                type: Github
                spec:
                  connectorRef: github_webapp_ecs
                  gitFetchType: Branch
                  paths:
                    - infra/task-definitions/<+env.name>.json
                  branch: main
        - manifest:
            identifier: serviceDefinition
            type: EcsServiceDefinition
            spec:
              store:
                type: Github
                spec:
                  connectorRef: github_webapp_ecs
                  gitFetchType: Branch
                  paths:
                    - infra/service-definitions/<+env.name>.json
                  branch: main
      artifacts:
        primary:
          primaryArtifactRef: webapp_docker_image
          sources:
            - identifier: webapp_docker_image
              type: Ecr
              spec:
                connectorRef: aws_connector
                imagePath: webapp
                region: us-east-1
                tag: <+input>

# Environment Definition
environment:
  name: production
  identifier: production
  type: Production
  orgIdentifier: platform_engineering
  projectIdentifier: webapp_ecs
  variables:
    - name: cluster_name
      type: String
      value: webapp-production-cluster
    - name: service_name
      type: String
      value: webapp-production-service

# Infrastructure Definition
infrastructureDefinition:
  name: webapp-ecs-infra-production
  identifier: webapp_ecs_infra_production
  type: ECS
  spec:
    connectorRef: aws_connector
    region: us-east-1
    cluster: <+env.variables.cluster_name>
```

### 5.3 Creating the EC2 Shell Script Project

```yaml
# Project: backend-services

# Service Definition
service:
  name: backend-api-service
  identifier: backend_api_service
  serviceDefinition:
    type: Ssh
    spec:
      artifacts:
        primary:
          primaryArtifactRef: backend_jar
          sources:
            - identifier: backend_jar
              type: ArtifactoryRegistry
              spec:
                connectorRef: artifactory_connector
                repository: libs-release-local
                artifactPath: com/acme/backend-service
                tag: <+input>


# Environment Definition
environment:
  name: production
  identifier: production
  type: Production
  variables:
    - name: target_hosts
      type: String
      value: "backend-prod-01,backend-prod-02,backend-prod-03"
    - name: app_name
      type: String
      value: backend-service
    - name: app_dir
      type: String
      value: /opt/app

# Infrastructure Definition (SSH/WinRM)
infrastructureDefinition:
  name: backend-ec2-infra-production
  identifier: backend_ec2_infra_production
  type: SshWinRm
  spec:
    connectorRef: aws_connector
    credentialsRef: backend_ssh_key
    hostConnectionType: Hostname
    hosts:
      - backend-prod-01.internal.acme.com
      - backend-prod-02.internal.acme.com
      - backend-prod-03.internal.acme.com
```

---

## 6. Pipeline Templates

### 6.1 ECS Deploy Stage Template

```yaml
# Template: ECS-Deploy-Stage-Template
# Scope: Organization (platform-engineering)

template:
  name: ECS Deploy Stage Template
  identifier: ecs_deploy_stage_template
  versionLabel: "1.0.0"
  type: Stage
  orgIdentifier: platform_engineering
  spec:
    type: Deployment
    spec:
      deploymentType: ECS
      service:
        serviceRef: <+input>
      environment:
        environmentRef: <+input>
        infrastructureDefinitions:
          - identifier: <+input>
      execution:
        steps:
          - step:
              name: ECS Rolling Deploy
              identifier: ecs_rolling_deploy
              type: EcsRollingDeploy
              spec:
                sameAsAlreadyRunningInstances: false
              timeout: 20m

          - step:
              name: Verify Deployment
              identifier: verify_deployment
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      echo "Verifying ECS deployment..."

                      CLUSTER="<+infra.cluster>"
                      SERVICE="<+env.variables.service_name>"
                      REGION="<+infra.region>"

                      # Get service status
                      STATUS=$(aws ecs describe-services \
                        --cluster ${CLUSTER} \
                        --services ${SERVICE} \
                        --region ${REGION} \
                        --query 'services[0].status' \
                        --output text)

                      RUNNING=$(aws ecs describe-services \
                        --cluster ${CLUSTER} \
                        --services ${SERVICE} \
                        --region ${REGION} \
                        --query 'services[0].runningCount' \
                        --output text)

                      DESIRED=$(aws ecs describe-services \
                        --cluster ${CLUSTER} \
                        --services ${SERVICE} \
                        --region ${REGION} \
                        --query 'services[0].desiredCount' \
                        --output text)

                      echo "Service Status: ${STATUS}"
                      echo "Running: ${RUNNING} / Desired: ${DESIRED}"

                      if [ "${STATUS}" == "ACTIVE" ] && [ "${RUNNING}" -eq "${DESIRED}" ]; then
                        echo "Deployment verified successfully!"
                      else
                        echo "Deployment verification failed!"
                        exit 1
                      fi
                delegateSelectors:
                  - aws-delegate
              timeout: 5m

        rollbackSteps:
          - step:
              name: ECS Rollback
              identifier: ecs_rollback
              type: EcsRollingRollback
              spec: {}
              timeout: 15m
```

### 6.2 EC2 Shell Script Deploy Stage Template

```yaml
# Template: EC2-Shell-Deploy-Stage-Template
# Scope: Organization (platform-engineering)

template:
  name: EC2 Shell Script Deploy Stage Template
  identifier: ec2_shell_deploy_stage_template
  versionLabel: "1.0.0"
  type: Stage
  orgIdentifier: platform_engineering
  spec:
    type: Custom
    spec:
      execution:
        steps:
          - step:
              name: Get Target Hosts
              identifier: get_target_hosts
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      # Option 1: Static hosts from environment variable
                      if [ -n "<+stage.variables.target_hosts>" ]; then
                        TARGET_HOSTS="<+stage.variables.target_hosts>"
                      else
                        # Option 2: Dynamic discovery from AWS
                        TARGET_HOSTS=$(aws ec2 describe-instances \
                          --filters "Name=tag:Application,Values=<+stage.variables.app_name>" \
                                    "Name=tag:Environment,Values=<+stage.variables.environment>" \
                                    "Name=instance-state-name,Values=running" \
                          --query 'Reservations[*].Instances[*].PrivateIpAddress' \
                          --output text | tr '\t' ',')
                      fi

                      echo "Target hosts: ${TARGET_HOSTS}"
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
                outputVariables:
                  - name: TARGET_HOSTS
                    type: String
                    value: ""
              timeout: 5m

          - step:
              name: Clone Deployment Scripts
              identifier: clone_scripts
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      WORK_DIR="/tmp/deploy-<+pipeline.executionId>"

                      rm -rf ${WORK_DIR}
                      git clone <+stage.variables.git_repo_url> ${WORK_DIR}
                      cd ${WORK_DIR}
                      git checkout <+stage.variables.git_branch>

                      echo "Scripts cloned to: ${WORK_DIR}"
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
                outputVariables:
                  - name: WORK_DIR
                    type: String
                    value: /tmp/deploy-<+pipeline.executionId>
              timeout: 5m

          - step:
              name: Setup SSH Key
              identifier: setup_ssh_key
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      mkdir -p ~/.ssh
                      chmod 700 ~/.ssh

                      cat << 'SSHKEY' > ~/.ssh/id_rsa
                      <+secrets.getValue(stage.variables.ssh_key_secret)>
                      SSHKEY

                      chmod 600 ~/.ssh/id_rsa
                      echo "SSH key configured"
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
              timeout: 2m

          - step:
              name: Download Artifact
              identifier: download_artifact
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      ARTIFACT_DIR="/tmp/artifacts"
                      mkdir -p ${ARTIFACT_DIR}

                      echo "Downloading artifact: <+stage.variables.artifact_url>"
                      curl -fsSL -o ${ARTIFACT_DIR}/app.jar "<+stage.variables.artifact_url>"

                      echo "Artifact downloaded to: ${ARTIFACT_DIR}/app.jar"
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
                outputVariables:
                  - name: ARTIFACT_PATH
                    type: String
                    value: /tmp/artifacts/app.jar
              timeout: 10m

          - step:
              name: Deploy to EC2 Instances
              identifier: deploy_to_ec2
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      cd <+execution.steps.clone_scripts.output.outputVariables.WORK_DIR>

                      # Export environment variables
                      export APP_NAME="<+stage.variables.app_name>"
                      export DEPLOY_USER="<+stage.variables.deploy_user>"
                      export APP_DIR="<+stage.variables.app_dir>"
                      export VERSION="<+stage.variables.version>"
                      export ENVIRONMENT="<+stage.variables.environment>"
                      export TARGET_HOSTS="<+execution.steps.get_target_hosts.output.outputVariables.TARGET_HOSTS>"
                      export ARTIFACT_URL="<+stage.variables.artifact_url>"

                      # Run deployment script
                      bash scripts/deploy/deploy.sh
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
              timeout: <+stage.variables.deploy_timeout>
              failureStrategies:
                - onFailure:
                    errors:
                      - AllErrors
                    action:
                      type: StageRollback

          - step:
              name: Health Check
              identifier: health_check
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      cd <+execution.steps.clone_scripts.output.outputVariables.WORK_DIR>

                      export TARGET_HOSTS="<+execution.steps.get_target_hosts.output.outputVariables.TARGET_HOSTS>"
                      export HEALTH_ENDPOINT="<+stage.variables.health_endpoint>"

                      bash scripts/utils/healthcheck.sh
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
              timeout: 5m

        rollbackSteps:
          - step:
              name: Rollback EC2 Instances
              identifier: rollback_ec2
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      cd <+execution.steps.clone_scripts.output.outputVariables.WORK_DIR>

                      export APP_NAME="<+stage.variables.app_name>"
                      export DEPLOY_USER="<+stage.variables.deploy_user>"
                      export APP_DIR="<+stage.variables.app_dir>"
                      export TARGET_HOSTS="<+execution.steps.get_target_hosts.output.outputVariables.TARGET_HOSTS>"

                      bash scripts/rollback/rollback.sh
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
              timeout: 20m

    variables:
      - name: git_repo_url
        type: String
        description: "Git repository URL containing deployment scripts"
        required: true
      - name: git_branch
        type: String
        description: "Git branch"
        required: true
        default: main
      - name: app_name
        type: String
        description: "Application name"
        required: true
      - name: app_dir
        type: String
        description: "Application directory on target hosts"
        required: true
        default: /opt/app
      - name: deploy_user
        type: String
        description: "User for SSH deployment"
        required: true
        default: deployer
      - name: target_hosts
        type: String
        description: "Comma-separated list of target hosts"
        required: false
      - name: environment
        type: String
        description: "Target environment"
        required: true
      - name: version
        type: String
        description: "Version to deploy"
        required: true
      - name: artifact_url
        type: String
        description: "URL to download artifact"
        required: true
      - name: ssh_key_secret
        type: String
        description: "Reference to SSH key secret"
        required: true
      - name: delegate_selector
        type: String
        description: "Delegate selector tag"
        required: true
        default: shell-delegate
      - name: health_endpoint
        type: String
        description: "Health check endpoint"
        required: false
        default: "http://localhost:8080/health"
      - name: deploy_timeout
        type: String
        description: "Deployment timeout"
        required: false
        default: "30m"
```

---

## 7. Complete Examples

### 7.1 Complete ECS Pipeline

```yaml
pipeline:
  name: Deploy WebApp ECS
  identifier: deploy_webapp_ecs
  projectIdentifier: webapp_ecs
  orgIdentifier: platform_engineering
  tags:
    ecs: ""
    webapp: ""

  variables:
    - name: image_tag
      type: String
      description: Docker image tag to deploy
      value: <+input>

  stages:
    # Stage 1: Build and Push Docker Image
    - stage:
        name: Build and Push
        identifier: build_push
        type: CI
        spec:
          cloneCodebase: true
          execution:
            steps:
              - step:
                  name: Build Docker Image
                  identifier: build_docker
                  type: BuildAndPushECR
                  spec:
                    connectorRef: aws_connector
                    region: us-east-1
                    account: "123456789012"
                    imageName: webapp
                    tags:
                      - <+pipeline.variables.image_tag>
                      - latest
                    dockerfile: app/Dockerfile
                    context: app

    # Stage 2: Deploy to Development
    - stage:
        name: Deploy to Development
        identifier: deploy_dev
        type: Deployment
        spec:
          deploymentType: ECS
          service:
            serviceRef: webapp_ecs_service
            serviceInputs:
              serviceDefinition:
                type: ECS
                spec:
                  artifacts:
                    primary:
                      primaryArtifactRef: webapp_docker_image
                      sources:
                        - identifier: webapp_docker_image
                          type: Ecr
                          spec:
                            tag: <+pipeline.variables.image_tag>
          environment:
            environmentRef: development
            infrastructureDefinitions:
              - identifier: webapp_ecs_infra_dev
          execution:
            steps:
              - step:
                  name: ECS Rolling Deploy
                  identifier: ecs_rolling_deploy
                  type: EcsRollingDeploy
                  spec: {}
                  timeout: 15m

              - step:
                  name: Verify Deployment
                  identifier: verify_dev
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          echo "Verifying development deployment..."
                          # Health check logic here
                  timeout: 5m

            rollbackSteps:
              - step:
                  name: Rollback
                  identifier: rollback_dev
                  type: EcsRollingRollback
                  spec: {}

    # Stage 3: Staging Approval
    - stage:
        name: Staging Approval
        identifier: staging_approval
        type: Approval
        spec:
          execution:
            steps:
              - step:
                  name: Approve Staging
                  identifier: approve_staging
                  type: HarnessApproval
                  spec:
                    approvalMessage: "Approve deployment to Staging?"
                    approvers:
                      userGroups:
                        - webapp_team
                      minimumCount: 1
                  timeout: 1d

    # Stage 4: Deploy to Staging
    - stage:
        name: Deploy to Staging
        identifier: deploy_staging
        type: Deployment
        spec:
          deploymentType: ECS
          service:
            serviceRef: webapp_ecs_service
          environment:
            environmentRef: staging
            infrastructureDefinitions:
              - identifier: webapp_ecs_infra_staging
          execution:
            steps:
              - step:
                  name: ECS Rolling Deploy
                  identifier: ecs_rolling_deploy_staging
                  type: EcsRollingDeploy
                  spec: {}
                  timeout: 15m

    # Stage 5: Production Approval
    - stage:
        name: Production Approval
        identifier: production_approval
        type: Approval
        spec:
          execution:
            steps:
              - step:
                  name: Approve Production
                  identifier: approve_production
                  type: HarnessApproval
                  spec:
                    approvalMessage: |
                      PRODUCTION DEPLOYMENT APPROVAL

                      Image: <+pipeline.variables.image_tag>

                      Please provide change ticket.
                    approvers:
                      userGroups:
                        - webapp_tech_leads
                        - platform_managers
                      minimumCount: 2
                      disallowPipelineExecutor: true
                    approverInputs:
                      - name: change_ticket
                        defaultValue: ""
                  timeout: 7d

    # Stage 6: Deploy to Production
    - stage:
        name: Deploy to Production
        identifier: deploy_production
        type: Deployment
        spec:
          deploymentType: ECS
          service:
            serviceRef: webapp_ecs_service
          environment:
            environmentRef: production
            infrastructureDefinitions:
              - identifier: webapp_ecs_infra_production
          execution:
            steps:
              - step:
                  name: ECS Blue Green Deploy
                  identifier: ecs_bg_deploy
                  type: EcsBlueGreenCreateService
                  spec: {}
                  timeout: 20m

              - step:
                  name: ECS Blue Green Swap
                  identifier: ecs_bg_swap
                  type: EcsBlueGreenSwapTargetGroups
                  spec:
                    downsizeOldService: true
                  timeout: 10m

            rollbackSteps:
              - step:
                  name: Rollback Production
                  identifier: rollback_production
                  type: EcsBlueGreenRollback
                  spec: {}
```

### 7.2 Complete EC2 Shell Script Pipeline

```yaml
pipeline:
  name: Deploy Backend Services EC2
  identifier: deploy_backend_ec2
  projectIdentifier: backend_services
  orgIdentifier: platform_engineering
  tags:
    ec2: ""
    shell: ""

  variables:
    - name: artifact_version
      type: String
      description: Artifact version to deploy
      value: <+input>
    - name: git_branch
      type: String
      description: Branch containing deployment scripts
      value: main

  stages:
    # Stage 1: Pre-Flight Checks
    - stage:
        name: Pre-Flight Checks
        identifier: preflight
        type: Custom
        spec:
          execution:
            steps:
              - step:
                  name: Validate Artifact
                  identifier: validate_artifact
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          echo "Validating artifact exists..."

                          ARTIFACT_URL="https://artifactory.acme.com/libs-release/com/acme/backend-service/<+pipeline.variables.artifact_version>/backend-service-<+pipeline.variables.artifact_version>.jar"

                          if curl -sSf -o /dev/null "${ARTIFACT_URL}"; then
                            echo "Artifact validated: ${ARTIFACT_URL}"
                          else
                            echo "ERROR: Artifact not found!"
                            exit 1
                          fi
                    delegateSelectors:
                      - shell-delegate
                  timeout: 5m

    # Stage 2: Deploy to Development
    - stage:
        name: Deploy to Development
        identifier: deploy_dev
        type: Custom
        spec:
          execution:
            steps:
              - step:
                  name: Clone Scripts
                  identifier: clone_scripts_dev
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          WORK_DIR="/tmp/deploy-<+pipeline.executionId>"
                          rm -rf ${WORK_DIR}
                          git clone https://github.com/acme-corp/backend-services.git ${WORK_DIR}
                          cd ${WORK_DIR} && git checkout <+pipeline.variables.git_branch>
                    delegateSelectors:
                      - shell-delegate
                    outputVariables:
                      - name: WORK_DIR
                        type: String
                        value: /tmp/deploy-<+pipeline.executionId>
                  timeout: 5m

              - step:
                  name: Setup SSH
                  identifier: setup_ssh_dev
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          mkdir -p ~/.ssh
                          cat << 'SSHKEY' > ~/.ssh/id_rsa
                          <+secrets.getValue("backend_ssh_key")>
                          SSHKEY
                          chmod 600 ~/.ssh/id_rsa
                    delegateSelectors:
                      - shell-delegate
                  timeout: 2m

              - step:
                  name: Deploy
                  identifier: deploy_dev_step
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          cd <+execution.steps.clone_scripts_dev.output.outputVariables.WORK_DIR>

                          export APP_NAME="backend-service"
                          export DEPLOY_USER="deployer"
                          export APP_DIR="/opt/app"
                          export VERSION="<+pipeline.variables.artifact_version>"
                          export ENVIRONMENT="dev"
                          export TARGET_HOSTS="backend-dev-01,backend-dev-02"
                          export ARTIFACT_URL="https://artifactory.acme.com/libs-release/com/acme/backend-service/${VERSION}/backend-service-${VERSION}.jar"

                          bash scripts/deploy/deploy.sh
                    delegateSelectors:
                      - shell-delegate
                  timeout: 20m
                  failureStrategies:
                    - onFailure:
                        errors:
                          - AllErrors
                        action:
                          type: StageRollback

              - step:
                  name: Health Check
                  identifier: health_check_dev
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          cd <+execution.steps.clone_scripts_dev.output.outputVariables.WORK_DIR>
                          export TARGET_HOSTS="backend-dev-01,backend-dev-02"
                          bash scripts/utils/healthcheck.sh
                    delegateSelectors:
                      - shell-delegate
                  timeout: 5m

            rollbackSteps:
              - step:
                  name: Rollback Dev
                  identifier: rollback_dev
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          cd <+execution.steps.clone_scripts_dev.output.outputVariables.WORK_DIR>
                          export APP_NAME="backend-service"
                          export DEPLOY_USER="deployer"
                          export APP_DIR="/opt/app"
                          export TARGET_HOSTS="backend-dev-01,backend-dev-02"
                          bash scripts/rollback/rollback.sh
                    delegateSelectors:
                      - shell-delegate
                  timeout: 15m

    # Stage 3: Staging Approval
    - stage:
        name: Staging Approval
        identifier: staging_approval
        type: Approval
        spec:
          execution:
            steps:
              - step:
                  name: Approve Staging
                  identifier: approve_staging
                  type: HarnessApproval
                  spec:
                    approvalMessage: "Development deployment successful. Approve staging?"
                    approvers:
                      userGroups:
                        - backend_team
                      minimumCount: 1
                  timeout: 1d

    # Stage 4: Deploy to Staging (similar structure)
    - stage:
        name: Deploy to Staging
        identifier: deploy_staging
        type: Custom
        spec:
          execution:
            steps:
              # ... similar steps with staging hosts

    # Stage 5: Production Approval
    - stage:
        name: Production Approval
        identifier: production_approval
        type: Approval
        spec:
          execution:
            steps:
              - step:
                  name: Approve Production
                  identifier: approve_production
                  type: HarnessApproval
                  spec:
                    approvalMessage: |
                      PRODUCTION DEPLOYMENT APPROVAL

                      Version: <+pipeline.variables.artifact_version>

                      Provide change ticket to proceed.
                    approvers:
                      userGroups:
                        - backend_tech_leads
                        - platform_managers
                      minimumCount: 2
                      disallowPipelineExecutor: true
                    approverInputs:
                      - name: change_ticket
                        defaultValue: ""
                  timeout: 7d

    # Stage 6: Deploy to Production
    - stage:
        name: Deploy to Production
        identifier: deploy_production
        type: Custom
        spec:
          execution:
            steps:
              # ... production deployment steps
```

---

## 8. Delegate Configuration

### 8.1 Delegate Requirements by Pattern

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    DELEGATE REQUIREMENTS BY DEPLOYMENT PATTERN                   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  ANSIBLE DELEGATE (for RabbitMQ)                                         │   │
│  │  Tags: ansible, linux                                                    │   │
│  │                                                                          │   │
│  │  Required Software:                                                      │   │
│  │  ├── Ansible 2.15+                                                       │   │
│  │  ├── Python 3.9+                                                         │   │
│  │  ├── SSH client                                                          │   │
│  │  └── Git                                                                 │   │
│  │                                                                          │   │
│  │  Network Access:                                                         │   │
│  │  └── SSH (22) to target RHEL VMs                                         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  AWS/ECS DELEGATE (for ECS EC2)                                          │   │
│  │  Tags: aws, ecs                                                          │   │
│  │                                                                          │   │
│  │  Required Software:                                                      │   │
│  │  ├── AWS CLI v2                                                          │   │
│  │  ├── Docker CLI (for image builds)                                       │   │
│  │  ├── jq                                                                  │   │
│  │  └── Git                                                                 │   │
│  │                                                                          │   │
│  │  IAM Permissions:                                                        │   │
│  │  ├── ecs:* (ECS service management)                                      │   │
│  │  ├── ecr:* (Container registry)                                          │   │
│  │  ├── ec2:Describe* (Instance info)                                       │   │
│  │  ├── elasticloadbalancing:* (ALB)                                        │   │
│  │  └── logs:* (CloudWatch)                                                 │   │
│  │                                                                          │   │
│  │  Network Access:                                                         │   │
│  │  └── HTTPS (443) to AWS APIs                                             │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  SHELL SCRIPT DELEGATE (for EC2 Shell)                                   │   │
│  │  Tags: shell, linux, ec2                                                 │   │
│  │                                                                          │   │
│  │  Required Software:                                                      │   │
│  │  ├── SSH client                                                          │   │
│  │  ├── AWS CLI v2 (for dynamic host discovery)                             │   │
│  │  ├── curl                                                                │   │
│  │  ├── jq                                                                  │   │
│  │  └── Git                                                                 │   │
│  │                                                                          │   │
│  │  Network Access:                                                         │   │
│  │  ├── SSH (22) to target EC2 instances                                    │   │
│  │  └── HTTPS (443) to artifact repository                                  │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Combined Delegate Dockerfile

```dockerfile
# Dockerfile for multi-purpose delegate
FROM harness/delegate:latest

USER root

# Install common tools
RUN microdnf install -y \
    python3 \
    python3-pip \
    openssh-clients \
    git \
    curl \
    jq \
    unzip \
    && microdnf clean all

# Install Ansible
RUN pip3 install ansible==2.15.*
RUN ansible-galaxy collection install community.general ansible.posix amazon.aws

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# Create directories
RUN mkdir -p /opt/harness-delegate/.ssh \
    && mkdir -p /opt/harness-delegate/scripts

# Switch back to harness user
USER harness

WORKDIR /opt/harness-delegate
```

---

## 9. Secrets Management

### 9.1 Secrets by Project

```yaml
# Organization Level Secrets (Shared)
org_secrets:
  - name: github-pat-token
    type: SecretText
    description: GitHub access token for all projects
  - name: aws-access-key
    type: SecretText
    description: AWS access key (or use IAM role)
  - name: aws-secret-key
    type: SecretText
    description: AWS secret key
  - name: slack-webhook
    type: SecretText
    description: Slack notifications webhook

# Project: webapp-ecs
webapp_ecs_secrets:
  - name: ecr-registry-credentials
    type: SecretText
    description: ECR push/pull credentials
  - name: webapp-db-password
    type: SecretText
    description: Database password for webapp
  - name: webapp-api-key
    type: SecretText
    description: External API key

# Project: backend-services
backend_services_secrets:
  - name: backend-ssh-key
    type: SSHKey
    description: SSH key for EC2 instances
  - name: backend-db-password
    type: SecretText
    description: Database password
  - name: artifactory-credentials
    type: SecretText
    description: Artifactory access token
```

---

## 10. Best Practices

### 10.1 Deployment Pattern Selection Guide

| Use Case | Recommended Pattern | Reason |
|----------|---------------------|--------|
| Containerized microservices | ECS EC2/Fargate | Native container orchestration |
| Legacy Java applications | EC2 Shell Script | Direct control, existing infra |
| Stateful middleware (RabbitMQ, Kafka) | Ansible | Complex configuration management |
| Auto-scaling web apps | ECS with ALB | Built-in scaling, load balancing |
| Batch processing jobs | EC2 Shell Script | Simple, cost-effective |

### 10.2 Security Checklist

- [ ] All secrets stored in Harness Secret Manager
- [ ] SSH keys rotated regularly
- [ ] IAM roles use least privilege
- [ ] Network security groups properly configured
- [ ] Audit logging enabled
- [ ] Approval gates for production

### 10.3 Operational Checklist

- [ ] Health checks configured for all services
- [ ] Rollback procedures tested
- [ ] Monitoring/alerting in place
- [ ] Runbooks documented
- [ ] DR procedures defined

---

## Document Summary

This guide covers three deployment patterns:

| Pattern | Target | Method | Template |
|---------|--------|--------|----------|
| Ansible | RHEL VMs | Playbooks | ansible-deploy-stage |
| ECS EC2 | ECS Cluster | Task Definition | ecs-deploy-stage |
| EC2 Shell | EC2 Instances | Shell Scripts | ec2-shell-deploy-stage |

**Key Files:**
- Deployment scripts for each pattern
- Pipeline templates (reusable)
- Complete pipeline examples
- Delegate configuration

---

**End of Document**
