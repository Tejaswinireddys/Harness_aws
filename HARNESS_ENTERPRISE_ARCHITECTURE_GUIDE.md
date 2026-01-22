# Harness CD Enterprise Architecture Guide

## Complete Project Structure, Pipeline Templates, Secrets Management & Approval Workflows

---

## Executive Summary

This document provides a comprehensive enterprise architecture guide for implementing Harness CD at an organizational level. It covers GitHub repository structure, Harness hierarchy, secrets management, delegate architecture, pipeline templates, and approval workflows using RabbitMQ cluster deployment as a practical example.

**Document Purpose:** Enable teams to implement standardized, secure, and scalable CI/CD pipelines following enterprise best practices.

---

## Table of Contents

1. [Harness Hierarchy Overview](#1-harness-hierarchy-overview)
2. [GitHub Repository Structure](#2-github-repository-structure)
3. [Harness Project Structure](#3-harness-project-structure)
4. [Secrets Management Strategy](#4-secrets-management-strategy)
5. [Delegate Architecture](#5-delegate-architecture)
6. [Pipeline Templates](#6-pipeline-templates)
7. [Approval Workflow Design](#7-approval-workflow-design)
8. [Complete RabbitMQ Example](#8-complete-rabbitmq-example)
9. [RBAC & Governance](#9-rbac--governance)
10. [Best Practices Checklist](#10-best-practices-checklist)

---

## 1. Harness Hierarchy Overview

### 1.1 Harness Account Structure

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              HARNESS ACCOUNT                                     │
│                         (Company: Acme Corporation)                              │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                    ACCOUNT-LEVEL RESOURCES                                 │  │
│  │  • Account Admin Users          • Default Delegates                        │  │
│  │  • Account Secrets (Shared)     • License Management                       │  │
│  │  • Connectors (Shared)          • Audit Logs                               │  │
│  │  • Templates (Account-wide)     • Governance Policies                      │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                           │
│         ┌────────────────────────────┼────────────────────────────┐             │
│         │                            │                            │             │
│         ▼                            ▼                            ▼             │
│  ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐         │
│  │  ORGANIZATION   │      │  ORGANIZATION   │      │  ORGANIZATION   │         │
│  │   Platform      │      │   Application   │      │   Data          │         │
│  │   Engineering   │      │   Development   │      │   Engineering   │         │
│  └────────┬────────┘      └────────┬────────┘      └────────┬────────┘         │
│           │                        │                        │                   │
│     ┌─────┴─────┐            ┌─────┴─────┐            ┌─────┴─────┐            │
│     ▼           ▼            ▼           ▼            ▼           ▼            │
│ ┌───────┐ ┌───────┐    ┌───────┐ ┌───────┐    ┌───────┐ ┌───────┐            │
│ │Project│ │Project│    │Project│ │Project│    │Project│ │Project│            │
│ │  K8s  │ │RabbitMQ│   │ Web   │ │Mobile │    │Kafka  │ │ Spark │            │
│ │Infra  │ │Cluster │   │ App   │ │ App   │    │Cluster│ │  ETL  │            │
│ └───────┘ └───────┘    └───────┘ └───────┘    └───────┘ └───────┘            │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Scope Inheritance Model

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           SCOPE INHERITANCE                                      │
│                                                                                  │
│  ACCOUNT LEVEL (Highest)                                                        │
│  ├── Secrets: Shared across ALL orgs & projects                                 │
│  ├── Connectors: Available to ALL orgs & projects                               │
│  ├── Templates: Reusable by ALL orgs & projects                                 │
│  ├── Delegates: Can be shared or scoped                                         │
│  └── User Groups: Account-wide admin groups                                     │
│       │                                                                          │
│       ▼                                                                          │
│  ORGANIZATION LEVEL (Middle)                                                    │
│  ├── Secrets: Shared within org, inherited from account                         │
│  ├── Connectors: Available to all projects in org                               │
│  ├── Templates: Reusable within org                                             │
│  ├── Delegates: Org-scoped delegates                                            │
│  └── User Groups: Org-level roles                                               │
│       │                                                                          │
│       ▼                                                                          │
│  PROJECT LEVEL (Lowest)                                                         │
│  ├── Secrets: Project-specific only                                             │
│  ├── Connectors: Project-specific only                                          │
│  ├── Templates: Project-specific only                                           │
│  ├── Delegates: Project-scoped delegates                                        │
│  └── User Groups: Project team members                                          │
│                                                                                  │
│  ════════════════════════════════════════════════════════════════════════════   │
│  INHERITANCE RULE: Lower scopes can USE resources from higher scopes,           │
│                    but cannot MODIFY them.                                       │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Your Project Context

As a project-level user with a project assigned by the org admin team:

```
Account: acme-corp
    └── Organization: platform-engineering
            └── Project: rabbitmq-cluster (YOUR PROJECT)
                    ├── Can USE account-level secrets/connectors/templates
                    ├── Can USE org-level secrets/connectors/templates
                    ├── Can CREATE project-level resources
                    └── Cannot MODIFY account/org level resources
```

---

## 2. GitHub Repository Structure

### 2.1 Recommended Repository Organization

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    GITHUB ORGANIZATION STRUCTURE                                 │
│                        (github.com/acme-corp)                                   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                     INFRASTRUCTURE REPOSITORIES                          │   │
│  │                                                                          │   │
│  │  acme-corp/                                                              │   │
│  │  ├── infra-ansible-common/        # Shared Ansible roles & collections  │   │
│  │  ├── infra-terraform-modules/     # Shared Terraform modules            │   │
│  │  ├── infra-helm-charts/           # Shared Helm charts                  │   │
│  │  └── infra-harness-templates/     # Shared Harness pipeline templates   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      PROJECT REPOSITORIES                                │   │
│  │                                                                          │   │
│  │  acme-corp/                                                              │   │
│  │  ├── rabbitmq-deployment/         # RabbitMQ specific deployment code   │   │
│  │  ├── kafka-deployment/            # Kafka specific deployment code      │   │
│  │  ├── webapp-frontend/             # Application source code             │   │
│  │  └── webapp-backend/              # Application source code             │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                     CONFIGURATION REPOSITORIES                           │   │
│  │                                                                          │   │
│  │  acme-corp/                                                              │   │
│  │  ├── config-environments/         # Environment-specific configs        │   │
│  │  ├── config-secrets-reference/    # Secret references (NOT actual)      │   │
│  │  └── config-inventory/            # Ansible inventories per env         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 RabbitMQ Project Repository Structure

```
rabbitmq-deployment/
│
├── README.md                          # Project documentation
├── CHANGELOG.md                       # Version history
├── .gitignore                         # Git ignore rules
│
├── .harness/                          # Harness pipeline-as-code (optional)
│   ├── pipelines/
│   │   ├── deploy-rabbitmq.yaml
│   │   └── destroy-rabbitmq.yaml
│   └── templates/
│       └── ansible-step-template.yaml
│
├── ansible/                           # Ansible codebase
│   ├── ansible.cfg
│   ├── requirements.yml               # Ansible Galaxy requirements
│   │
│   ├── inventory/                     # Environment inventories
│   │   ├── dev/
│   │   │   ├── hosts.yml
│   │   │   └── group_vars/
│   │   │       ├── all.yml            # Non-sensitive variables
│   │   │       └── vault.yml          # Encrypted with ansible-vault (optional)
│   │   ├── staging/
│   │   │   ├── hosts.yml
│   │   │   └── group_vars/
│   │   │       └── all.yml
│   │   └── production/
│   │       ├── hosts.yml
│   │       └── group_vars/
│   │           └── all.yml
│   │
│   ├── playbooks/
│   │   ├── deploy.yml                 # Main deployment playbook
│   │   ├── rollback.yml               # Rollback playbook
│   │   ├── upgrade.yml                # Upgrade playbook
│   │   ├── backup.yml                 # Backup playbook
│   │   └── healthcheck.yml            # Health check playbook
│   │
│   └── roles/
│       └── rabbitmq/
│           ├── defaults/main.yml
│           ├── handlers/main.yml
│           ├── tasks/
│           ├── templates/
│           └── vars/
│
├── scripts/                           # Utility scripts
│   ├── pre-deploy-check.sh
│   ├── post-deploy-validate.sh
│   └── generate-inventory.sh
│
├── tests/                             # Test files
│   ├── integration/
│   │   └── test_cluster.py
│   └── molecule/                      # Ansible Molecule tests
│       └── default/
│
└── docs/                              # Additional documentation
    ├── architecture.md
    ├── runbook.md
    └── troubleshooting.md
```

### 2.3 Branch Strategy

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          GIT BRANCH STRATEGY                                     │
│                                                                                  │
│  main (protected)                                                               │
│  │   └── Production-ready code                                                  │
│  │   └── Requires PR + approvals                                                │
│  │   └── Triggers: Production deployment (manual approval)                      │
│  │                                                                               │
│  ├── release/v1.0.0                                                             │
│  │   └── Release branches for versioning                                        │
│  │   └── Created from main for production releases                              │
│  │                                                                               │
│  ├── develop                                                                    │
│  │   └── Integration branch                                                     │
│  │   └── Triggers: Development deployment (auto)                                │
│  │                                                                               │
│  ├── staging                                                                    │
│  │   └── Staging environment branch                                             │
│  │   └── Triggers: Staging deployment (auto)                                    │
│  │                                                                               │
│  └── feature/JIRA-123-description                                               │
│      └── Feature branches                                                       │
│      └── PR to develop                                                          │
│                                                                                  │
│  ════════════════════════════════════════════════════════════════════════════   │
│                                                                                  │
│  BRANCH → ENVIRONMENT MAPPING:                                                  │
│  ┌──────────────┬─────────────────┬─────────────────────────────────────────┐  │
│  │   Branch     │   Environment   │   Trigger                               │  │
│  ├──────────────┼─────────────────┼─────────────────────────────────────────┤  │
│  │ develop      │ Development     │ Auto on merge                           │  │
│  │ staging      │ Staging         │ Auto on merge                           │  │
│  │ main         │ Production      │ Manual trigger + approval               │  │
│  └──────────────┴─────────────────┴─────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Harness Project Structure

### 3.1 Project Components Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     HARNESS PROJECT: rabbitmq-cluster                           │
│                     Organization: platform-engineering                          │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                           CONNECTORS                                     │   │
│  │                                                                          │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │   │
│  │  │   Git Connector │  │  AWS Connector  │  │ Docker Registry │         │   │
│  │  │                 │  │   (if needed)   │  │  (if needed)    │         │   │
│  │  │ github-rabbitmq │  │   aws-platform  │  │  dockerhub      │         │   │
│  │  │    (Project)    │  │    (Org-level)  │  │  (Account)      │         │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                            SECRETS                                       │   │
│  │                                                                          │   │
│  │  Account-Level (Inherited):                                              │   │
│  │  └── github-pat-token (shared Git access)                                │   │
│  │                                                                          │   │
│  │  Org-Level (Inherited):                                                  │   │
│  │  └── platform-ssh-key (shared infra access)                              │   │
│  │                                                                          │   │
│  │  Project-Level (Owned):                                                  │   │
│  │  ├── rabbitmq-admin-password                                             │   │
│  │  ├── rabbitmq-erlang-cookie                                              │   │
│  │  ├── rabbitmq-app-password                                               │   │
│  │  └── rabbitmq-nodes-ssh-key                                              │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                          ENVIRONMENTS                                    │   │
│  │                                                                          │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                  │   │
│  │  │ Development │    │   Staging   │    │ Production  │                  │   │
│  │  │             │    │             │    │             │                  │   │
│  │  │ Type: Pre-  │    │ Type: Pre-  │    │ Type: Prod  │                  │   │
│  │  │ Production  │    │ Production  │    │             │                  │   │
│  │  │             │    │             │    │ Approval:   │                  │   │
│  │  │ Auto-deploy │    │ Auto-deploy │    │ Required    │                  │   │
│  │  └─────────────┘    └─────────────┘    └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                           SERVICES                                       │   │
│  │                                                                          │   │
│  │  ┌─────────────────────────────────────────────────────────┐            │   │
│  │  │  Service: rabbitmq-cluster                              │            │   │
│  │  │  Type: Custom Deployment (Ansible)                      │            │   │
│  │  │                                                         │            │   │
│  │  │  Manifests: Git repository (ansible playbooks)          │            │   │
│  │  │  Variables:                                             │            │   │
│  │  │    - rabbitmq_version: 4.0.2                            │            │   │
│  │  │    - erlang_version: 26.2                               │            │   │
│  │  │    - cluster_size: 3                                    │            │   │
│  │  └─────────────────────────────────────────────────────────┘            │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                          PIPELINES                                       │   │
│  │                                                                          │   │
│  │  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐   │   │
│  │  │ Deploy RabbitMQ   │  │ Upgrade RabbitMQ  │  │ Destroy RabbitMQ  │   │   │
│  │  │ (Main Pipeline)   │  │ (Rolling Update)  │  │ (Cleanup)         │   │   │
│  │  └───────────────────┘  └───────────────────┘  └───────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    INFRASTRUCTURE DEFINITIONS                            │   │
│  │                                                                          │   │
│  │  Development:     rabbitmq-infra-dev                                     │   │
│  │  Staging:         rabbitmq-infra-staging                                 │   │
│  │  Production:      rabbitmq-infra-production                              │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Step-by-Step Project Setup

#### Step 1: Verify Project Access

```yaml
# Navigate to Harness UI
# 1. Login to Harness
# 2. Click on "Account Settings" (top-right)
# 3. Verify your organization: platform-engineering
# 4. Verify your project: rabbitmq-cluster
# 5. Check your role permissions

# Required Permissions:
permissions_required:
  - pipeline: Create, Edit, Execute, Delete
  - service: Create, Edit, Delete
  - environment: Create, Edit, Delete
  - connector: Create, Edit, Delete (Project scope)
  - secret: Create, Edit, Delete (Project scope)
  - infrastructure: Create, Edit, Delete
```

#### Step 2: Create Git Connector

```yaml
# Harness UI: Project Settings → Connectors → + New Connector → Code Repositories → GitHub

connector:
  name: github-rabbitmq-deployment
  identifier: github_rabbitmq_deployment
  description: GitHub connector for RabbitMQ deployment repository
  orgIdentifier: platform_engineering
  projectIdentifier: rabbitmq_cluster
  type: Github
  spec:
    url: https://github.com/acme-corp/rabbitmq-deployment
    authentication:
      type: Http
      spec:
        type: UsernameToken
        spec:
          username: harness-service-account
          tokenRef: account.github_pat_token    # Uses account-level secret
    apiAccess:
      type: Token
      spec:
        tokenRef: account.github_pat_token
    delegateSelectors:
      - platform-delegate
    executeOnDelegate: true
```

#### Step 3: Create Project Secrets

```yaml
# Harness UI: Project Settings → Secrets → + New Secret

secrets:
  # SSH Key for RabbitMQ nodes
  - name: rabbitmq-nodes-ssh-key
    identifier: rabbitmq_nodes_ssh_key
    type: SSHKey
    spec:
      auth:
        type: SSH
        sshKeySpec:
          credentialType: KeyPath
          userName: ansible
          key: |
            -----BEGIN OPENSSH PRIVATE KEY-----
            [Your private key content]
            -----END OPENSSH PRIVATE KEY-----
          # Or reference a file: keyPathRef: /path/to/key

  # Admin Password
  - name: rabbitmq-admin-password
    identifier: rabbitmq_admin_password
    type: SecretText
    spec:
      value: [encrypted-value]
      valueType: Inline

  # Erlang Cookie
  - name: rabbitmq-erlang-cookie
    identifier: rabbitmq_erlang_cookie
    type: SecretText
    spec:
      value: [encrypted-value]
      valueType: Inline

  # Application Password
  - name: rabbitmq-app-password
    identifier: rabbitmq_app_password
    type: SecretText
    spec:
      value: [encrypted-value]
      valueType: Inline
```

---

## 4. Secrets Management Strategy

### 4.1 Secret Scope Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        SECRETS MANAGEMENT ARCHITECTURE                           │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      ACCOUNT-LEVEL SECRETS                               │   │
│  │                   (Managed by: Platform Admin Team)                      │   │
│  │                                                                          │   │
│  │  Purpose: Shared secrets used across multiple organizations/projects    │   │
│  │                                                                          │   │
│  │  Examples:                                                               │   │
│  │  ├── github-pat-token          (GitHub access for all projects)         │   │
│  │  ├── dockerhub-credentials     (Container registry access)              │   │
│  │  ├── vault-token               (HashiCorp Vault root token)             │   │
│  │  ├── artifactory-credentials   (Artifact storage)                       │   │
│  │  └── slack-webhook-url         (Notifications)                          │   │
│  │                                                                          │   │
│  │  Reference: account.secret_name                                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    ORGANIZATION-LEVEL SECRETS                            │   │
│  │                 (Managed by: Organization Admin Team)                    │   │
│  │                                                                          │   │
│  │  Purpose: Secrets shared within an organization                         │   │
│  │                                                                          │   │
│  │  Examples (for platform-engineering org):                                │   │
│  │  ├── platform-aws-credentials  (AWS access for infra team)              │   │
│  │  ├── platform-ssh-key          (Common SSH key for VMs)                 │   │
│  │  ├── platform-db-root-password (Shared DB credentials)                  │   │
│  │  └── platform-ldap-bind        (LDAP service account)                   │   │
│  │                                                                          │   │
│  │  Reference: org.secret_name                                              │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      PROJECT-LEVEL SECRETS                               │   │
│  │                    (Managed by: Project Team)                            │   │
│  │                                                                          │   │
│  │  Purpose: Project-specific secrets, isolated from other projects        │   │
│  │                                                                          │   │
│  │  Examples (for rabbitmq-cluster project):                                │   │
│  │  ├── rabbitmq-admin-password   (RabbitMQ admin credentials)             │   │
│  │  ├── rabbitmq-erlang-cookie    (Cluster authentication)                 │   │
│  │  ├── rabbitmq-app-password     (Application user password)              │   │
│  │  ├── rabbitmq-nodes-ssh-key    (SSH key for RabbitMQ VMs)               │   │
│  │  └── rabbitmq-tls-cert         (TLS certificates)                       │   │
│  │                                                                          │   │
│  │  Reference: secret_name (no prefix needed within project)               │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Secret Reference Syntax

```yaml
# In Pipeline YAML:

# Account-level secret
account_secret: <+secrets.getValue("account.github_pat_token")>

# Organization-level secret
org_secret: <+secrets.getValue("org.platform_ssh_key")>

# Project-level secret (current project)
project_secret: <+secrets.getValue("rabbitmq_admin_password")>

# Secret from another project (requires permissions)
cross_project: <+secrets.getValue("org.other_project.some_secret")>
```

### 4.3 Secret Types and Usage

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           SECRET TYPES IN HARNESS                                │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  TYPE: SecretText                                                        │   │
│  │  Use Case: Passwords, API tokens, configuration values                   │   │
│  │  Example: rabbitmq-admin-password                                        │   │
│  │                                                                          │   │
│  │  Pipeline Reference:                                                     │   │
│  │  <+secrets.getValue("rabbitmq_admin_password")>                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  TYPE: SecretFile                                                        │   │
│  │  Use Case: Certificates, key files, configuration files                  │   │
│  │  Example: rabbitmq-tls-cert.pem                                          │   │
│  │                                                                          │   │
│  │  Pipeline Reference:                                                     │   │
│  │  <+secrets.getValue("rabbitmq_tls_cert")>  # Returns file content        │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  TYPE: SSHKey                                                            │   │
│  │  Use Case: SSH authentication for remote servers                         │   │
│  │  Example: rabbitmq-nodes-ssh-key                                         │   │
│  │                                                                          │   │
│  │  Pipeline Reference (in SSH step or variable):                           │   │
│  │  sshKeyRef: rabbitmq_nodes_ssh_key                                       │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  TYPE: WinRMCredentials                                                  │   │
│  │  Use Case: Windows server authentication                                 │   │
│  │  Example: windows-admin-credentials                                      │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 4.4 External Secret Managers Integration

```yaml
# Option 1: HashiCorp Vault Integration
secret_manager:
  type: Vault
  spec:
    vaultUrl: https://vault.acme-corp.com
    authToken: <+secrets.getValue("account.vault_token")>
    secretEngineName: kv
    secretEngineVersion: 2
    namespace: platform
    readOnly: true
    renewalIntervalMinutes: 60

# Option 2: AWS Secrets Manager
secret_manager:
  type: AwsSecretManager
  spec:
    region: us-east-1
    credentialType: AssumeIAMRole
    delegateSelectors:
      - aws-delegate

# Option 3: Azure Key Vault
secret_manager:
  type: AzureKeyVault
  spec:
    vaultName: acme-keyvault
    subscription: subscription-id
    clientId: <+secrets.getValue("account.azure_client_id")>
    tenantId: <+secrets.getValue("account.azure_tenant_id")>
```

---

## 5. Delegate Architecture

### 5.1 Delegate Deployment Strategy

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        DELEGATE ARCHITECTURE                                     │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    DELEGATE DEPLOYMENT OPTIONS                           │   │
│  │                                                                          │   │
│  │  1. KUBERNETES DELEGATE (Recommended for Production)                     │   │
│  │     - High availability with multiple replicas                           │   │
│  │     - Auto-scaling capabilities                                          │   │
│  │     - Easy upgrades via Helm                                             │   │
│  │                                                                          │   │
│  │  2. DOCKER DELEGATE (Good for POC/Development)                           │   │
│  │     - Quick setup                                                        │   │
│  │     - Single container deployment                                        │   │
│  │     - Limited scalability                                                │   │
│  │                                                                          │   │
│  │  3. VM/SHELL DELEGATE (Legacy/Special Requirements)                      │   │
│  │     - Direct installation on Linux VM                                    │   │
│  │     - Full control over environment                                      │   │
│  │     - Manual management required                                         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    DELEGATE SCOPING STRATEGY                             │   │
│  │                                                                          │   │
│  │  ACCOUNT-SCOPE DELEGATES:                                                │   │
│  │  └── Purpose: Shared infrastructure, common tools                        │   │
│  │  └── Name: account-shared-delegate                                       │   │
│  │  └── Tags: shared, common                                                │   │
│  │                                                                          │   │
│  │  ORG-SCOPE DELEGATES:                                                    │   │
│  │  └── Purpose: Organization-specific infrastructure                       │   │
│  │  └── Name: platform-eng-delegate                                         │   │
│  │  └── Tags: platform, infrastructure                                      │   │
│  │                                                                          │   │
│  │  PROJECT-SCOPE DELEGATES:                                                │   │
│  │  └── Purpose: Project-specific, isolated workloads                       │   │
│  │  └── Name: rabbitmq-project-delegate                                     │   │
│  │  └── Tags: rabbitmq, ansible                                             │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Delegate Network Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     DELEGATE NETWORK TOPOLOGY                                    │
│                                                                                  │
│                          HARNESS CLOUD                                          │
│                    ┌─────────────────────────┐                                  │
│                    │   Harness Manager       │                                  │
│                    │   (app.harness.io)      │                                  │
│                    └───────────┬─────────────┘                                  │
│                                │                                                 │
│                    HTTPS (443) │ Outbound Only                                  │
│                                │ (Delegate initiates)                           │
│                                ▼                                                 │
│  ═══════════════════════════════════════════════════════════════════════════   │
│                           CORPORATE FIREWALL                                    │
│  ═══════════════════════════════════════════════════════════════════════════   │
│                                │                                                 │
│                                ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      DELEGATE NETWORK ZONE                               │   │
│  │                    (e.g., Management Subnet)                             │   │
│  │                                                                          │   │
│  │    ┌─────────────────────┐      ┌─────────────────────┐                 │   │
│  │    │  Delegate Pod/VM    │      │  Delegate Pod/VM    │                 │   │
│  │    │  (Primary)          │      │  (Replica)          │                 │   │
│  │    │                     │      │                     │                 │   │
│  │    │  Installed:         │      │  Installed:         │                 │   │
│  │    │  - Ansible 2.15+    │      │  - Ansible 2.15+    │                 │   │
│  │    │  - Python 3.9+      │      │  - Python 3.9+      │                 │   │
│  │    │  - SSH client       │      │  - SSH client       │                 │   │
│  │    │  - Git              │      │  - Git              │                 │   │
│  │    └──────────┬──────────┘      └──────────┬──────────┘                 │   │
│  │               │                            │                             │   │
│  │               └────────────┬───────────────┘                             │   │
│  │                            │                                              │   │
│  └────────────────────────────┼──────────────────────────────────────────────┘   │
│                               │ SSH (22)                                        │
│                               ▼                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    TARGET INFRASTRUCTURE ZONE                            │   │
│  │                  (e.g., Application Subnet)                              │   │
│  │                                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                   │   │
│  │  │ rabbitmq-01  │  │ rabbitmq-02  │  │ rabbitmq-03  │                   │   │
│  │  │  RHEL 8      │  │  RHEL 8      │  │  RHEL 8      │                   │   │
│  │  │              │  │              │  │              │                   │   │
│  │  │ ansible user │  │ ansible user │  │ ansible user │                   │   │
│  │  │ (SSH key)    │  │ (SSH key)    │  │ (SSH key)    │                   │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘                   │   │
│  │                                                                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Delegate Installation for Ansible

#### Kubernetes Delegate with Ansible

```yaml
# delegate-values.yaml for Helm installation
delegateName: platform-ansible-delegate
accountId: <YOUR_ACCOUNT_ID>
delegateToken: <YOUR_DELEGATE_TOKEN>
managerEndpoint: https://app.harness.io
delegateDockerImage: harness/delegate:latest
replicas: 2

# Resource allocation
resources:
  limits:
    cpu: "2"
    memory: "4Gi"
  requests:
    cpu: "1"
    memory: "2Gi"

# Custom init script to install Ansible
initScript: |
  #!/bin/bash

  # Install Python and pip
  microdnf install -y python3 python3-pip

  # Install Ansible
  pip3 install ansible==2.15.*

  # Install additional Ansible collections
  ansible-galaxy collection install community.general
  ansible-galaxy collection install ansible.posix

  # Install SSH client
  microdnf install -y openssh-clients

  # Verify installations
  ansible --version
  python3 --version

# Delegate tags for selection
tags:
  - ansible
  - platform
  - linux

# Delegate selectors
delegateSelectors:
  - ansible-delegate
```

#### Docker Delegate with Ansible

```bash
#!/bin/bash
# deploy-docker-delegate.sh

# Variables
DELEGATE_NAME="platform-ansible-delegate"
ACCOUNT_ID="<YOUR_ACCOUNT_ID>"
DELEGATE_TOKEN="<YOUR_DELEGATE_TOKEN>"
MANAGER_URL="https://app.harness.io"

# Create Dockerfile with Ansible
cat << 'DOCKERFILE' > Dockerfile.delegate
FROM harness/delegate:latest

USER root

# Install required packages
RUN microdnf install -y \
    python3 \
    python3-pip \
    openssh-clients \
    git \
    && pip3 install ansible==2.15.* \
    && ansible-galaxy collection install community.general \
    && ansible-galaxy collection install ansible.posix \
    && microdnf clean all

# Create directories
RUN mkdir -p /opt/harness-delegate/.ssh

# Switch back to harness user
USER harness

WORKDIR /opt/harness-delegate
DOCKERFILE

# Build custom delegate image
docker build -t harness-ansible-delegate:latest -f Dockerfile.delegate .

# Create SSH directory for mounting
mkdir -p /opt/delegate/ssh

# Run delegate
docker run -d \
  --name ${DELEGATE_NAME} \
  --restart unless-stopped \
  -e DELEGATE_NAME=${DELEGATE_NAME} \
  -e NEXT_GEN=true \
  -e DELEGATE_TYPE=DOCKER \
  -e ACCOUNT_ID=${ACCOUNT_ID} \
  -e DELEGATE_TOKEN=${DELEGATE_TOKEN} \
  -e MANAGER_HOST_AND_PORT=${MANAGER_URL} \
  -e LOG_STREAMING_SERVICE_URL=${MANAGER_URL}/log-service/ \
  -e DELEGATE_TAGS="ansible,platform,linux" \
  -v /opt/delegate/ssh:/home/harness/.ssh:ro \
  harness-ansible-delegate:latest
```

### 5.4 Delegate Selection in Pipeline

```yaml
# In pipeline step, select delegate by tags
step:
  type: ShellScript
  spec:
    delegateSelectors:
      - ansible-delegate    # Primary tag
      - platform           # Secondary tag
    # Delegate must have ALL specified tags
```

---

## 6. Pipeline Templates

### 6.1 Template Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        PIPELINE TEMPLATE STRATEGY                                │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    ACCOUNT-LEVEL TEMPLATES                               │   │
│  │                 (Managed by: Platform Admin Team)                        │   │
│  │                                                                          │   │
│  │  Templates shared across entire organization:                            │   │
│  │  ├── Approval-Stage-Template         (Standard approval workflow)        │   │
│  │  ├── Notification-Step-Template      (Slack/Email notifications)         │   │
│  │  ├── Security-Scan-Stage-Template    (Common security scanning)          │   │
│  │  └── Compliance-Check-Template       (Policy compliance checks)          │   │
│  │                                                                          │   │
│  │  Reference: account.template_name                                        │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                   ORGANIZATION-LEVEL TEMPLATES                           │   │
│  │                  (Managed by: Org Admin Team)                            │   │
│  │                                                                          │   │
│  │  Templates for platform-engineering organization:                        │   │
│  │  ├── Ansible-Deploy-Stage-Template   (Standard Ansible deployment)       │   │
│  │  ├── Infrastructure-Validate-Template (Pre-deploy validation)            │   │
│  │  ├── Rollback-Stage-Template         (Standard rollback procedure)       │   │
│  │  └── Post-Deploy-Verify-Template     (Health check template)             │   │
│  │                                                                          │   │
│  │  Reference: org.template_name                                            │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                     PROJECT-LEVEL TEMPLATES                              │   │
│  │                    (Managed by: Project Team)                            │   │
│  │                                                                          │   │
│  │  Templates specific to rabbitmq-cluster project:                         │   │
│  │  ├── RabbitMQ-Health-Check-Step      (RabbitMQ-specific health check)    │   │
│  │  ├── RabbitMQ-Cluster-Validate-Step  (Cluster status validation)         │   │
│  │  └── RabbitMQ-User-Setup-Step        (User/vhost configuration)          │   │
│  │                                                                          │   │
│  │  Reference: template_name (within project)                               │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Organization-Level Ansible Stage Template

```yaml
# Template: Ansible-Deploy-Stage-Template
# Scope: Organization (platform-engineering)
# Location: Harness UI → Organization → Templates → + New Template → Stage

template:
  name: Ansible Deploy Stage Template
  identifier: ansible_deploy_stage_template
  versionLabel: "1.0.0"
  type: Stage
  orgIdentifier: platform_engineering
  spec:
    type: Custom
    spec:
      execution:
        steps:
          - step:
              name: Clone Repository
              identifier: clone_repo
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      WORK_DIR="/tmp/ansible-${HARNESS_BUILD_ID}"

                      echo "Cloning repository: <+stage.variables.git_repo_url>"
                      rm -rf $WORK_DIR
                      git clone <+stage.variables.git_repo_url> $WORK_DIR
                      cd $WORK_DIR
                      git checkout <+stage.variables.git_branch>

                      echo "Repository cloned successfully"
                      echo "Commit: $(git rev-parse HEAD)"
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
                outputVariables:
                  - name: WORK_DIR
                    type: String
                    value: /tmp/ansible-${HARNESS_BUILD_ID}
              timeout: 5m

          - step:
              name: Setup SSH Key
              identifier: setup_ssh
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

                      # Write SSH key from secret
                      cat << 'SSHKEY' > ~/.ssh/id_rsa
                      <+secrets.getValue(stage.variables.ssh_key_secret)>
                      SSHKEY

                      chmod 600 ~/.ssh/id_rsa

                      echo "SSH key configured"
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
              timeout: 2m

          - step:
              name: Run Ansible Playbook
              identifier: run_ansible
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      cd <+execution.steps.clone_repo.output.outputVariables.WORK_DIR>/<+stage.variables.ansible_dir>

                      echo "Running Ansible Playbook"
                      echo "Inventory: <+stage.variables.inventory_file>"
                      echo "Playbook: <+stage.variables.playbook_file>"

                      export ANSIBLE_HOST_KEY_CHECKING=False

                      # Export any additional environment variables
                      <+stage.variables.env_exports>

                      ansible-playbook \
                        -i <+stage.variables.inventory_file> \
                        <+stage.variables.playbook_file> \
                        <+stage.variables.extra_vars> \
                        -v

                      echo "Ansible playbook completed successfully"
                delegateSelectors:
                  - <+stage.variables.delegate_selector>
                environmentVariables: <+stage.variables.ansible_env_vars>
              timeout: <+stage.variables.timeout>
              failureStrategies:
                - onFailure:
                    errors:
                      - AllErrors
                    action:
                      type: StageRollback

    variables:
      - name: git_repo_url
        type: String
        description: "Git repository URL"
        required: true
      - name: git_branch
        type: String
        description: "Git branch to deploy"
        required: true
        default: main
      - name: ansible_dir
        type: String
        description: "Directory containing ansible files (relative to repo root)"
        required: true
        default: ansible
      - name: inventory_file
        type: String
        description: "Path to inventory file (relative to ansible_dir)"
        required: true
      - name: playbook_file
        type: String
        description: "Path to playbook file (relative to ansible_dir)"
        required: true
        default: playbooks/deploy.yml
      - name: ssh_key_secret
        type: String
        description: "Reference to SSH key secret"
        required: true
      - name: delegate_selector
        type: String
        description: "Delegate selector tag"
        required: true
        default: ansible-delegate
      - name: extra_vars
        type: String
        description: "Extra variables to pass to ansible-playbook (-e flags)"
        required: false
        default: ""
      - name: env_exports
        type: String
        description: "Environment variable export commands"
        required: false
        default: ""
      - name: ansible_env_vars
        type: String
        description: "Environment variables for Ansible (JSON array)"
        required: false
        default: "[]"
      - name: timeout
        type: String
        description: "Timeout for ansible playbook"
        required: false
        default: "30m"
```

### 6.3 Account-Level Approval Stage Template

```yaml
# Template: Standard-Approval-Stage-Template
# Scope: Account
# Location: Account Settings → Templates → + New Template → Stage

template:
  name: Standard Approval Stage Template
  identifier: standard_approval_stage_template
  versionLabel: "1.0.0"
  type: Stage
  spec:
    type: Approval
    spec:
      execution:
        steps:
          - step:
              name: Pre-Approval Notification
              identifier: pre_approval_notification
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash

                      # Send Slack notification (if webhook configured)
                      if [ -n "<+stage.variables.slack_webhook>" ]; then
                        curl -X POST -H 'Content-type: application/json' \
                          --data "{
                            \"text\": \"Deployment Approval Required\",
                            \"blocks\": [
                              {
                                \"type\": \"section\",
                                \"text\": {
                                  \"type\": \"mrkdwn\",
                                  \"text\": \"*Deployment Approval Required*\n\n*Pipeline:* <+pipeline.name>\n*Environment:* <+stage.variables.target_environment>\n*Triggered By:* <+pipeline.triggeredBy.name>\n*Execution URL:* <+pipeline.execution.url>\"
                                }
                              }
                            ]
                          }" \
                          <+stage.variables.slack_webhook>
                      fi
              timeout: 2m
              when:
                stageStatus: Success

          - step:
              name: Approval Gate
              identifier: approval_gate
              type: HarnessApproval
              spec:
                approvalMessage: |
                  <+stage.variables.approval_message>

                  ══════════════════════════════════════════
                  Pipeline: <+pipeline.name>
                  Environment: <+stage.variables.target_environment>
                  Triggered By: <+pipeline.triggeredBy.name>
                  ══════════════════════════════════════════

                  Please review and approve to proceed.
                includePipelineExecutionHistory: true
                approvers:
                  userGroups: <+stage.variables.approver_groups>
                  minimumCount: <+stage.variables.min_approvers>
                  disallowPipelineExecutor: <+stage.variables.disallow_executor>
                approverInputs:
                  - name: approval_reason
                    defaultValue: ""
                  - name: change_ticket
                    defaultValue: ""
              timeout: <+stage.variables.approval_timeout>

          - step:
              name: Post-Approval Notification
              identifier: post_approval_notification
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash

                      echo "Approval received, proceeding with deployment"
                      echo "Approved by: <+approval.approvers>"
                      echo "Approval time: $(date)"
              timeout: 2m

    variables:
      - name: approval_message
        type: String
        description: "Custom approval message"
        required: true
        default: "Deployment approval required"
      - name: target_environment
        type: String
        description: "Target environment name"
        required: true
      - name: approver_groups
        type: String
        description: "User groups who can approve (JSON array)"
        required: true
        default: '["_project_all_users"]'
      - name: min_approvers
        type: Number
        description: "Minimum number of approvals required"
        required: true
        default: 1
      - name: disallow_executor
        type: String
        description: "Prevent pipeline executor from approving"
        required: false
        default: "false"
      - name: approval_timeout
        type: String
        description: "Timeout for approval"
        required: false
        default: "1d"
      - name: slack_webhook
        type: String
        description: "Slack webhook URL for notifications"
        required: false
        default: ""
```

### 6.4 Project-Level Step Template

```yaml
# Template: RabbitMQ-Health-Check-Step
# Scope: Project (rabbitmq-cluster)

template:
  name: RabbitMQ Health Check Step
  identifier: rabbitmq_health_check_step
  versionLabel: "1.0.0"
  type: Step
  projectIdentifier: rabbitmq_cluster
  orgIdentifier: platform_engineering
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

            echo "═══════════════════════════════════════════════════"
            echo "       RabbitMQ Cluster Health Check"
            echo "═══════════════════════════════════════════════════"

            MASTER_NODE="<+step.variables.master_node>"
            ADMIN_USER="<+step.variables.admin_user>"
            ADMIN_PASS="<+secrets.getValue(step.variables.admin_password_secret)>"
            EXPECTED_NODES=<+step.variables.expected_nodes>

            # Function to check API
            check_api() {
              local endpoint=$1
              local response=$(curl -s -u ${ADMIN_USER}:${ADMIN_PASS} \
                "http://${MASTER_NODE}:15672/api/${endpoint}" \
                -w "\n%{http_code}")
              local http_code=$(echo "$response" | tail -1)
              local body=$(echo "$response" | head -n -1)

              if [ "$http_code" != "200" ]; then
                echo "ERROR: API call failed with status $http_code"
                return 1
              fi
              echo "$body"
            }

            # Check 1: Cluster Status
            echo ""
            echo "Check 1: Cluster Status"
            echo "───────────────────────────────────────────────────"
            CLUSTER_NAME=$(check_api "cluster-name" | jq -r '.name')
            echo "Cluster Name: $CLUSTER_NAME"

            # Check 2: Node Count
            echo ""
            echo "Check 2: Node Count"
            echo "───────────────────────────────────────────────────"
            NODES=$(check_api "nodes")
            RUNNING_NODES=$(echo "$NODES" | jq '[.[] | select(.running == true)] | length')
            echo "Running Nodes: $RUNNING_NODES / Expected: $EXPECTED_NODES"

            if [ "$RUNNING_NODES" -lt "$EXPECTED_NODES" ]; then
              echo "ERROR: Not all nodes are running!"
              exit 1
            fi

            # Check 3: Node Health
            echo ""
            echo "Check 3: Node Health"
            echo "───────────────────────────────────────────────────"
            echo "$NODES" | jq -r '.[] | "Node: \(.name) | Running: \(.running) | Memory: \((.mem_used/1024/1024)|floor)MB"'

            # Check 4: Alarms
            echo ""
            echo "Check 4: Alarms Check"
            echo "───────────────────────────────────────────────────"
            ALARMS=$(check_api "health/checks/alarms")
            ALARM_STATUS=$(echo "$ALARMS" | jq -r '.status')

            if [ "$ALARM_STATUS" != "ok" ]; then
              echo "WARNING: Alarms detected!"
              echo "$ALARMS" | jq '.'
            else
              echo "No alarms detected"
            fi

            # Check 5: Queue Status
            echo ""
            echo "Check 5: Queue Summary"
            echo "───────────────────────────────────────────────────"
            QUEUES=$(check_api "queues")
            QUEUE_COUNT=$(echo "$QUEUES" | jq 'length')
            TOTAL_MESSAGES=$(echo "$QUEUES" | jq '[.[].messages] | add // 0')
            echo "Total Queues: $QUEUE_COUNT"
            echo "Total Messages: $TOTAL_MESSAGES"

            echo ""
            echo "═══════════════════════════════════════════════════"
            echo "       Health Check Completed Successfully"
            echo "═══════════════════════════════════════════════════"
      delegateSelectors:
        - <+step.variables.delegate_selector>
    timeout: 5m

  variables:
    - name: master_node
      type: String
      description: "RabbitMQ master node hostname or IP"
      required: true
    - name: admin_user
      type: String
      description: "RabbitMQ admin username"
      required: true
      default: admin
    - name: admin_password_secret
      type: String
      description: "Reference to admin password secret"
      required: true
    - name: expected_nodes
      type: Number
      description: "Expected number of cluster nodes"
      required: true
      default: 3
    - name: delegate_selector
      type: String
      description: "Delegate selector tag"
      required: false
      default: ansible-delegate
```

---

## 7. Approval Workflow Design

### 7.1 Approval Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      APPROVAL WORKFLOW ARCHITECTURE                              │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    ENVIRONMENT-BASED APPROVAL MATRIX                     │   │
│  │                                                                          │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │   │
│  │  │ DEVELOPMENT                                                      │    │   │
│  │  │ ├── Approval Required: NO                                        │    │   │
│  │  │ ├── Auto-deploy on: develop branch merge                         │    │   │
│  │  │ └── Notify: Team Slack channel                                   │    │   │
│  │  └─────────────────────────────────────────────────────────────────┘    │   │
│  │                              │                                           │   │
│  │                              ▼                                           │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │   │
│  │  │ STAGING                                                          │    │   │
│  │  │ ├── Approval Required: YES (1 approver)                          │    │   │
│  │  │ ├── Approvers: Project Team Members                              │    │   │
│  │  │ ├── Auto-deploy after approval                                   │    │   │
│  │  │ └── Notify: Team Slack + Email                                   │    │   │
│  │  └─────────────────────────────────────────────────────────────────┘    │   │
│  │                              │                                           │   │
│  │                              ▼                                           │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │   │
│  │  │ PRODUCTION                                                       │    │   │
│  │  │ ├── Approval Required: YES (2 approvers)                         │    │   │
│  │  │ ├── Approvers: Tech Lead + Manager                               │    │   │
│  │  │ ├── Required Inputs: Change Ticket, Maintenance Window           │    │   │
│  │  │ ├── Executor cannot self-approve                                 │    │   │
│  │  │ ├── Deployment Window: Business hours only (optional)            │    │   │
│  │  │ └── Notify: All stakeholders + PagerDuty                         │    │   │
│  │  └─────────────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                     EMERGENCY DEPLOYMENT PATH                            │   │
│  │                                                                          │   │
│  │  For critical hotfixes:                                                  │   │
│  │  ├── Skip staging (with VP approval)                                     │   │
│  │  ├── Single senior approver                                              │   │
│  │  ├── Mandatory post-deployment review                                    │   │
│  │  └── Auto-create incident ticket                                         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 User Groups for Approval

```yaml
# User Groups Configuration
# Location: Project Settings → Access Control → User Groups

user_groups:
  # Development Team
  - name: RabbitMQ Dev Team
    identifier: rabbitmq_dev_team
    description: Development team members
    users:
      - dev1@acme-corp.com
      - dev2@acme-corp.com
    roles:
      - Pipeline Executor
      - Service Viewer

  # QA/Staging Approvers
  - name: RabbitMQ QA Approvers
    identifier: rabbitmq_qa_approvers
    description: QA team who can approve staging deployments
    users:
      - qa1@acme-corp.com
      - qa2@acme-corp.com
    roles:
      - Pipeline Executor

  # Production Approvers (Tech Leads)
  - name: RabbitMQ Tech Leads
    identifier: rabbitmq_tech_leads
    description: Technical leads who can approve production
    users:
      - techlead1@acme-corp.com
      - techlead2@acme-corp.com
    roles:
      - Pipeline Executor

  # Production Approvers (Managers)
  - name: Platform Engineering Managers
    identifier: platform_eng_managers
    description: Engineering managers for production approval
    users:
      - manager1@acme-corp.com
      - manager2@acme-corp.com
    roles:
      - Pipeline Executor
      - Pipeline Admin
```

### 7.3 Approval Stage Implementation

```yaml
# Production Approval Stage
- stage:
    name: Production Approval
    identifier: production_approval
    description: Approval gate before production deployment
    type: Approval
    spec:
      execution:
        steps:
          # Step 1: Send notification
          - step:
              name: Send Approval Request
              identifier: send_approval_request
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash

                      echo "Sending approval notifications..."

                      # Slack notification
                      curl -X POST -H 'Content-type: application/json' \
                        --data '{
                          "text": "Production Deployment Approval Required",
                          "blocks": [
                            {
                              "type": "header",
                              "text": {
                                "type": "plain_text",
                                "text": "Production Deployment Approval Required"
                              }
                            },
                            {
                              "type": "section",
                              "fields": [
                                {"type": "mrkdwn", "text": "*Pipeline:*\n<+pipeline.name>"},
                                {"type": "mrkdwn", "text": "*Service:*\nRabbitMQ Cluster"},
                                {"type": "mrkdwn", "text": "*Triggered By:*\n<+pipeline.triggeredBy.name>"},
                                {"type": "mrkdwn", "text": "*Branch:*\n<+pipeline.variables.git_branch>"}
                              ]
                            },
                            {
                              "type": "actions",
                              "elements": [
                                {
                                  "type": "button",
                                  "text": {"type": "plain_text", "text": "Review in Harness"},
                                  "url": "<+pipeline.execution.url>"
                                }
                              ]
                            }
                          ]
                        }' \
                        <+secrets.getValue("account.slack_webhook")>
              timeout: 2m

          # Step 2: Approval Gate
          - step:
              name: Production Deployment Approval
              identifier: prod_approval_gate
              type: HarnessApproval
              spec:
                approvalMessage: |
                  ╔══════════════════════════════════════════════════════════╗
                  ║      PRODUCTION DEPLOYMENT APPROVAL REQUIRED             ║
                  ╠══════════════════════════════════════════════════════════╣
                  ║                                                          ║
                  ║  Service: RabbitMQ 4.x Cluster                           ║
                  ║  Environment: PRODUCTION                                 ║
                  ║  Triggered By: <+pipeline.triggeredBy.name>              ║
                  ║                                                          ║
                  ║  Changes:                                                ║
                  ║  - Branch: <+pipeline.variables.git_branch>              ║
                  ║  - Commit: <+pipeline.variables.git_commit>              ║
                  ║                                                          ║
                  ║  Pre-Production Validation:                              ║
                  ║  - Dev Deployment: ✓ Passed                              ║
                  ║  - Staging Deployment: ✓ Passed                          ║
                  ║  - Integration Tests: ✓ Passed                           ║
                  ║                                                          ║
                  ╚══════════════════════════════════════════════════════════╝

                  Please provide the required information and approve.
                includePipelineExecutionHistory: true
                approvers:
                  userGroups:
                    - rabbitmq_tech_leads
                    - platform_eng_managers
                  minimumCount: 2
                  disallowPipelineExecutor: true
                approverInputs:
                  - name: change_ticket
                    defaultValue: ""
                  - name: maintenance_window
                    defaultValue: ""
                  - name: rollback_plan_reviewed
                    defaultValue: "No"
                isAutoRejectEnabled: false
              timeout: 7d
              failureStrategies:
                - onFailure:
                    errors:
                      - ApprovalRejection
                    action:
                      type: MarkAsFailure

          # Step 3: Post-approval validation
          - step:
              name: Validate Approval Inputs
              identifier: validate_approval
              type: ShellScript
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e

                      echo "Validating approval inputs..."

                      CHANGE_TICKET="<+execution.steps.prod_approval_gate.output.approverInputs.change_ticket>"
                      MAINTENANCE_WINDOW="<+execution.steps.prod_approval_gate.output.approverInputs.maintenance_window>"
                      ROLLBACK_REVIEWED="<+execution.steps.prod_approval_gate.output.approverInputs.rollback_plan_reviewed>"

                      # Validate change ticket format
                      if [[ ! "$CHANGE_TICKET" =~ ^CHG[0-9]{6}$ ]]; then
                        echo "ERROR: Invalid change ticket format. Expected: CHG######"
                        exit 1
                      fi

                      # Validate rollback plan was reviewed
                      if [ "$ROLLBACK_REVIEWED" != "Yes" ]; then
                        echo "ERROR: Rollback plan must be reviewed before production deployment"
                        exit 1
                      fi

                      echo "Approval validation passed"
                      echo "Change Ticket: $CHANGE_TICKET"
                      echo "Maintenance Window: $MAINTENANCE_WINDOW"
              timeout: 5m
```

---

## 8. Complete RabbitMQ Example

### 8.1 Full Pipeline YAML

```yaml
pipeline:
  name: Deploy RabbitMQ Cluster
  identifier: deploy_rabbitmq_cluster
  projectIdentifier: rabbitmq_cluster
  orgIdentifier: platform_engineering
  description: |
    Complete deployment pipeline for RabbitMQ 4.x cluster
    using Ansible automation via Harness CD.
  tags:
    rabbitmq: ""
    ansible: ""
    infrastructure: ""

  properties:
    ci:
      codebase:
        connectorRef: github_rabbitmq_deployment
        repoName: rabbitmq-deployment
        build: <+input>

  variables:
    - name: git_repo_url
      type: String
      description: Git repository URL
      value: https://github.com/acme-corp/rabbitmq-deployment.git
    - name: git_branch
      type: String
      description: Branch to deploy
      value: <+input>.default(main)
    - name: rabbitmq_version
      type: String
      description: RabbitMQ version
      value: "4.0.2"
    - name: erlang_version
      type: String
      description: Erlang version
      value: "26.2"

  stages:
    # =========================================================================
    # STAGE 1: Pre-Flight Checks
    # =========================================================================
    - stage:
        name: Pre-Flight Checks
        identifier: preflight_checks
        description: Validate environment before deployment
        type: Custom
        spec:
          execution:
            steps:
              - step:
                  name: Validate Inputs
                  identifier: validate_inputs
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
                          echo "       Pre-Flight Validation"
                          echo "═══════════════════════════════════════════"

                          echo "Git Branch: <+pipeline.variables.git_branch>"
                          echo "RabbitMQ Version: <+pipeline.variables.rabbitmq_version>"
                          echo "Erlang Version: <+pipeline.variables.erlang_version>"

                          # Validate branch name
                          if [[ ! "<+pipeline.variables.git_branch>" =~ ^(main|develop|staging|release/.*)$ ]]; then
                            echo "WARNING: Deploying from non-standard branch"
                          fi

                          echo "Validation completed"
                    delegateSelectors:
                      - ansible-delegate
                  timeout: 5m

              - step:
                  name: Test Connectivity
                  identifier: test_connectivity
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          echo "Testing SSH connectivity to nodes..."

                          # Setup SSH key
                          mkdir -p ~/.ssh
                          cat << 'SSHKEY' > ~/.ssh/id_rsa
                          <+secrets.getValue("rabbitmq_nodes_ssh_key")>
                          SSHKEY
                          chmod 600 ~/.ssh/id_rsa

                          # Test nodes (using pipeline variables or hardcoded for POC)
                          NODES=("rabbitmq-01" "rabbitmq-02" "rabbitmq-03")

                          for node in "${NODES[@]}"; do
                            echo "Testing $node..."
                            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                              ansible@$node "hostname" && echo "  ✓ $node OK" || echo "  ✗ $node FAILED"
                          done
                    delegateSelectors:
                      - ansible-delegate
                  timeout: 5m

    # =========================================================================
    # STAGE 2: Deploy to Development
    # =========================================================================
    - stage:
        name: Deploy to Development
        identifier: deploy_dev
        description: Deploy to development environment
        type: Deployment
        spec:
          deploymentType: CustomDeployment
          service:
            serviceRef: rabbitmq_cluster_service
          environment:
            environmentRef: development
            infrastructureDefinitions:
              - identifier: rabbitmq_infra_dev
          execution:
            steps:
              - step:
                  name: Clone Ansible Repository
                  identifier: clone_repo_dev
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          WORK_DIR="/tmp/ansible-rabbitmq-<+pipeline.executionId>"

                          echo "Cloning repository..."
                          rm -rf $WORK_DIR
                          git clone <+pipeline.variables.git_repo_url> $WORK_DIR
                          cd $WORK_DIR
                          git checkout <+pipeline.variables.git_branch>

                          echo "Cloned to: $WORK_DIR"
                          echo "Commit: $(git rev-parse HEAD)"
                    delegateSelectors:
                      - ansible-delegate
                    outputVariables:
                      - name: ANSIBLE_WORK_DIR
                        type: String
                        value: /tmp/ansible-rabbitmq-<+pipeline.executionId>
                  timeout: 5m

              - step:
                  name: Run Ansible Deployment
                  identifier: run_ansible_dev
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          cd <+execution.steps.clone_repo_dev.output.outputVariables.ANSIBLE_WORK_DIR>/ansible

                          # Setup SSH
                          mkdir -p ~/.ssh
                          cat << 'SSHKEY' > ~/.ssh/id_rsa
                          <+secrets.getValue("rabbitmq_nodes_ssh_key")>
                          SSHKEY
                          chmod 600 ~/.ssh/id_rsa

                          # Set environment variables
                          export ANSIBLE_HOST_KEY_CHECKING=False
                          export RABBITMQ_ADMIN_PASSWORD="<+secrets.getValue("rabbitmq_admin_password")>"
                          export RABBITMQ_APP_PASSWORD="<+secrets.getValue("rabbitmq_app_password")>"
                          export RABBITMQ_ERLANG_COOKIE="<+secrets.getValue("rabbitmq_erlang_cookie")>"

                          echo "Running Ansible playbook for Development..."

                          ansible-playbook \
                            -i inventory/dev/hosts.yml \
                            playbooks/deploy.yml \
                            -e "environment_name=dev" \
                            -e "rabbitmq_version=<+pipeline.variables.rabbitmq_version>" \
                            -e "erlang_version=<+pipeline.variables.erlang_version>" \
                            -v

                          echo "Ansible deployment completed"
                    delegateSelectors:
                      - ansible-delegate
                  timeout: 30m
                  failureStrategies:
                    - onFailure:
                        errors:
                          - AllErrors
                        action:
                          type: StageRollback

              - stepGroup:
                  name: Validation
                  identifier: validation_dev
                  steps:
                    - step:
                        name: Cluster Health Check
                        identifier: health_check_dev
                        type: ShellScript
                        spec:
                          shell: Bash
                          source:
                            type: Inline
                            spec:
                              script: |
                                #!/bin/bash
                                set -e

                                ADMIN_USER="admin"
                                ADMIN_PASS="<+secrets.getValue("rabbitmq_admin_password")>"
                                MASTER="rabbitmq-01"

                                echo "Checking cluster status..."

                                # Check nodes
                                NODES=$(curl -s -u $ADMIN_USER:$ADMIN_PASS \
                                  http://$MASTER:15672/api/nodes | jq 'length')

                                echo "Running nodes: $NODES"

                                if [ "$NODES" -lt 3 ]; then
                                  echo "ERROR: Expected 3 nodes, found $NODES"
                                  exit 1
                                fi

                                # Check alarms
                                ALARMS=$(curl -s -u $ADMIN_USER:$ADMIN_PASS \
                                  http://$MASTER:15672/api/health/checks/alarms)

                                if echo "$ALARMS" | grep -q '"status":"ok"'; then
                                  echo "No alarms - cluster healthy"
                                else
                                  echo "WARNING: Alarms detected"
                                fi
                          delegateSelectors:
                            - ansible-delegate
                        timeout: 5m

                    - step:
                        name: Integration Test
                        identifier: integration_test_dev
                        type: ShellScript
                        spec:
                          shell: Bash
                          source:
                            type: Inline
                            spec:
                              script: |
                                #!/bin/bash
                                set -e

                                ADMIN_USER="admin"
                                ADMIN_PASS="<+secrets.getValue("rabbitmq_admin_password")>"
                                MASTER="rabbitmq-01"

                                echo "Running integration tests..."

                                # Create test queue
                                curl -s -u $ADMIN_USER:$ADMIN_PASS -X PUT \
                                  -H "content-type: application/json" \
                                  -d '{"durable":true,"arguments":{"x-queue-type":"quorum"}}' \
                                  http://$MASTER:15672/api/queues/%2F/harness-test-queue

                                # Publish message
                                curl -s -u $ADMIN_USER:$ADMIN_PASS -X POST \
                                  -H "content-type: application/json" \
                                  -d '{"properties":{},"routing_key":"harness-test-queue","payload":"test","payload_encoding":"string"}' \
                                  http://$MASTER:15672/api/exchanges/%2F/amq.default/publish

                                # Get message
                                MSG=$(curl -s -u $ADMIN_USER:$ADMIN_PASS -X POST \
                                  -H "content-type: application/json" \
                                  -d '{"count":1,"ackmode":"ack_requeue_false","encoding":"auto"}' \
                                  http://$MASTER:15672/api/queues/%2F/harness-test-queue/get)

                                # Cleanup
                                curl -s -u $ADMIN_USER:$ADMIN_PASS -X DELETE \
                                  http://$MASTER:15672/api/queues/%2F/harness-test-queue

                                echo "Integration tests passed"
                          delegateSelectors:
                            - ansible-delegate
                        timeout: 5m

            rollbackSteps:
              - step:
                  name: Rollback Development
                  identifier: rollback_dev
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          echo "Initiating rollback for Development..."

                          cd <+execution.steps.clone_repo_dev.output.outputVariables.ANSIBLE_WORK_DIR>/ansible

                          ansible-playbook \
                            -i inventory/dev/hosts.yml \
                            playbooks/rollback.yml \
                            -e "environment_name=dev" \
                            -v
                    delegateSelectors:
                      - ansible-delegate
                  timeout: 20m

    # =========================================================================
    # STAGE 3: Staging Approval
    # =========================================================================
    - stage:
        name: Staging Approval
        identifier: staging_approval
        description: Approval before staging deployment
        type: Approval
        spec:
          execution:
            steps:
              - step:
                  name: Approve Staging Deployment
                  identifier: approve_staging
                  type: HarnessApproval
                  spec:
                    approvalMessage: |
                      Development deployment successful!

                      Please approve to deploy to Staging environment.

                      Pipeline: <+pipeline.name>
                      Branch: <+pipeline.variables.git_branch>
                    includePipelineExecutionHistory: true
                    approvers:
                      userGroups:
                        - rabbitmq_qa_approvers
                        - rabbitmq_dev_team
                      minimumCount: 1
                      disallowPipelineExecutor: false
                  timeout: 1d
        when:
          pipelineStatus: Success

    # =========================================================================
    # STAGE 4: Deploy to Staging
    # =========================================================================
    - stage:
        name: Deploy to Staging
        identifier: deploy_staging
        description: Deploy to staging environment
        type: Deployment
        spec:
          deploymentType: CustomDeployment
          service:
            serviceRef: rabbitmq_cluster_service
          environment:
            environmentRef: staging
            infrastructureDefinitions:
              - identifier: rabbitmq_infra_staging
          execution:
            steps:
              # Similar steps as Development with staging inventory
              - step:
                  name: Clone Ansible Repository
                  identifier: clone_repo_staging
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e
                          WORK_DIR="/tmp/ansible-rabbitmq-<+pipeline.executionId>"
                          git clone <+pipeline.variables.git_repo_url> $WORK_DIR
                          cd $WORK_DIR && git checkout <+pipeline.variables.git_branch>
                    delegateSelectors:
                      - ansible-delegate
                    outputVariables:
                      - name: ANSIBLE_WORK_DIR
                        type: String
                        value: /tmp/ansible-rabbitmq-<+pipeline.executionId>
                  timeout: 5m

              - step:
                  name: Run Ansible Deployment
                  identifier: run_ansible_staging
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e
                          cd <+execution.steps.clone_repo_staging.output.outputVariables.ANSIBLE_WORK_DIR>/ansible

                          # Setup SSH and environment variables (same as dev)
                          mkdir -p ~/.ssh
                          cat << 'SSHKEY' > ~/.ssh/id_rsa
                          <+secrets.getValue("rabbitmq_nodes_ssh_key")>
                          SSHKEY
                          chmod 600 ~/.ssh/id_rsa

                          export ANSIBLE_HOST_KEY_CHECKING=False
                          export RABBITMQ_ADMIN_PASSWORD="<+secrets.getValue("rabbitmq_admin_password")>"
                          export RABBITMQ_ERLANG_COOKIE="<+secrets.getValue("rabbitmq_erlang_cookie")>"

                          ansible-playbook \
                            -i inventory/staging/hosts.yml \
                            playbooks/deploy.yml \
                            -e "environment_name=staging" \
                            -v
                    delegateSelectors:
                      - ansible-delegate
                  timeout: 30m

    # =========================================================================
    # STAGE 5: Production Approval
    # =========================================================================
    - stage:
        name: Production Approval
        identifier: production_approval
        description: Approval gate for production deployment
        type: Approval
        spec:
          execution:
            steps:
              - step:
                  name: Production Deployment Approval
                  identifier: approve_production
                  type: HarnessApproval
                  spec:
                    approvalMessage: |
                      ╔══════════════════════════════════════════════════════════╗
                      ║      PRODUCTION DEPLOYMENT APPROVAL REQUIRED             ║
                      ╠══════════════════════════════════════════════════════════╣
                      ║                                                          ║
                      ║  Service: RabbitMQ 4.x Cluster                           ║
                      ║  Environment: PRODUCTION                                 ║
                      ║                                                          ║
                      ║  Pre-Production Results:                                 ║
                      ║  ✓ Development - Passed                                  ║
                      ║  ✓ Staging - Passed                                      ║
                      ║                                                          ║
                      ║  Required Information:                                   ║
                      ║  - Change Management Ticket (CHG######)                  ║
                      ║  - Maintenance Window                                    ║
                      ║                                                          ║
                      ╚══════════════════════════════════════════════════════════╝
                    includePipelineExecutionHistory: true
                    approvers:
                      userGroups:
                        - rabbitmq_tech_leads
                        - platform_eng_managers
                      minimumCount: 2
                      disallowPipelineExecutor: true
                    approverInputs:
                      - name: change_ticket
                        defaultValue: ""
                      - name: maintenance_window
                        defaultValue: ""
                  timeout: 7d
        when:
          pipelineStatus: Success

    # =========================================================================
    # STAGE 6: Deploy to Production
    # =========================================================================
    - stage:
        name: Deploy to Production
        identifier: deploy_production
        description: Deploy to production environment
        type: Deployment
        spec:
          deploymentType: CustomDeployment
          service:
            serviceRef: rabbitmq_cluster_service
          environment:
            environmentRef: production
            infrastructureDefinitions:
              - identifier: rabbitmq_infra_production
          execution:
            steps:
              - step:
                  name: Pre-Production Backup
                  identifier: pre_prod_backup
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          echo "Creating pre-deployment backup..."

                          # SSH to master and create backup
                          ssh -o StrictHostKeyChecking=no ansible@rabbitmq-prod-01 \
                            "sudo rabbitmqctl export_definitions /backup/rabbitmq/definitions-$(date +%Y%m%d-%H%M%S).json"

                          echo "Backup completed"
                    delegateSelectors:
                      - ansible-delegate
                  timeout: 10m

              - step:
                  name: Clone Ansible Repository
                  identifier: clone_repo_prod
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e
                          WORK_DIR="/tmp/ansible-rabbitmq-<+pipeline.executionId>"
                          git clone <+pipeline.variables.git_repo_url> $WORK_DIR
                          cd $WORK_DIR && git checkout <+pipeline.variables.git_branch>
                    delegateSelectors:
                      - ansible-delegate
                    outputVariables:
                      - name: ANSIBLE_WORK_DIR
                        type: String
                        value: /tmp/ansible-rabbitmq-<+pipeline.executionId>
                  timeout: 5m

              - step:
                  name: Run Ansible Deployment
                  identifier: run_ansible_prod
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e
                          cd <+execution.steps.clone_repo_prod.output.outputVariables.ANSIBLE_WORK_DIR>/ansible

                          mkdir -p ~/.ssh
                          cat << 'SSHKEY' > ~/.ssh/id_rsa
                          <+secrets.getValue("rabbitmq_nodes_ssh_key")>
                          SSHKEY
                          chmod 600 ~/.ssh/id_rsa

                          export ANSIBLE_HOST_KEY_CHECKING=False
                          export RABBITMQ_ADMIN_PASSWORD="<+secrets.getValue("rabbitmq_admin_password")>"
                          export RABBITMQ_ERLANG_COOKIE="<+secrets.getValue("rabbitmq_erlang_cookie")>"

                          echo "Deploying to Production..."

                          ansible-playbook \
                            -i inventory/production/hosts.yml \
                            playbooks/deploy.yml \
                            -e "environment_name=production" \
                            -v

                          echo "Production deployment completed"
                    delegateSelectors:
                      - ansible-delegate
                  timeout: 45m
                  failureStrategies:
                    - onFailure:
                        errors:
                          - AllErrors
                        action:
                          type: StageRollback

              - step:
                  name: Production Health Check
                  identifier: health_check_prod
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          echo "Running production health checks..."

                          ADMIN_USER="admin"
                          ADMIN_PASS="<+secrets.getValue("rabbitmq_admin_password")>"
                          MASTER="rabbitmq-prod-01"

                          # Comprehensive health check
                          NODES=$(curl -s -u $ADMIN_USER:$ADMIN_PASS \
                            http://$MASTER:15672/api/nodes | jq 'length')

                          if [ "$NODES" -lt 3 ]; then
                            echo "ERROR: Production cluster unhealthy"
                            exit 1
                          fi

                          echo "Production cluster healthy with $NODES nodes"
                    delegateSelectors:
                      - ansible-delegate
                  timeout: 10m

            rollbackSteps:
              - step:
                  name: Rollback Production
                  identifier: rollback_prod
                  type: ShellScript
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          echo "CRITICAL: Initiating production rollback..."

                          cd <+execution.steps.clone_repo_prod.output.outputVariables.ANSIBLE_WORK_DIR>/ansible

                          ansible-playbook \
                            -i inventory/production/hosts.yml \
                            playbooks/rollback.yml \
                            -e "environment_name=production" \
                            -v

                          echo "Production rollback completed"
                    delegateSelectors:
                      - ansible-delegate
                  timeout: 30m

  notificationRules:
    - name: Pipeline Notifications
      enabled: true
      pipelineEvents:
        - type: AllEvents
      notificationMethod:
        type: Slack
        spec:
          webhookUrl: <+secrets.getValue("account.slack_webhook")>
```

---

## 9. RBAC & Governance

### 9.1 Role-Based Access Control Matrix

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         RBAC MATRIX FOR RABBITMQ PROJECT                         │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    ROLE DEFINITIONS                                      │   │
│  │                                                                          │   │
│  │  VIEWER (Read-Only)                                                      │   │
│  │  ├── View pipelines and executions                                       │   │
│  │  ├── View services and environments                                      │   │
│  │  ├── View deployment history                                             │   │
│  │  └── Cannot execute or modify                                            │   │
│  │                                                                          │   │
│  │  DEVELOPER                                                               │   │
│  │  ├── All Viewer permissions                                              │   │
│  │  ├── Execute pipelines (non-production)                                  │   │
│  │  ├── Create/edit services                                                │   │
│  │  └── Approve staging deployments                                         │   │
│  │                                                                          │   │
│  │  PIPELINE EXECUTOR                                                       │   │
│  │  ├── All Developer permissions                                           │   │
│  │  ├── Execute all pipelines                                               │   │
│  │  ├── Create/edit pipelines                                               │   │
│  │  └── Approve non-production deployments                                  │   │
│  │                                                                          │   │
│  │  PROJECT ADMIN                                                           │   │
│  │  ├── All Pipeline Executor permissions                                   │   │
│  │  ├── Manage project secrets                                              │   │
│  │  ├── Manage project connectors                                           │   │
│  │  ├── Approve production deployments                                      │   │
│  │  └── Manage user access within project                                   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    USER GROUP ASSIGNMENTS                                │   │
│  │                                                                          │   │
│  │  ┌───────────────────────┬─────────────────┬─────────────────────────┐  │   │
│  │  │ User Group            │ Role            │ Approval Permissions    │  │   │
│  │  ├───────────────────────┼─────────────────┼─────────────────────────┤  │   │
│  │  │ rabbitmq_dev_team     │ Developer       │ Staging only            │  │   │
│  │  │ rabbitmq_qa_approvers │ Pipeline Exec   │ Staging only            │  │   │
│  │  │ rabbitmq_tech_leads   │ Project Admin   │ All environments        │  │   │
│  │  │ platform_eng_managers │ Project Admin   │ All environments        │  │   │
│  │  └───────────────────────┴─────────────────┴─────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 9.2 Governance Policies

```yaml
# OPA Policy Example for Production Deployments
# Ensures change ticket is provided for production

package harness.approval

deny[msg] {
  input.pipeline.stages[_].identifier == "deploy_production"
  input.approval.inputs.change_ticket == ""
  msg := "Change ticket is required for production deployment"
}

deny[msg] {
  input.pipeline.stages[_].identifier == "deploy_production"
  not regex.match("^CHG[0-9]{6}$", input.approval.inputs.change_ticket)
  msg := "Invalid change ticket format. Expected: CHG######"
}
```

---

## 10. Best Practices Checklist

### Pre-Implementation Checklist

- [ ] **Harness Setup**
  - [ ] Account hierarchy defined (Account → Org → Project)
  - [ ] User groups created with appropriate roles
  - [ ] Delegates installed and healthy
  - [ ] Secret manager configured

- [ ] **GitHub Setup**
  - [ ] Repository structure follows standards
  - [ ] Branch protection enabled on main
  - [ ] Service account with appropriate permissions
  - [ ] Webhooks configured (if using triggers)

- [ ] **Security**
  - [ ] All secrets stored in Harness Secret Manager
  - [ ] SSH keys are unique per environment
  - [ ] No secrets in Git repository
  - [ ] Audit logging enabled

- [ ] **Pipeline Design**
  - [ ] Templates used for reusable components
  - [ ] Approval gates for production
  - [ ] Rollback steps defined
  - [ ] Notifications configured

### Operational Checklist

- [ ] **Before Each Deployment**
  - [ ] Pre-flight checks pass
  - [ ] Change ticket created (production)
  - [ ] Stakeholders notified
  - [ ] Rollback plan documented

- [ ] **After Each Deployment**
  - [ ] Health checks pass
  - [ ] Monitoring verified
  - [ ] Documentation updated
  - [ ] Post-deployment notification sent

---

## Document Summary

This guide provides a complete enterprise architecture for Harness CD implementation:

| Component | Scope | Location |
|-----------|-------|----------|
| Pipeline Templates | Account/Org | Reusable across projects |
| Secrets | Tiered (Account→Org→Project) | Harness Secret Manager |
| Delegates | Org-scoped with Ansible | Kubernetes/Docker |
| Approvals | Environment-based | 1 (Staging) / 2 (Production) |
| RBAC | Project-level | Role-based user groups |

**Key Files Created:**
1. This architecture guide
2. Complete pipeline YAML
3. Template examples
4. RBAC configuration

---

**End of Document**
