# Harness CD Architecture for Business Unit

## Complete CD Architecture: Jenkins to Harness Migration

---

## Executive Summary

This document provides a complete Continuous Delivery (CD) architecture for a Business Unit (BU) migrating from Jenkins to Harness. It covers project structure, pipeline design, shared resources, and governance for multiple application teams within the BU.

**Migration Goal:** Transition from Jenkins-based CI/CD to Harness CD while maintaining deployment consistency and improving automation capabilities.

---

## Table of Contents

1. [Current State: Jenkins Architecture](#1-current-state-jenkins-architecture)
2. [Target State: Harness Architecture](#2-target-state-harness-architecture)
3. [Jenkins to Harness Mapping](#3-jenkins-to-harness-mapping)
4. [BU Project Structure](#4-bu-project-structure)
5. [Shared Resources Strategy](#5-shared-resources-strategy)
6. [Project Configurations](#6-project-configurations)
7. [Pipeline Architecture](#7-pipeline-architecture)
8. [Delegate Strategy](#8-delegate-strategy)
9. [Secrets Management](#9-secrets-management)
10. [Approval & Governance](#10-approval--governance)
11. [Migration Plan](#11-migration-plan)
12. [Complete Examples](#12-complete-examples)

---

## 1. Current State: Jenkins Architecture

### 1.1 Typical Jenkins Setup

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        CURRENT JENKINS ARCHITECTURE                              │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      JENKINS MASTER                                      │   │
│  │                   (jenkins.bu-name.acme.com)                             │   │
│  │                                                                          │   │
│  │  Folders Structure:                                                      │   │
│  │  └── BU-Name/                                                            │   │
│  │      ├── rabbitmq-cluster/                                               │   │
│  │      │   ├── deploy-dev                                                  │   │
│  │      │   ├── deploy-staging                                              │   │
│  │      │   └── deploy-prod                                                 │   │
│  │      ├── webapp-frontend/                                                │   │
│  │      │   ├── build-and-deploy-dev                                        │   │
│  │      │   ├── deploy-staging                                              │   │
│  │      │   └── deploy-prod                                                 │   │
│  │      ├── backend-api/                                                    │   │
│  │      │   ├── build-and-deploy-dev                                        │   │
│  │      │   ├── deploy-staging                                              │   │
│  │      │   └── deploy-prod                                                 │   │
│  │      └── shared-libraries/                                               │   │
│  │          ├── deploy-ansible.groovy                                       │   │
│  │          ├── deploy-ecs.groovy                                           │   │
│  │          └── deploy-ec2.groovy                                           │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      JENKINS AGENTS                                      │   │
│  │                                                                          │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │   │
│  │  │ Agent: ansible  │  │ Agent: docker   │  │ Agent: aws      │         │   │
│  │  │                 │  │                 │  │                 │         │   │
│  │  │ Labels:         │  │ Labels:         │  │ Labels:         │         │   │
│  │  │ - ansible       │  │ - docker        │  │ - aws           │         │   │
│  │  │ - linux         │  │ - build         │  │ - ecs           │         │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Pain Points:                                                                   │
│  ├── Manual pipeline maintenance per environment                                │
│  ├── Inconsistent approval workflows                                            │
│  ├── Secrets scattered across credentials stores                                │
│  ├── No built-in rollback mechanism                                             │
│  ├── Limited visibility and audit trail                                         │
│  └── Complex Groovy shared libraries                                            │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Typical Jenkins Pipeline (Jenkinsfile)

```groovy
// Current Jenkins Pipeline Example
@Library('shared-libraries') _

pipeline {
    agent { label 'ansible' }

    parameters {
        choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'production'])
        string(name: 'VERSION', defaultValue: 'latest')
    }

    environment {
        ANSIBLE_HOST_KEY_CHECKING = 'False'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Deploy to Dev') {
            when { expression { params.ENVIRONMENT == 'dev' } }
            steps {
                deployAnsible(
                    inventory: 'inventory/dev/hosts.yml',
                    playbook: 'playbooks/deploy.yml'
                )
            }
        }

        stage('Approval for Staging') {
            when { expression { params.ENVIRONMENT == 'staging' } }
            steps {
                input message: 'Deploy to Staging?', submitter: 'qa-team'
            }
        }

        stage('Deploy to Staging') {
            when { expression { params.ENVIRONMENT == 'staging' } }
            steps {
                deployAnsible(
                    inventory: 'inventory/staging/hosts.yml',
                    playbook: 'playbooks/deploy.yml'
                )
            }
        }

        stage('Approval for Production') {
            when { expression { params.ENVIRONMENT == 'production' } }
            steps {
                input message: 'Deploy to Production?', submitter: 'tech-leads,managers'
            }
        }

        stage('Deploy to Production') {
            when { expression { params.ENVIRONMENT == 'production' } }
            steps {
                deployAnsible(
                    inventory: 'inventory/production/hosts.yml',
                    playbook: 'playbooks/deploy.yml'
                )
            }
        }
    }

    post {
        failure {
            slackSend channel: '#deployments', message: "Deployment Failed: ${env.JOB_NAME}"
        }
        success {
            slackSend channel: '#deployments', message: "Deployment Successful: ${env.JOB_NAME}"
        }
    }
}
```

---

## 2. Target State: Harness Architecture

### 2.1 Harness Hierarchy for BU

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        HARNESS ACCOUNT: ACME Corporation                         │
│                                                                                  │
│  Account-Level Resources:                                                       │
│  ├── Default Secret Manager (Harness Built-in)                                  │
│  ├── Account Delegates (shared infrastructure)                                  │
│  ├── Account Templates (company-wide standards)                                 │
│  └── Account Connectors (GitHub Enterprise, Artifactory)                        │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  ORGANIZATION: Business-Unit-Name (e.g., "Digital Platform")            │   │
│  │  (This is YOUR BU's space in Harness)                                    │   │
│  │                                                                          │   │
│  │  Org-Level Resources (Managed by BU Platform Team):                      │   │
│  │  ├── Org Delegates: bu-ansible-delegate, bu-aws-delegate                 │   │
│  │  ├── Org Secrets: bu-ssh-key, bu-aws-credentials, bu-slack-webhook       │   │
│  │  ├── Org Connectors: bu-github-connector, bu-aws-connector               │   │
│  │  ├── Org Templates: ansible-deploy-stage, ecs-deploy-stage, ec2-deploy   │   │
│  │  └── Org Variables: bu_name, cost_center, support_email                  │   │
│  │                                                                          │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │   │
│  │  │                        PROJECTS                                  │    │   │
│  │  │                                                                  │    │   │
│  │  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │    │   │
│  │  │  │ rabbitmq-cluster│  │ webapp-ecs      │  │ backend-services│  │    │   │
│  │  │  │                 │  │                 │  │                 │  │    │   │
│  │  │  │ Type: Ansible   │  │ Type: ECS EC2   │  │ Type: EC2 Shell │  │    │   │
│  │  │  │ Team: Platform  │  │ Team: Frontend  │  │ Team: Backend   │  │    │   │
│  │  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  │    │   │
│  │  │                                                                  │    │   │
│  │  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │    │   │
│  │  │  │ kafka-cluster   │  │ redis-cache     │  │ monitoring-stack│  │    │   │
│  │  │  │                 │  │                 │  │                 │  │    │   │
│  │  │  │ Type: Ansible   │  │ Type: EC2 Shell │  │ Type: Ansible   │  │    │   │
│  │  │  │ Team: Platform  │  │ Team: Platform  │  │ Team: SRE       │  │    │   │
│  │  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  │    │   │
│  │  │                                                                  │    │   │
│  │  └─────────────────────────────────────────────────────────────────┘    │   │
│  │                                                                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Other Organizations (Other BUs - Not your concern):                            │
│  ├── Organization: Mobile-Banking                                               │
│  ├── Organization: Customer-Portal                                              │
│  └── Organization: Data-Analytics                                               │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Visual Comparison: Jenkins vs Harness

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      JENKINS vs HARNESS STRUCTURE                                │
│                                                                                  │
│  JENKINS                              HARNESS                                   │
│  ═══════                              ═══════                                   │
│                                                                                  │
│  Jenkins Master                       Account (Acme Corp)                       │
│       │                                    │                                     │
│       ├── Folder: BU-Name             ────► Organization: BU-Name               │
│       │       │                                 │                                │
│       │       ├── Folder: rabbitmq    ────────► Project: rabbitmq-cluster       │
│       │       │       │                              │                          │
│       │       │       ├── Job: deploy-dev    ──────► Pipeline: deploy-rabbitmq  │
│       │       │       ├── Job: deploy-stg            (with stages for all envs) │
│       │       │       └── Job: deploy-prod                                      │
│       │       │                                                                  │
│       │       ├── Folder: webapp      ────────► Project: webapp-ecs             │
│       │       │       └── Jobs...                    │                          │
│       │       │                                      └── Pipeline: deploy-webapp│
│       │       │                                                                  │
│       │       └── shared-libraries    ────────► Org Templates                   │
│       │                                         (Reusable across projects)      │
│       │                                                                          │
│       └── Credentials                 ────────► Secrets (Account/Org/Project)   │
│                                                                                  │
│  Jenkins Agents                       ────────► Harness Delegates               │
│  (labeled nodes)                               (tagged, scoped)                 │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Jenkins to Harness Mapping

### 3.1 Concept Mapping Table

| Jenkins Concept | Harness Equivalent | Notes |
|-----------------|-------------------|-------|
| Jenkins Master | Harness Account | Cloud-hosted by Harness |
| Folder | Organization / Project | Hierarchical structure |
| Job / Pipeline | Pipeline | Single pipeline for all environments |
| Jenkinsfile | Pipeline YAML | Stored in Harness or Git |
| Shared Library | Templates (Stage/Step) | Reusable at Org/Account level |
| Credentials | Secrets | Scoped (Account/Org/Project) |
| Agent / Node | Delegate | Runs in your infrastructure |
| Agent Label | Delegate Tag/Selector | For routing workloads |
| Parameters | Pipeline Variables / Inputs | Runtime inputs |
| `input` step | Approval Stage | Built-in approval workflow |
| Post Actions | Notification Rules | Slack, Email, PagerDuty |
| Plugins | Connectors / Built-in Steps | Native integrations |
| Freestyle Job | Custom Stage | Shell script execution |
| Multibranch Pipeline | Git Triggers | Branch-based triggering |

### 3.2 Feature Comparison

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      FEATURE COMPARISON: JENKINS vs HARNESS                      │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ FEATURE              │ JENKINS                │ HARNESS                 │   │
│  ├──────────────────────┼────────────────────────┼─────────────────────────┤   │
│  │ Pipeline Definition  │ Jenkinsfile (Groovy)   │ YAML (declarative)      │   │
│  │ Environments         │ Separate jobs/params   │ Built-in Environments   │   │
│  │ Approvals            │ input step (basic)     │ Approval Stage (RBAC)   │   │
│  │ Rollback             │ Manual/custom scripts  │ Built-in rollback steps │   │
│  │ Secrets              │ Credentials plugin     │ Native Secret Manager   │   │
│  │ Audit Trail          │ Build logs only        │ Full audit logging      │   │
│  │ RBAC                 │ Role Strategy plugin   │ Native RBAC             │   │
│  │ Service Definition   │ N/A                    │ Service entity          │   │
│  │ Infrastructure       │ Agent labels           │ Infrastructure Def      │   │
│  │ Templates            │ Shared Libraries       │ Stage/Step Templates    │   │
│  │ GitOps               │ Plugin required        │ Native support          │   │
│  │ Deployment Strategies│ Custom implementation  │ Built-in (Rolling, B/G) │   │
│  │ Notifications        │ Plugin per channel     │ Native multi-channel    │   │
│  │ Governance/Policy    │ Limited                │ OPA Policy as Code      │   │
│  └──────────────────────┴────────────────────────┴─────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Migration Mapping for Common Patterns

#### Jenkins Shared Library → Harness Template

**Jenkins (vars/deployAnsible.groovy):**
```groovy
def call(Map config) {
    withCredentials([sshUserPrivateKey(credentialsId: 'ansible-ssh-key', keyFileVariable: 'SSH_KEY')]) {
        sh """
            export ANSIBLE_HOST_KEY_CHECKING=False
            ansible-playbook -i ${config.inventory} ${config.playbook} \
                --private-key=${SSH_KEY} \
                -e "version=${config.version}"
        """
    }
}
```

**Harness (Org Template: ansible-deploy-step):**
```yaml
template:
  name: Ansible Deploy Step
  identifier: ansible_deploy_step
  type: Step
  spec:
    type: ShellScript
    spec:
      shell: Bash
      source:
        type: Inline
        spec:
          script: |
            #!/bin/bash
            set -e

            # SSH key injected from Harness Secrets
            mkdir -p ~/.ssh
            echo "<+secrets.getValue(step.variables.ssh_key_ref)>" > ~/.ssh/id_rsa
            chmod 600 ~/.ssh/id_rsa

            export ANSIBLE_HOST_KEY_CHECKING=False

            ansible-playbook \
              -i <+step.variables.inventory> \
              <+step.variables.playbook> \
              -e "version=<+step.variables.version>" \
              -v
      delegateSelectors:
        - <+step.variables.delegate_tag>
    timeout: <+step.variables.timeout>

  variables:
    - name: inventory
      type: String
      required: true
    - name: playbook
      type: String
      required: true
    - name: version
      type: String
      required: true
    - name: ssh_key_ref
      type: String
      required: true
    - name: delegate_tag
      type: String
      default: ansible-delegate
    - name: timeout
      type: String
      default: "30m"
```

---

## 4. BU Project Structure

### 4.1 Complete BU Organization Setup

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│              BUSINESS UNIT: Digital-Platform (Your BU)                           │
│                                                                                  │
│  Organization Identifier: digital_platform                                      │
│  Organization Admin: platform-admin@acme.com                                    │
│                                                                                  │
│  ╔═══════════════════════════════════════════════════════════════════════════╗ │
│  ║                    ORGANIZATION-LEVEL RESOURCES                           ║ │
│  ╠═══════════════════════════════════════════════════════════════════════════╣ │
│  ║                                                                           ║ │
│  ║  DELEGATES (Org-scoped):                                                  ║ │
│  ║  ┌─────────────────────────────────────────────────────────────────────┐ ║ │
│  ║  │ Name                    │ Tags              │ Purpose               │ ║ │
│  ║  ├─────────────────────────┼───────────────────┼───────────────────────┤ ║ │
│  ║  │ dp-ansible-delegate     │ ansible, linux    │ Ansible deployments   │ ║ │
│  ║  │ dp-aws-delegate         │ aws, ecs, ec2     │ AWS deployments       │ ║ │
│  ║  │ dp-shell-delegate       │ shell, linux      │ Shell script deploys  │ ║ │
│  ║  └─────────────────────────────────────────────────────────────────────┘ ║ │
│  ║                                                                           ║ │
│  ║  CONNECTORS (Org-level, shared by all projects):                          ║ │
│  ║  ┌─────────────────────────────────────────────────────────────────────┐ ║ │
│  ║  │ Name                    │ Type              │ Purpose               │ ║ │
│  ║  ├─────────────────────────┼───────────────────┼───────────────────────┤ ║ │
│  ║  │ dp-github-connector     │ GitHub            │ Source code repos     │ ║ │
│  ║  │ dp-aws-connector        │ AWS               │ AWS services access   │ ║ │
│  ║  │ dp-artifactory          │ Artifactory       │ Artifact storage      │ ║ │
│  ║  │ dp-ecr-connector        │ AWS ECR           │ Container registry    │ ║ │
│  ║  │ dp-slack-connector      │ Slack             │ Notifications         │ ║ │
│  ║  └─────────────────────────────────────────────────────────────────────┘ ║ │
│  ║                                                                           ║ │
│  ║  SECRETS (Org-level, inherited by all projects):                          ║ │
│  ║  ┌─────────────────────────────────────────────────────────────────────┐ ║ │
│  ║  │ Name                    │ Type              │ Purpose               │ ║ │
│  ║  ├─────────────────────────┼───────────────────┼───────────────────────┤ ║ │
│  ║  │ dp-platform-ssh-key     │ SSH Key           │ Shared infra access   │ ║ │
│  ║  │ dp-aws-access-key       │ Secret Text       │ AWS credentials       │ ║ │
│  ║  │ dp-aws-secret-key       │ Secret Text       │ AWS credentials       │ ║ │
│  ║  │ dp-github-token         │ Secret Text       │ GitHub PAT            │ ║ │
│  ║  │ dp-slack-webhook        │ Secret Text       │ Slack notifications   │ ║ │
│  ║  │ dp-artifactory-token    │ Secret Text       │ Artifactory access    │ ║ │
│  ║  └─────────────────────────────────────────────────────────────────────┘ ║ │
│  ║                                                                           ║ │
│  ║  TEMPLATES (Org-level, reusable by all projects):                         ║ │
│  ║  ┌─────────────────────────────────────────────────────────────────────┐ ║ │
│  ║  │ Name                         │ Type    │ Purpose                    │ ║ │
│  ║  ├──────────────────────────────┼─────────┼────────────────────────────┤ ║ │
│  ║  │ ansible-deploy-stage         │ Stage   │ Ansible deployment         │ ║ │
│  ║  │ ecs-deploy-stage             │ Stage   │ ECS EC2 deployment         │ ║ │
│  ║  │ ec2-shell-deploy-stage       │ Stage   │ EC2 shell script deploy    │ ║ │
│  ║  │ approval-stage               │ Stage   │ Standard approval workflow │ ║ │
│  ║  │ health-check-step            │ Step    │ Generic health check       │ ║ │
│  ║  │ slack-notification-step      │ Step    │ Slack notification         │ ║ │
│  ║  └─────────────────────────────────────────────────────────────────────┘ ║ │
│  ║                                                                           ║ │
│  ║  VARIABLES (Org-level):                                                   ║ │
│  ║  ├── bu_name: "Digital Platform"                                          ║ │
│  ║  ├── cost_center: "CC-12345"                                              ║ │
│  ║  ├── support_email: "dp-support@acme.com"                                 ║ │
│  ║  └── slack_channel: "#dp-deployments"                                     ║ │
│  ║                                                                           ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════╝ │
│                                                                                  │
│  ╔═══════════════════════════════════════════════════════════════════════════╗ │
│  ║                           PROJECTS                                        ║ │
│  ╠═══════════════════════════════════════════════════════════════════════════╣ │
│  ║                                                                           ║ │
│  ║  ┌───────────────────────────────────────────────────────────────────┐   ║ │
│  ║  │ PROJECT 1: rabbitmq-cluster                                       │   ║ │
│  ║  │ ─────────────────────────────────────────────────────────────────│   ║ │
│  ║  │ Description: RabbitMQ 4.x cluster deployment                      │   ║ │
│  ║  │ Deployment Type: Ansible                                          │   ║ │
│  ║  │ Team: Platform Engineering                                        │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Services:                                                         │   ║ │
│  ║  │ └── rabbitmq-cluster-service                                      │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Environments: dev, staging, production                            │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Pipelines:                                                        │   ║ │
│  ║  │ ├── deploy-rabbitmq-cluster                                       │   ║ │
│  ║  │ ├── upgrade-rabbitmq-cluster                                      │   ║ │
│  ║  │ └── rollback-rabbitmq-cluster                                     │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Project Secrets:                                                  │   ║ │
│  ║  │ ├── rabbitmq-admin-password                                       │   ║ │
│  ║  │ ├── rabbitmq-erlang-cookie                                        │   ║ │
│  ║  │ └── rabbitmq-nodes-ssh-key                                        │   ║ │
│  ║  └───────────────────────────────────────────────────────────────────┘   ║ │
│  ║                                                                           ║ │
│  ║  ┌───────────────────────────────────────────────────────────────────┐   ║ │
│  ║  │ PROJECT 2: webapp-ecs                                             │   ║ │
│  ║  │ ─────────────────────────────────────────────────────────────────│   ║ │
│  ║  │ Description: Web application on ECS EC2                           │   ║ │
│  ║  │ Deployment Type: ECS (EC2 Launch Type)                            │   ║ │
│  ║  │ Team: Frontend Engineering                                        │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Services:                                                         │   ║ │
│  ║  │ └── webapp-ecs-service                                            │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Environments: dev, staging, production                            │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Pipelines:                                                        │   ║ │
│  ║  │ ├── build-and-deploy-webapp                                       │   ║ │
│  ║  │ └── rollback-webapp                                               │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Project Secrets:                                                  │   ║ │
│  ║  │ ├── webapp-db-password                                            │   ║ │
│  ║  │ └── webapp-api-key                                                │   ║ │
│  ║  └───────────────────────────────────────────────────────────────────┘   ║ │
│  ║                                                                           ║ │
│  ║  ┌───────────────────────────────────────────────────────────────────┐   ║ │
│  ║  │ PROJECT 3: backend-services                                       │   ║ │
│  ║  │ ─────────────────────────────────────────────────────────────────│   ║ │
│  ║  │ Description: Backend API services on EC2                          │   ║ │
│  ║  │ Deployment Type: EC2 Shell Script                                 │   ║ │
│  ║  │ Team: Backend Engineering                                         │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Services:                                                         │   ║ │
│  ║  │ ├── user-service                                                  │   ║ │
│  ║  │ ├── order-service                                                 │   ║ │
│  ║  │ └── notification-service                                          │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Environments: dev, staging, production                            │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Pipelines:                                                        │   ║ │
│  ║  │ ├── deploy-user-service                                           │   ║ │
│  ║  │ ├── deploy-order-service                                          │   ║ │
│  ║  │ ├── deploy-notification-service                                   │   ║ │
│  ║  │ └── deploy-all-services                                           │   ║ │
│  ║  │                                                                   │   ║ │
│  ║  │ Project Secrets:                                                  │   ║ │
│  ║  │ ├── backend-ssh-key                                               │   ║ │
│  ║  │ ├── backend-db-password                                           │   ║ │
│  ║  │ └── backend-redis-password                                        │   ║ │
│  ║  └───────────────────────────────────────────────────────────────────┘   ║ │
│  ║                                                                           ║ │
│  ║  ┌───────────────────────────────────────────────────────────────────┐   ║ │
│  ║  │ PROJECT 4: kafka-cluster                                          │   ║ │
│  ║  │ ─────────────────────────────────────────────────────────────────│   ║ │
│  ║  │ Description: Kafka cluster deployment                             │   ║ │
│  ║  │ Deployment Type: Ansible                                          │   ║ │
│  ║  │ Team: Platform Engineering                                        │   ║ │
│  ║  └───────────────────────────────────────────────────────────────────┘   ║ │
│  ║                                                                           ║ │
│  ║  ┌───────────────────────────────────────────────────────────────────┐   ║ │
│  ║  │ PROJECT 5: monitoring-stack                                       │   ║ │
│  ║  │ ─────────────────────────────────────────────────────────────────│   ║ │
│  ║  │ Description: Prometheus, Grafana, AlertManager                    │   ║ │
│  ║  │ Deployment Type: Ansible                                          │   ║ │
│  ║  │ Team: SRE                                                         │   ║ │
│  ║  └───────────────────────────────────────────────────────────────────┘   ║ │
│  ║                                                                           ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════╝ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Project Creation Steps

#### Step 1: Request Organization Access (If not already granted)

```
Request to: Harness Account Admin
Subject: Organization Access for Digital Platform BU

Required:
- Organization: digital_platform (create if not exists)
- Role: Organization Admin
- Purpose: Manage CD pipelines for Digital Platform BU applications
```

#### Step 2: Create Organization Resources (One-time Setup)

```yaml
# Organization Setup Checklist

# 1. Create Delegates (via Harness UI or CLI)
delegates:
  - name: dp-ansible-delegate
    type: Kubernetes  # or Docker
    tags: [ansible, linux, digital-platform]
    scope: Organization

  - name: dp-aws-delegate
    type: Kubernetes
    tags: [aws, ecs, ec2, digital-platform]
    scope: Organization

# 2. Create Connectors
connectors:
  - name: dp-github-connector
    type: GitHub
    url: https://github.com/acme-corp
    auth: Token (from org secret)

  - name: dp-aws-connector
    type: AWS
    region: us-east-1
    auth: IAM Role or Access Keys

# 3. Create Org-Level Secrets
secrets:
  - name: dp-platform-ssh-key
    type: SSHKey
  - name: dp-github-token
    type: SecretText
  - name: dp-slack-webhook
    type: SecretText
```

#### Step 3: Create Each Project

For each project in your BU:

```yaml
# Project Creation via Harness UI
# Path: Organization → Projects → + New Project

project:
  name: rabbitmq-cluster
  identifier: rabbitmq_cluster
  orgIdentifier: digital_platform
  description: RabbitMQ 4.x cluster deployment using Ansible
  color: "#0063F7"  # Blue for infrastructure
  modules:
    - CD  # Continuous Delivery

# Repeat for each project:
# - webapp-ecs
# - backend-services
# - kafka-cluster
# - monitoring-stack
```

---

## 5. Shared Resources Strategy

### 5.1 Resource Inheritance Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      RESOURCE INHERITANCE STRATEGY                               │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ ACCOUNT LEVEL (Managed by: Central Platform Team)                       │   │
│  │                                                                          │   │
│  │ Secrets:                                                                 │   │
│  │ └── global-slack-webhook (company-wide alerts)                           │   │
│  │                                                                          │   │
│  │ Connectors:                                                              │   │
│  │ └── global-github-enterprise (github.acme.com)                           │   │
│  │                                                                          │   │
│  │ Templates:                                                               │   │
│  │ └── company-approval-policy (mandatory for production)                   │   │
│  │                                                                          │   │
│  │ Reference Prefix: account.resource_name                                  │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │ Inherited by                               │
│                                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ ORGANIZATION LEVEL (Managed by: BU Platform Team)                       │   │
│  │ Organization: digital_platform                                          │   │
│  │                                                                          │   │
│  │ Secrets:                                                                 │   │
│  │ ├── dp-platform-ssh-key (shared across projects)                        │   │
│  │ ├── dp-aws-credentials                                                  │   │
│  │ └── dp-slack-webhook (BU-specific channel)                              │   │
│  │                                                                          │   │
│  │ Connectors:                                                              │   │
│  │ ├── dp-github-connector                                                 │   │
│  │ ├── dp-aws-connector                                                    │   │
│  │ └── dp-artifactory                                                      │   │
│  │                                                                          │   │
│  │ Templates:                                                               │   │
│  │ ├── ansible-deploy-stage                                                │   │
│  │ ├── ecs-deploy-stage                                                    │   │
│  │ ├── ec2-shell-deploy-stage                                              │   │
│  │ └── standard-approval-stage                                             │   │
│  │                                                                          │   │
│  │ Delegates:                                                               │   │
│  │ ├── dp-ansible-delegate                                                 │   │
│  │ └── dp-aws-delegate                                                     │   │
│  │                                                                          │   │
│  │ Reference Prefix: org.resource_name                                     │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │ Inherited by                               │
│           ┌───────────────────────┼───────────────────────┐                    │
│           ▼                       ▼                       ▼                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                │
│  │ PROJECT:        │  │ PROJECT:        │  │ PROJECT:        │                │
│  │ rabbitmq-cluster│  │ webapp-ecs      │  │ backend-services│                │
│  │                 │  │                 │  │                 │                │
│  │ CAN USE:        │  │ CAN USE:        │  │ CAN USE:        │                │
│  │ • Account secrets│ │ • Account secrets│ │ • Account secrets│               │
│  │ • Org secrets    │  │ • Org secrets    │  │ • Org secrets    │              │
│  │ • Org connectors │  │ • Org connectors │  │ • Org connectors │              │
│  │ • Org templates  │  │ • Org templates  │  │ • Org templates  │              │
│  │ • Org delegates  │  │ • Org delegates  │  │ • Org delegates  │              │
│  │                 │  │                 │  │                 │                │
│  │ CAN CREATE:     │  │ CAN CREATE:     │  │ CAN CREATE:     │                │
│  │ • Project secrets│ │ • Project secrets│ │ • Project secrets│               │
│  │ • Project pipes  │  │ • Project pipes  │  │ • Project pipes  │              │
│  │ • Services      │  │ • Services      │  │ • Services      │                │
│  │ • Environments  │  │ • Environments  │  │ • Environments  │                │
│  │                 │  │                 │  │                 │                │
│  │ Reference:      │  │ Reference:      │  │ Reference:      │                │
│  │ (no prefix)     │  │ (no prefix)     │  │ (no prefix)     │                │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 When to Use Each Scope

| Resource | Account | Organization | Project |
|----------|---------|--------------|---------|
| GitHub PAT (Enterprise) | ✓ | | |
| AWS Credentials (BU) | | ✓ | |
| App-specific passwords | | | ✓ |
| Shared SSH Key | | ✓ | |
| App SSH Key (different access) | | | ✓ |
| Slack Webhook (Company) | ✓ | | |
| Slack Webhook (BU channel) | | ✓ | |
| Deployment Templates | | ✓ | |
| App-specific Templates | | | ✓ |

---

## 6. Project Configurations

### 6.1 Project: rabbitmq-cluster

```yaml
# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT: rabbitmq-cluster
# Deployment Type: Ansible
# ═══════════════════════════════════════════════════════════════════════════════

# SERVICE DEFINITION
service:
  name: rabbitmq-cluster-service
  identifier: rabbitmq_cluster_service
  orgIdentifier: digital_platform
  projectIdentifier: rabbitmq_cluster
  description: RabbitMQ 4.x cluster service
  serviceDefinition:
    type: CustomDeployment
    spec:
      customDeploymentRef:
        templateRef: org.ansible_deploy_template
      variables:
        - name: rabbitmq_version
          type: String
          value: "4.0.2"
        - name: erlang_version
          type: String
          value: "26.2"
        - name: cluster_size
          type: Number
          value: 3

# ENVIRONMENTS
environments:
  - name: Development
    identifier: dev
    type: PreProduction
    variables:
      - name: inventory_file
        value: inventory/dev/hosts.yml
      - name: target_hosts
        value: "rabbitmq-dev-01,rabbitmq-dev-02,rabbitmq-dev-03"

  - name: Staging
    identifier: staging
    type: PreProduction
    variables:
      - name: inventory_file
        value: inventory/staging/hosts.yml
      - name: target_hosts
        value: "rabbitmq-stg-01,rabbitmq-stg-02,rabbitmq-stg-03"

  - name: Production
    identifier: production
    type: Production
    variables:
      - name: inventory_file
        value: inventory/production/hosts.yml
      - name: target_hosts
        value: "rabbitmq-prod-01,rabbitmq-prod-02,rabbitmq-prod-03"

# PROJECT-SPECIFIC SECRETS
secrets:
  - name: rabbitmq-admin-password
    identifier: rabbitmq_admin_password
    type: SecretText

  - name: rabbitmq-erlang-cookie
    identifier: rabbitmq_erlang_cookie
    type: SecretText

  - name: rabbitmq-nodes-ssh-key
    identifier: rabbitmq_nodes_ssh_key
    type: SSHKey
    description: "SSH key specific to RabbitMQ nodes (if different from org key)"

# INFRASTRUCTURE DEFINITIONS
infrastructureDefinitions:
  - name: rabbitmq-infra-dev
    identifier: rabbitmq_infra_dev
    environmentRef: dev
    type: CustomDeployment
    spec:
      variables:
        - name: delegate_selector
          value: dp-ansible-delegate

  - name: rabbitmq-infra-staging
    identifier: rabbitmq_infra_staging
    environmentRef: staging

  - name: rabbitmq-infra-production
    identifier: rabbitmq_infra_production
    environmentRef: production
```

### 6.2 Project: webapp-ecs

```yaml
# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT: webapp-ecs
# Deployment Type: ECS EC2
# ═══════════════════════════════════════════════════════════════════════════════

# SERVICE DEFINITION
service:
  name: webapp-ecs-service
  identifier: webapp_ecs_service
  orgIdentifier: digital_platform
  projectIdentifier: webapp_ecs
  description: Web application running on ECS EC2
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
                  connectorRef: org.dp_github_connector
                  gitFetchType: Branch
                  paths:
                    - infra/task-definitions/<+env.identifier>.json
                  branch: main
        - manifest:
            identifier: serviceDefinition
            type: EcsServiceDefinition
            spec:
              store:
                type: Github
                spec:
                  connectorRef: org.dp_github_connector
                  paths:
                    - infra/service-definitions/<+env.identifier>.json
                  branch: main
      artifacts:
        primary:
          primaryArtifactRef: webapp_image
          sources:
            - identifier: webapp_image
              type: Ecr
              spec:
                connectorRef: org.dp_aws_connector
                imagePath: digital-platform/webapp
                region: us-east-1
                tag: <+input>

# ENVIRONMENTS
environments:
  - name: Development
    identifier: dev
    type: PreProduction
    variables:
      - name: cluster_name
        value: dp-dev-cluster
      - name: service_name
        value: webapp-dev-service
      - name: desired_count
        value: "2"

  - name: Staging
    identifier: staging
    type: PreProduction
    variables:
      - name: cluster_name
        value: dp-staging-cluster
      - name: service_name
        value: webapp-staging-service
      - name: desired_count
        value: "3"

  - name: Production
    identifier: production
    type: Production
    variables:
      - name: cluster_name
        value: dp-production-cluster
      - name: service_name
        value: webapp-production-service
      - name: desired_count
        value: "6"

# PROJECT SECRETS
secrets:
  - name: webapp-db-password
    identifier: webapp_db_password
    type: SecretText

  - name: webapp-api-key
    identifier: webapp_api_key
    type: SecretText

# INFRASTRUCTURE DEFINITIONS
infrastructureDefinitions:
  - name: webapp-ecs-infra-dev
    identifier: webapp_ecs_infra_dev
    environmentRef: dev
    type: ECS
    spec:
      connectorRef: org.dp_aws_connector
      region: us-east-1
      cluster: <+env.variables.cluster_name>

  - name: webapp-ecs-infra-staging
    identifier: webapp_ecs_infra_staging
    environmentRef: staging
    type: ECS
    spec:
      connectorRef: org.dp_aws_connector
      region: us-east-1
      cluster: <+env.variables.cluster_name>

  - name: webapp-ecs-infra-production
    identifier: webapp_ecs_infra_production
    environmentRef: production
    type: ECS
    spec:
      connectorRef: org.dp_aws_connector
      region: us-east-1
      cluster: <+env.variables.cluster_name>
```

### 6.3 Project: backend-services

```yaml
# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT: backend-services
# Deployment Type: EC2 Shell Script
# ═══════════════════════════════════════════════════════════════════════════════

# MULTIPLE SERVICES IN ONE PROJECT
services:
  - name: user-service
    identifier: user_service
    description: User management API service
    serviceDefinition:
      type: Ssh
      spec:
        artifacts:
          primary:
            primaryArtifactRef: user_service_jar
            sources:
              - identifier: user_service_jar
                type: ArtifactoryRegistry
                spec:
                  connectorRef: org.dp_artifactory
                  repository: libs-release
                  artifactPath: com/acme/user-service
                  tag: <+input>

  - name: order-service
    identifier: order_service
    description: Order processing API service
    serviceDefinition:
      type: Ssh
      spec:
        artifacts:
          primary:
            primaryArtifactRef: order_service_jar
            sources:
              - identifier: order_service_jar
                type: ArtifactoryRegistry
                spec:
                  connectorRef: org.dp_artifactory
                  repository: libs-release
                  artifactPath: com/acme/order-service
                  tag: <+input>

  - name: notification-service
    identifier: notification_service
    description: Notification delivery service
    serviceDefinition:
      type: Ssh
      spec:
        artifacts:
          primary:
            primaryArtifactRef: notification_service_jar
            sources:
              - identifier: notification_service_jar
                type: ArtifactoryRegistry
                spec:
                  connectorRef: org.dp_artifactory
                  repository: libs-release
                  artifactPath: com/acme/notification-service
                  tag: <+input>

# ENVIRONMENTS WITH HOST GROUPS
environments:
  - name: Development
    identifier: dev
    type: PreProduction
    variables:
      - name: user_service_hosts
        value: "user-dev-01,user-dev-02"
      - name: order_service_hosts
        value: "order-dev-01,order-dev-02"
      - name: notification_service_hosts
        value: "notif-dev-01"

  - name: Staging
    identifier: staging
    type: PreProduction
    variables:
      - name: user_service_hosts
        value: "user-stg-01,user-stg-02"
      - name: order_service_hosts
        value: "order-stg-01,order-stg-02"
      - name: notification_service_hosts
        value: "notif-stg-01,notif-stg-02"

  - name: Production
    identifier: production
    type: Production
    variables:
      - name: user_service_hosts
        value: "user-prod-01,user-prod-02,user-prod-03"
      - name: order_service_hosts
        value: "order-prod-01,order-prod-02,order-prod-03"
      - name: notification_service_hosts
        value: "notif-prod-01,notif-prod-02"

# PROJECT SECRETS
secrets:
  - name: backend-ssh-key
    identifier: backend_ssh_key
    type: SSHKey

  - name: backend-db-password
    identifier: backend_db_password
    type: SecretText

  - name: backend-redis-password
    identifier: backend_redis_password
    type: SecretText

# INFRASTRUCTURE DEFINITIONS (SSH/WinRM type)
infrastructureDefinitions:
  - name: backend-infra-dev
    identifier: backend_infra_dev
    environmentRef: dev
    type: SshWinRm
    spec:
      connectorRef: org.dp_aws_connector
      credentialsRef: backend_ssh_key

  - name: backend-infra-staging
    identifier: backend_infra_staging
    environmentRef: staging
    type: SshWinRm
    spec:
      connectorRef: org.dp_aws_connector
      credentialsRef: backend_ssh_key

  - name: backend-infra-production
    identifier: backend_infra_production
    environmentRef: production
    type: SshWinRm
    spec:
      connectorRef: org.dp_aws_connector
      credentialsRef: backend_ssh_key
```

---

## 7. Pipeline Architecture

### 7.1 Pipeline Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    STANDARD PIPELINE FLOW (All Projects)                         │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                                                                          │   │
│  │   TRIGGER                                                                │   │
│  │   ├── Manual (Run Pipeline button)                                       │   │
│  │   ├── Git Push (webhook on main/develop branch)                          │   │
│  │   └── Scheduled (cron for specific deployments)                          │   │
│  │                                                                          │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │                                             │
│                                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ STAGE 1: Pre-Flight Checks                                               │   │
│  │ ──────────────────────────                                               │   │
│  │ • Validate inputs                                                        │   │
│  │ • Check artifact exists                                                  │   │
│  │ • Test connectivity to targets                                           │   │
│  │ • Verify delegate health                                                 │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │                                             │
│                                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ STAGE 2: Deploy to Development                                           │   │
│  │ ─────────────────────────────────                                        │   │
│  │ • Clone repository / Download artifact                                   │   │
│  │ • Execute deployment (Ansible/ECS/Shell)                                 │   │
│  │ • Run health checks                                                      │   │
│  │ • Run smoke tests                                                        │   │
│  │                                                                          │   │
│  │ On Failure: Rollback → Notify → Stop                                     │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │                                             │
│                                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ STAGE 3: Staging Approval                                                │   │
│  │ ────────────────────────────                                             │   │
│  │ • Notify team via Slack                                                  │   │
│  │ • Wait for approval (1 approver from team)                               │   │
│  │ • Timeout: 24 hours                                                      │   │
│  │                                                                          │   │
│  │ Approvers: Project Team Members                                          │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │                                             │
│                                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ STAGE 4: Deploy to Staging                                               │   │
│  │ ───────────────────────────                                              │   │
│  │ • Same deployment steps as Dev                                           │   │
│  │ • More comprehensive tests                                               │   │
│  │ • Performance baseline check                                             │   │
│  │                                                                          │   │
│  │ On Failure: Rollback → Notify → Stop                                     │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │                                             │
│                                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ STAGE 5: Production Approval                                             │   │
│  │ ──────────────────────────────                                           │   │
│  │ • Notify stakeholders (Slack + Email)                                    │   │
│  │ • Require 2 approvers (Tech Lead + Manager)                              │   │
│  │ • Executor cannot self-approve                                           │   │
│  │ • Required inputs:                                                       │   │
│  │   - Change Ticket Number (CHG######)                                     │   │
│  │   - Maintenance Window                                                   │   │
│  │   - Rollback Plan Confirmed                                              │   │
│  │ • Timeout: 7 days                                                        │   │
│  │                                                                          │   │
│  │ Approvers: Tech Leads + Managers                                         │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │                                             │
│                                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ STAGE 6: Deploy to Production                                            │   │
│  │ ───────────────────────────────                                          │   │
│  │ • Pre-deployment backup                                                  │   │
│  │ • Execute deployment with extra monitoring                               │   │
│  │ • Comprehensive health checks                                            │   │
│  │ • Notify on completion                                                   │   │
│  │                                                                          │   │
│  │ On Failure: Automatic Rollback → Page On-Call → Create Incident          │   │
│  └────────────────────────────────┬────────────────────────────────────────┘   │
│                                   │                                             │
│                                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ POST-DEPLOYMENT                                                          │   │
│  │ ─────────────────                                                        │   │
│  │ • Send success notification to Slack channel                             │   │
│  │ • Update deployment dashboard                                            │   │
│  │ • Tag Git repository with version                                        │   │
│  │ • Close change ticket (if integrated)                                    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Generic Pipeline Template (Using Org Templates)

```yaml
# ═══════════════════════════════════════════════════════════════════════════════
# PIPELINE: Standard Deployment Pipeline (Using Org Templates)
# This pattern is used across all projects with appropriate template references
# ═══════════════════════════════════════════════════════════════════════════════

pipeline:
  name: Deploy <+service.name>
  identifier: deploy_<+service.identifier>
  projectIdentifier: <+project.identifier>
  orgIdentifier: digital_platform
  tags:
    bu: digital-platform
    deployment-type: <+input>

  variables:
    - name: version
      type: String
      description: "Version/tag to deploy"
      value: <+input>
    - name: git_branch
      type: String
      description: "Git branch"
      value: <+input>.default(main)

  stages:
    # =========================================================================
    # Stage 1: Pre-Flight (Always runs)
    # =========================================================================
    - stage:
        name: Pre-Flight Checks
        identifier: preflight
        type: Custom
        spec:
          execution:
            steps:
              - step:
                  name: Validate Inputs
                  identifier: validate
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e
                          echo "═══════════════════════════════════════════"
                          echo "Pre-Flight Validation"
                          echo "═══════════════════════════════════════════"
                          echo "Project: <+project.name>"
                          echo "Service: <+service.name>"
                          echo "Version: <+pipeline.variables.version>"
                          echo "═══════════════════════════════════════════"

                          # Add validation logic here
                    delegateSelectors:
                      - dp-ansible-delegate
                  timeout: 5m

    # =========================================================================
    # Stage 2: Deploy to Development (Uses Org Template)
    # =========================================================================
    - stage:
        name: Deploy to Development
        identifier: deploy_dev
        template:
          templateRef: org.ansible_deploy_stage  # For Ansible projects
          # OR: org.ecs_deploy_stage           # For ECS projects
          # OR: org.ec2_shell_deploy_stage     # For EC2 Shell projects
          versionLabel: "1.0.0"
          templateInputs:
            type: Custom
            spec:
              execution:
                steps:
                  - step:
                      identifier: run_ansible
                      type: ShellScript
                      spec:
                        environmentVariables:
                          - name: ENVIRONMENT
                            value: dev
            variables:
              - name: git_repo_url
                value: <+service.variables.git_repo>
              - name: inventory_file
                value: inventory/dev/hosts.yml
              - name: ssh_key_secret
                value: org.dp_platform_ssh_key

    # =========================================================================
    # Stage 3: Staging Approval
    # =========================================================================
    - stage:
        name: Staging Approval
        identifier: staging_approval
        template:
          templateRef: org.standard_approval_stage
          versionLabel: "1.0.0"
          templateInputs:
            variables:
              - name: approval_message
                value: "Development deployment successful. Approve staging deployment?"
              - name: target_environment
                value: Staging
              - name: approver_groups
                value: '["<+project.identifier>_team"]'
              - name: min_approvers
                value: 1
              - name: approval_timeout
                value: "1d"

    # =========================================================================
    # Stage 4: Deploy to Staging
    # =========================================================================
    - stage:
        name: Deploy to Staging
        identifier: deploy_staging
        template:
          templateRef: org.ansible_deploy_stage
          versionLabel: "1.0.0"
          templateInputs:
            variables:
              - name: inventory_file
                value: inventory/staging/hosts.yml

    # =========================================================================
    # Stage 5: Production Approval
    # =========================================================================
    - stage:
        name: Production Approval
        identifier: production_approval
        template:
          templateRef: org.standard_approval_stage
          versionLabel: "1.0.0"
          templateInputs:
            variables:
              - name: approval_message
                value: |
                  PRODUCTION DEPLOYMENT APPROVAL

                  Service: <+service.name>
                  Version: <+pipeline.variables.version>

                  Please provide change ticket to proceed.
              - name: target_environment
                value: Production
              - name: approver_groups
                value: '["dp_tech_leads", "dp_managers"]'
              - name: min_approvers
                value: 2
              - name: disallow_executor
                value: "true"
              - name: approval_timeout
                value: "7d"

    # =========================================================================
    # Stage 6: Deploy to Production
    # =========================================================================
    - stage:
        name: Deploy to Production
        identifier: deploy_production
        template:
          templateRef: org.ansible_deploy_stage
          versionLabel: "1.0.0"
          templateInputs:
            variables:
              - name: inventory_file
                value: inventory/production/hosts.yml

  notificationRules:
    - name: Deployment Notifications
      enabled: true
      pipelineEvents:
        - type: PipelineStart
        - type: PipelineEnd
        - type: PipelineFailed
        - type: StageStart
          forStages:
            - deploy_production
      notificationMethod:
        type: Slack
        spec:
          webhookUrl: <+secrets.getValue("org.dp_slack_webhook")>
```

---

## 8. Delegate Strategy

### 8.1 Delegate Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    BU DELEGATE DEPLOYMENT STRATEGY                               │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                   MANAGEMENT NETWORK / KUBERNETES                        │   │
│  │                                                                          │   │
│  │  ┌─────────────────────────────────────────────────────────────┐        │   │
│  │  │         KUBERNETES CLUSTER: dp-delegates                     │        │   │
│  │  │                                                              │        │   │
│  │  │  Namespace: harness-delegates                                │        │   │
│  │  │                                                              │        │   │
│  │  │  ┌──────────────────┐  ┌──────────────────┐                 │        │   │
│  │  │  │ Deployment:      │  │ Deployment:      │                 │        │   │
│  │  │  │ dp-ansible-      │  │ dp-aws-          │                 │        │   │
│  │  │  │ delegate         │  │ delegate         │                 │        │   │
│  │  │  │                  │  │                  │                 │        │   │
│  │  │  │ Replicas: 2      │  │ Replicas: 2      │                 │        │   │
│  │  │  │                  │  │                  │                 │        │   │
│  │  │  │ Tags:            │  │ Tags:            │                 │        │   │
│  │  │  │ - ansible        │  │ - aws            │                 │        │   │
│  │  │  │ - linux          │  │ - ecs            │                 │        │   │
│  │  │  │ - digital-       │  │ - ec2            │                 │        │   │
│  │  │  │   platform       │  │ - digital-       │                 │        │   │
│  │  │  │                  │  │   platform       │                 │        │   │
│  │  │  │ Software:        │  │                  │                 │        │   │
│  │  │  │ - Ansible 2.15   │  │ Software:        │                 │        │   │
│  │  │  │ - Python 3.9     │  │ - AWS CLI v2     │                 │        │   │
│  │  │  │ - SSH client     │  │ - Docker CLI     │                 │        │   │
│  │  │  │ - Git            │  │ - jq             │                 │        │   │
│  │  │  └──────────────────┘  └──────────────────┘                 │        │   │
│  │  │                                                              │        │   │
│  │  │  Resource Allocation per Pod:                                │        │   │
│  │  │  - CPU: 1 core (request) / 2 cores (limit)                   │        │   │
│  │  │  - Memory: 2GB (request) / 4GB (limit)                       │        │   │
│  │  │                                                              │        │   │
│  │  └──────────────────────────────────────────────────────────────┘        │   │
│  │                              │                                            │   │
│  │                              │ Network Access                             │   │
│  │                              │                                            │   │
│  └──────────────────────────────┼────────────────────────────────────────────┘   │
│                                 │                                                │
│         ┌───────────────────────┼───────────────────────┐                       │
│         │                       │                       │                       │
│         ▼                       ▼                       ▼                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                 │
│  │ Target: RHEL VMs│  │ Target: AWS ECS │  │ Target: AWS EC2 │                 │
│  │ (SSH:22)        │  │ (HTTPS:443)     │  │ (SSH:22)        │                 │
│  │                 │  │                 │  │                 │                 │
│  │ • RabbitMQ      │  │ • ECS Clusters  │  │ • Backend       │                 │
│  │ • Kafka         │  │ • ECR Registry  │  │   Services      │                 │
│  │ • Monitoring    │  │ • ALB           │  │ • Redis         │                 │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                 │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Delegate Helm Values

```yaml
# helm-values-dp-ansible-delegate.yaml

delegateName: dp-ansible-delegate
accountId: <HARNESS_ACCOUNT_ID>
delegateToken: <DELEGATE_TOKEN>
managerEndpoint: https://app.harness.io
delegateDockerImage: harness/delegate:latest

# Scope to Organization
delegateType: KUBERNETES
description: "Ansible delegate for Digital Platform BU"

# Tags for selection
tags:
  - ansible
  - linux
  - digital-platform

# Replicas for HA
replicas: 2

# Resources
resources:
  limits:
    cpu: "2"
    memory: "4Gi"
  requests:
    cpu: "1"
    memory: "2Gi"

# Init script to install required tools
initScript: |
  #!/bin/bash
  set -e

  # Install Python and pip
  microdnf install -y python3 python3-pip openssh-clients git

  # Install Ansible
  pip3 install ansible==2.15.*

  # Install Ansible collections
  ansible-galaxy collection install community.general
  ansible-galaxy collection install ansible.posix

  # Verify installations
  echo "Ansible version: $(ansible --version | head -1)"
  echo "Python version: $(python3 --version)"

# Selectors for pipeline reference
delegateSelectors:
  - dp-ansible-delegate

# Node affinity (optional)
nodeSelector:
  node-type: management
```

---

## 9. Secrets Management

### 9.1 Secrets Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    SECRETS MANAGEMENT FOR BU                                     │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ ACCOUNT LEVEL (Managed by: Central IT)                                   │   │
│  │ Reference: account.secret_name                                           │   │
│  │                                                                          │   │
│  │ • global-pagerduty-key        (Company-wide incident management)         │   │
│  │ • global-github-enterprise    (GitHub Enterprise PAT)                    │   │
│  │ • global-vault-token          (HashiCorp Vault)                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ ORGANIZATION LEVEL: digital_platform (Managed by: BU Platform Team)     │   │
│  │ Reference: org.secret_name                                               │   │
│  │                                                                          │   │
│  │ ┌─────────────────────────────────────────────────────────────────────┐ │   │
│  │ │ Shared Infrastructure Secrets                                        │ │   │
│  │ │ • dp-platform-ssh-key       (SSH key for all BU infrastructure)     │ │   │
│  │ │ • dp-aws-access-key         (AWS credentials)                       │ │   │
│  │ │ • dp-aws-secret-key         (AWS credentials)                       │ │   │
│  │ │ • dp-github-token           (GitHub PAT for BU repos)               │ │   │
│  │ │ • dp-artifactory-token      (Artifact repository)                   │ │   │
│  │ │ • dp-slack-webhook          (BU Slack channel)                      │ │   │
│  │ └─────────────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│         ┌────────────────────────────┼────────────────────────────┐            │
│         ▼                            ▼                            ▼            │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐    │
│  │ PROJECT:            │  │ PROJECT:            │  │ PROJECT:            │    │
│  │ rabbitmq-cluster    │  │ webapp-ecs          │  │ backend-services    │    │
│  │                     │  │                     │  │                     │    │
│  │ Project Secrets:    │  │ Project Secrets:    │  │ Project Secrets:    │    │
│  │ • rabbitmq-admin-   │  │ • webapp-db-        │  │ • backend-db-       │    │
│  │   password          │  │   password          │  │   password          │    │
│  │ • rabbitmq-erlang-  │  │ • webapp-api-key    │  │ • backend-redis-    │    │
│  │   cookie            │  │ • webapp-jwt-secret │  │   password          │    │
│  │ • rabbitmq-nodes-   │  │                     │  │ • backend-ssh-key   │    │
│  │   ssh-key (if       │  │ Uses Org:           │  │   (if different)    │    │
│  │   different)        │  │ • dp-aws-*          │  │                     │    │
│  │                     │  │ • dp-github-token   │  │ Uses Org:           │    │
│  │ Uses Org:           │  │                     │  │ • dp-artifactory-   │    │
│  │ • dp-platform-ssh-  │  │                     │  │   token             │    │
│  │   key               │  │                     │  │ • dp-platform-ssh-  │    │
│  │ • dp-slack-webhook  │  │                     │  │   key               │    │
│  │                     │  │                     │  │                     │    │
│  │ Reference:          │  │ Reference:          │  │ Reference:          │    │
│  │ secret_name         │  │ secret_name         │  │ secret_name         │    │
│  │ (no prefix)         │  │ (no prefix)         │  │ (no prefix)         │    │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 9.2 Secret Reference Examples

```yaml
# In Pipeline YAML:

# Reference Account-level secret
account_secret_example: <+secrets.getValue("account.global_pagerduty_key")>

# Reference Org-level secret
org_secret_example: <+secrets.getValue("org.dp_platform_ssh_key")>

# Reference Project-level secret (within same project)
project_secret_example: <+secrets.getValue("rabbitmq_admin_password")>

# Reference in Shell Script step
steps:
  - step:
      type: ShellScript
      spec:
        source:
          type: Inline
          spec:
            script: |
              # SSH key from Org secret
              echo "<+secrets.getValue("org.dp_platform_ssh_key")>" > ~/.ssh/id_rsa

              # Password from Project secret
              export DB_PASSWORD="<+secrets.getValue("backend_db_password")>"

              # API key from Project secret
              export API_KEY="<+secrets.getValue("webapp_api_key")>"
```

---

## 10. Approval & Governance

### 10.1 User Groups Structure

```yaml
# Organization-Level User Groups (for BU)
org_user_groups:
  # BU-wide Admin Group
  - name: Digital Platform Admins
    identifier: dp_admins
    description: BU-wide administrators
    users:
      - bu-admin1@acme.com
      - bu-admin2@acme.com
    roles:
      - Organization Admin

  # Tech Leads (Production Approvers)
  - name: Digital Platform Tech Leads
    identifier: dp_tech_leads
    description: Technical leads for production approvals
    users:
      - tech-lead1@acme.com
      - tech-lead2@acme.com
      - tech-lead3@acme.com
    roles:
      - Pipeline Executor

  # Managers (Production Approvers)
  - name: Digital Platform Managers
    identifier: dp_managers
    description: Engineering managers for production approvals
    users:
      - manager1@acme.com
      - manager2@acme.com
    roles:
      - Pipeline Executor

# Project-Level User Groups
project_user_groups:
  # RabbitMQ Team
  - project: rabbitmq_cluster
    groups:
      - name: RabbitMQ Team
        identifier: rabbitmq_team
        users:
          - rabbitmq-dev1@acme.com
          - rabbitmq-dev2@acme.com
        roles:
          - Pipeline Executor
          - Service Admin

  # WebApp Team
  - project: webapp_ecs
    groups:
      - name: WebApp Team
        identifier: webapp_team
        users:
          - webapp-dev1@acme.com
          - webapp-dev2@acme.com
          - webapp-dev3@acme.com
        roles:
          - Pipeline Executor
          - Service Admin

  # Backend Team
  - project: backend_services
    groups:
      - name: Backend Team
        identifier: backend_team
        users:
          - backend-dev1@acme.com
          - backend-dev2@acme.com
          - backend-dev3@acme.com
        roles:
          - Pipeline Executor
          - Service Admin
```

### 10.2 Approval Matrix

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           APPROVAL MATRIX                                        │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ ENVIRONMENT  │ APPROVERS                     │ COUNT │ TIMEOUT │ INPUTS │   │
│  ├──────────────┼───────────────────────────────┼───────┼─────────┼────────┤   │
│  │ Development  │ None (Auto-deploy)            │  N/A  │   N/A   │  None  │   │
│  │              │                               │       │         │        │   │
│  │ Staging      │ Project Team                  │   1   │  1 day  │  None  │   │
│  │              │ (webapp_team, rabbitmq_team,  │       │         │        │   │
│  │              │  backend_team)                │       │         │        │   │
│  │              │                               │       │         │        │   │
│  │ Production   │ Tech Leads (dp_tech_leads)    │   2   │ 7 days  │ • CHG# │   │
│  │              │ + Managers (dp_managers)      │       │         │ • MW   │   │
│  │              │                               │       │         │ • RB   │   │
│  │              │ Executor cannot self-approve  │       │         │        │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Legend:                                                                        │
│  CHG# = Change Ticket Number (format: CHG######)                                │
│  MW   = Maintenance Window                                                      │
│  RB   = Rollback Plan Confirmed                                                 │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 11. Migration Plan

### 11.1 Phase-wise Migration

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    JENKINS TO HARNESS MIGRATION PLAN                             │
│                                                                                  │
│  ╔═══════════════════════════════════════════════════════════════════════════╗ │
│  ║ PHASE 1: FOUNDATION (Week 1-2)                                            ║ │
│  ╠═══════════════════════════════════════════════════════════════════════════╣ │
│  ║                                                                           ║ │
│  ║ □ Create Organization in Harness (digital_platform)                       ║ │
│  ║ □ Install and configure Delegates                                         ║ │
│  ║ □ Create Org-level Connectors (GitHub, AWS, Artifactory)                  ║ │
│  ║ □ Create Org-level Secrets                                                ║ │
│  ║ □ Create Org-level Templates (from Jenkins shared libraries)             ║ │
│  ║ □ Set up User Groups and RBAC                                             ║ │
│  ║ □ Configure notification channels                                         ║ │
│  ║                                                                           ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════╝ │
│                                      │                                          │
│                                      ▼                                          │
│  ╔═══════════════════════════════════════════════════════════════════════════╗ │
│  ║ PHASE 2: PILOT PROJECT (Week 3-4)                                         ║ │
│  ╠═══════════════════════════════════════════════════════════════════════════╣ │
│  ║                                                                           ║ │
│  ║ Select ONE project for pilot (recommend: lowest risk, e.g., monitoring)  ║ │
│  ║                                                                           ║ │
│  ║ □ Create Project in Harness                                               ║ │
│  ║ □ Create Services, Environments, Infrastructure Definitions              ║ │
│  ║ □ Migrate Jenkins pipeline to Harness pipeline                            ║ │
│  ║ □ Run parallel deployments (Jenkins + Harness) to Dev                     ║ │
│  ║ □ Validate functionality and timing                                       ║ │
│  ║ □ Deploy to Staging via Harness                                           ║ │
│  ║ □ Get team feedback                                                       ║ │
│  ║ □ Document issues and learnings                                           ║ │
│  ║                                                                           ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════╝ │
│                                      │                                          │
│                                      ▼                                          │
│  ╔═══════════════════════════════════════════════════════════════════════════╗ │
│  ║ PHASE 3: EXPAND TO OTHER PROJECTS (Week 5-8)                              ║ │
│  ╠═══════════════════════════════════════════════════════════════════════════╣ │
│  ║                                                                           ║ │
│  ║ Migration Order (by risk/complexity):                                    ║ │
│  ║                                                                           ║ │
│  ║ Week 5: monitoring-stack (Ansible - similar to pilot)                    ║ │
│  ║ Week 6: rabbitmq-cluster (Ansible - infrastructure critical)             ║ │
│  ║ Week 7: webapp-ecs (ECS - new deployment type)                           ║ │
│  ║ Week 8: backend-services (EC2 Shell - multiple services)                 ║ │
│  ║                                                                           ║ │
│  ║ For each project:                                                        ║ │
│  ║ □ Create project and entities                                             ║ │
│  ║ □ Migrate pipelines                                                       ║ │
│  ║ □ Test in Dev/Staging                                                     ║ │
│  ║ □ Run parallel with Jenkins for 1 week                                    ║ │
│  ║ □ Switch to Harness as primary                                            ║ │
│  ║                                                                           ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════╝ │
│                                      │                                          │
│                                      ▼                                          │
│  ╔═══════════════════════════════════════════════════════════════════════════╗ │
│  ║ PHASE 4: PRODUCTION CUTOVER (Week 9-10)                                   ║ │
│  ╠═══════════════════════════════════════════════════════════════════════════╣ │
│  ║                                                                           ║ │
│  ║ □ Complete testing in all environments                                    ║ │
│  ║ □ Train all team members on Harness                                       ║ │
│  ║ □ Update runbooks and documentation                                       ║ │
│  ║ □ Schedule production deployment via Harness                              ║ │
│  ║ □ Perform production deployment for each project                          ║ │
│  ║ □ Validate success                                                        ║ │
│  ║                                                                           ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════╝ │
│                                      │                                          │
│                                      ▼                                          │
│  ╔═══════════════════════════════════════════════════════════════════════════╗ │
│  ║ PHASE 5: DECOMMISSION JENKINS (Week 11-12)                                ║ │
│  ╠═══════════════════════════════════════════════════════════════════════════╣ │
│  ║                                                                           ║ │
│  ║ □ Disable Jenkins jobs (don't delete yet)                                 ║ │
│  ║ □ Monitor Harness for 2 weeks                                             ║ │
│  ║ □ Archive Jenkins job configurations                                      ║ │
│  ║ □ Decommission Jenkins agents                                             ║ │
│  ║ □ Delete Jenkins folder (after backup)                                    ║ │
│  ║ □ Project complete!                                                       ║ │
│  ║                                                                           ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════╝ │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 11.2 Migration Checklist per Project

```markdown
## Migration Checklist: [Project Name]

### Pre-Migration
- [ ] Document current Jenkins job configuration
- [ ] List all credentials/secrets used
- [ ] Identify target environments and hosts
- [ ] Document approval process
- [ ] Identify notification channels

### Harness Setup
- [ ] Create Project in Harness
- [ ] Create Project-specific Secrets
- [ ] Create Service definition
- [ ] Create Environments (dev, staging, production)
- [ ] Create Infrastructure Definitions
- [ ] Create User Groups and assign permissions

### Pipeline Migration
- [ ] Create pipeline YAML
- [ ] Map Jenkins parameters to Harness variables
- [ ] Convert Jenkinsfile stages to Harness stages
- [ ] Configure approval stages
- [ ] Set up notifications
- [ ] Configure rollback steps

### Testing
- [ ] Test deployment to Dev (Harness)
- [ ] Compare with Jenkins deployment
- [ ] Test approval workflow
- [ ] Test rollback
- [ ] Test notifications

### Cutover
- [ ] Schedule cutover date
- [ ] Communicate to team
- [ ] Disable Jenkins job
- [ ] Monitor Harness deployments
- [ ] Document any issues

### Post-Migration
- [ ] Update runbooks
- [ ] Train team members
- [ ] Archive Jenkins configuration
- [ ] Close migration ticket
```

---

## 12. Complete Examples

### 12.1 Complete RabbitMQ Pipeline (Production-Ready)

See: `HARNESS_RABBITMQ_CLUSTER_POC.md` for full pipeline

### 12.2 Complete WebApp ECS Pipeline

See: `HARNESS_ECS_EC2_DEPLOYMENT_GUIDE.md` for full pipeline

### 12.3 Complete Backend Services EC2 Pipeline

See: `HARNESS_ECS_EC2_DEPLOYMENT_GUIDE.md` for full pipeline

---

## Summary

This document provides a complete blueprint for migrating your BU from Jenkins to Harness CD:

| Component | Jenkins | Harness |
|-----------|---------|---------|
| Structure | Folders | Organization → Projects |
| Pipelines | Per-environment jobs | Single pipeline, multiple stages |
| Shared Code | Shared Libraries | Org Templates |
| Secrets | Credentials Plugin | Scoped Secrets |
| Agents | Labeled nodes | Tagged Delegates |
| Approvals | Input step | Approval Stage with RBAC |
| Governance | Limited | OPA Policies |

**Key Benefits of Migration:**
1. Single pipeline for all environments
2. Built-in rollback mechanisms
3. Granular RBAC and audit trail
4. Reusable templates across projects
5. Native approval workflows
6. Better visibility and governance

---

**End of Document**
