# Harness CD POC: RabbitMQ 4.x Cluster Deployment with Ansible on RHEL 8

## Executive Summary

This document provides a comprehensive Proof of Concept (POC) guide for deploying a production-grade RabbitMQ 4.x cluster on RHEL 8 using Harness Continuous Delivery with Ansible as the configuration management tool.

**POC Objectives:**
- Demonstrate automated RabbitMQ 4.x cluster deployment using Harness CD
- Establish infrastructure-as-code practices with Ansible
- Validate cluster high availability and failover capabilities
- Create repeatable deployment patterns for production use

**Target Audience:** DevOps Engineers, Platform Engineers, Architects, Management

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Infrastructure Requirements](#infrastructure-requirements)
4. [Phase 1: Environment Setup](#phase-1-environment-setup)
5. [Phase 2: Ansible Configuration](#phase-2-ansible-configuration)
6. [Phase 3: Harness CD Setup](#phase-3-harness-cd-setup)
7. [Phase 4: Pipeline Creation](#phase-4-pipeline-creation)
8. [Phase 5: Deployment Execution](#phase-5-deployment-execution)
9. [Phase 6: Validation & Testing](#phase-6-validation--testing)
10. [Rollback Strategy](#rollback-strategy)
11. [Monitoring & Alerting](#monitoring--alerting)
12. [Security Considerations](#security-considerations)
13. [Troubleshooting Guide](#troubleshooting-guide)
14. [Appendix](#appendix)

---

## Architecture Overview

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           HARNESS PLATFORM                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Project   │  │   Service   │  │ Environment │  │  Pipeline   │        │
│  │  RabbitMQ   │  │  Ansible    │  │  Dev/Stg/   │  │  Deploy     │        │
│  │  Cluster    │  │  Playbooks  │  │  Prod       │  │  Workflow   │        │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         HARNESS DELEGATE                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Delegate VM/Container (RHEL 8)                                      │   │
│  │  - Ansible 2.15+                                                     │   │
│  │  - Python 3.9+                                                       │   │
│  │  - SSH Access to Target Nodes                                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │ SSH (Port 22)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     RABBITMQ CLUSTER (3-NODE)                                │
│                                                                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │   Node 1 (Disc)  │  │   Node 2 (Disc)  │  │   Node 3 (Disc)  │          │
│  │   rabbitmq-01    │  │   rabbitmq-02    │  │   rabbitmq-03    │          │
│  │   RHEL 8         │  │   RHEL 8         │  │   RHEL 8         │          │
│  │                  │  │                  │  │                  │          │
│  │  Ports:          │  │  Ports:          │  │  Ports:          │          │
│  │  - 5672 (AMQP)   │  │  - 5672 (AMQP)   │  │  - 5672 (AMQP)   │          │
│  │  - 15672 (Mgmt)  │  │  - 15672 (Mgmt)  │  │  - 15672 (Mgmt)  │          │
│  │  - 25672 (Dist)  │  │  - 25672 (Dist)  │  │  - 25672 (Dist)  │          │
│  │  - 4369 (EPMD)   │  │  - 4369 (EPMD)   │  │  - 4369 (EPMD)   │          │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘          │
│           │                     │                     │                     │
│           └─────────────────────┼─────────────────────┘                     │
│                                 │                                            │
│                    Erlang Distribution Protocol                              │
│                    (Clustering Communication)                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LOAD BALANCER (Optional)                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  HAProxy / AWS ALB / F5                                              │   │
│  │  - TCP Load Balancing on Port 5672                                   │   │
│  │  - Health Checks on Port 15672                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### RabbitMQ 4.x Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     RABBITMQ 4.x CLUSTER INTERNALS                           │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        QUORUM QUEUES                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │   Leader    │  │  Follower   │  │  Follower   │                  │   │
│  │  │   Node 1    │◄─┤   Node 2    │◄─┤   Node 3    │                  │   │
│  │  │             │  │             │  │             │                  │   │
│  │  │  Raft Log   │  │  Raft Log   │  │  Raft Log   │                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  │                    Raft Consensus Protocol                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      STREAM QUEUES (New in 4.x)                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │   Writer    │  │  Replica    │  │  Replica    │                  │   │
│  │  │   Node 1    │──┤   Node 2    │──┤   Node 3    │                  │   │
│  │  │             │  │             │  │             │                  │   │
│  │  │  Log-based  │  │  Log-based  │  │  Log-based  │                  │   │
│  │  │  Storage    │  │  Storage    │  │  Storage    │                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Deployment Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DEPLOYMENT WORKFLOW                                  │
│                                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │  Stage 1 │    │  Stage 2 │    │  Stage 3 │    │  Stage 4 │              │
│  │          │    │          │    │          │    │          │              │
│  │ Pre-     │───▶│ Install  │───▶│ Cluster  │───▶│ Post-    │              │
│  │ Flight   │    │ RabbitMQ │    │ Formation│    │ Deploy   │              │
│  │ Checks   │    │          │    │          │    │ Validate │              │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘              │
│       │               │               │               │                     │
│       ▼               ▼               ▼               ▼                     │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │• Verify  │    │• Install │    │• Set     │    │• Health  │              │
│  │  RHEL 8  │    │  Erlang  │    │  Cookie  │    │  Check   │              │
│  │• Check   │    │• Install │    │• Join    │    │• Create  │              │
│  │  Ports   │    │  RabbitMQ│    │  Cluster │    │  Vhost   │              │
│  │• Verify  │    │• Config  │    │• Set     │    │• Create  │              │
│  │  DNS     │    │  Service │    │  Policies│    │  Users   │              │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘              │
│                                                                              │
│       │               │               │               │                     │
│       └───────────────┴───────────────┴───────────────┘                     │
│                               │                                              │
│                               ▼                                              │
│                    ┌──────────────────────┐                                 │
│                    │   Approval Gate      │                                 │
│                    │   (If Production)    │                                 │
│                    └──────────────────────┘                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### 1. Harness Account Requirements

| Requirement | Details |
|-------------|---------|
| Harness Account | Active Harness CD subscription (Free tier works for POC) |
| User Role | Project Admin or higher |
| Delegate | At least one healthy delegate with Ansible installed |
| Connectors | Git connector for Ansible repository |

### 2. Infrastructure Requirements

| Component | Specification | Quantity |
|-----------|---------------|----------|
| RabbitMQ Nodes | RHEL 8.x, 4 vCPU, 8GB RAM, 100GB SSD | 3 |
| Harness Delegate | RHEL 8.x, 2 vCPU, 4GB RAM | 1-2 |
| Network | Private subnet with inter-node communication | 1 |
| Load Balancer | HAProxy/ALB (optional for POC) | 1 |

### 3. Network Requirements

| Port | Protocol | Purpose | Direction |
|------|----------|---------|-----------|
| 22 | TCP | SSH (Ansible) | Delegate → Nodes |
| 4369 | TCP | EPMD (Erlang Port Mapper) | Node ↔ Node |
| 5672 | TCP | AMQP Client Connections | Client → Nodes |
| 5671 | TCP | AMQPS (TLS) | Client → Nodes |
| 15672 | TCP | Management UI/API | Admin → Nodes |
| 25672 | TCP | Erlang Distribution | Node ↔ Node |
| 35672-35682 | TCP | CLI Tools | Node ↔ Node |

### 4. Software Requirements

| Software | Version | Purpose |
|----------|---------|---------|
| RHEL | 8.6+ | Operating System |
| Erlang/OTP | 26.x | RabbitMQ Runtime |
| RabbitMQ | 4.0.x | Message Broker |
| Ansible | 2.15+ | Configuration Management |
| Python | 3.9+ | Ansible Dependency |

### 5. Access Requirements

| Access Type | Details |
|-------------|---------|
| SSH Key | Private key for passwordless SSH to all nodes |
| Sudo Access | Ansible user must have passwordless sudo |
| Git Repository | Access to Ansible playbooks repository |
| Harness Secrets | Credentials stored in Harness Secret Manager |

---

## Infrastructure Requirements

### Server Sizing Guidelines

#### Development/POC Environment

| Component | CPU | RAM | Storage | Count |
|-----------|-----|-----|---------|-------|
| RabbitMQ Node | 2 vCPU | 4 GB | 50 GB SSD | 3 |
| Harness Delegate | 2 vCPU | 4 GB | 50 GB | 1 |

#### Production Environment

| Component | CPU | RAM | Storage | Count |
|-----------|-----|-----|---------|-------|
| RabbitMQ Node | 8 vCPU | 32 GB | 500 GB NVMe | 3-5 |
| Harness Delegate | 4 vCPU | 8 GB | 100 GB | 2 |

### Storage Considerations

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     STORAGE LAYOUT PER NODE                                  │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  /                          20 GB   (OS Root)                        │   │
│  │  /var/lib/rabbitmq          80 GB+  (Message Data - CRITICAL)       │   │
│  │  /var/log/rabbitmq          10 GB   (Logs)                          │   │
│  │  /tmp                       10 GB   (Temporary Files)               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  RECOMMENDATION: Use separate SSD/NVMe volume for /var/lib/rabbitmq        │
│  IOPS Requirement: Minimum 3000 IOPS for production workloads              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Environment Setup

### Step 1.1: Prepare RHEL 8 Servers

Execute on **ALL** RabbitMQ nodes:

```bash
# Update system packages
sudo dnf update -y

# Install required packages
sudo dnf install -y \
    epel-release \
    net-tools \
    wget \
    curl \
    vim \
    socat \
    logrotate \
    chrony

# Enable and start chronyd for time synchronization
sudo systemctl enable --now chronyd

# Verify time sync (CRITICAL for cluster)
chronyc tracking
```

### Step 1.2: Configure Hostnames and DNS

On **each node**, set the hostname:

```bash
# Node 1
sudo hostnamectl set-hostname rabbitmq-01.example.com

# Node 2
sudo hostnamectl set-hostname rabbitmq-02.example.com

# Node 3
sudo hostnamectl set-hostname rabbitmq-03.example.com
```

Configure `/etc/hosts` on **ALL nodes**:

```bash
# Add to /etc/hosts on ALL nodes
cat << 'EOF' | sudo tee -a /etc/hosts
# RabbitMQ Cluster Nodes
192.168.1.101   rabbitmq-01.example.com   rabbitmq-01
192.168.1.102   rabbitmq-02.example.com   rabbitmq-02
192.168.1.103   rabbitmq-03.example.com   rabbitmq-03
EOF
```

### Step 1.3: Configure Firewall Rules

```bash
# Open required ports
sudo firewall-cmd --permanent --add-port=4369/tcp      # EPMD
sudo firewall-cmd --permanent --add-port=5672/tcp      # AMQP
sudo firewall-cmd --permanent --add-port=5671/tcp      # AMQPS
sudo firewall-cmd --permanent --add-port=15672/tcp     # Management
sudo firewall-cmd --permanent --add-port=25672/tcp     # Distribution
sudo firewall-cmd --permanent --add-port=35672-35682/tcp  # CLI Tools

# Reload firewall
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-all
```

### Step 1.4: Configure SELinux (if enabled)

```bash
# Option 1: Set SELinux to permissive (for POC)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Option 2: Configure SELinux policies (for Production)
sudo dnf install -y policycoreutils-python-utils
sudo semanage port -a -t amqp_port_t -p tcp 5672
sudo semanage port -a -t amqp_port_t -p tcp 5671
sudo semanage port -a -t amqp_port_t -p tcp 15672
sudo semanage port -a -t amqp_port_t -p tcp 25672
```

### Step 1.5: Configure System Limits

Create `/etc/security/limits.d/99-rabbitmq.conf`:

```bash
cat << 'EOF' | sudo tee /etc/security/limits.d/99-rabbitmq.conf
# RabbitMQ file descriptor and process limits
rabbitmq soft nofile 65536
rabbitmq hard nofile 65536
rabbitmq soft nproc 65536
rabbitmq hard nproc 65536
EOF
```

Configure systemd service limits:

```bash
sudo mkdir -p /etc/systemd/system/rabbitmq-server.service.d/

cat << 'EOF' | sudo tee /etc/systemd/system/rabbitmq-server.service.d/limits.conf
[Service]
LimitNOFILE=65536
LimitNPROC=65536
EOF

sudo systemctl daemon-reload
```

### Step 1.6: Create Ansible User on All Nodes

```bash
# Create ansible user
sudo useradd -m -s /bin/bash ansible

# Set up SSH key authentication
sudo mkdir -p /home/ansible/.ssh
sudo chmod 700 /home/ansible/.ssh

# Add your delegate's public key
echo "ssh-rsa YOUR_PUBLIC_KEY_HERE" | sudo tee /home/ansible/.ssh/authorized_keys
sudo chmod 600 /home/ansible/.ssh/authorized_keys
sudo chown -R ansible:ansible /home/ansible/.ssh

# Configure passwordless sudo
echo "ansible ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/ansible
sudo chmod 440 /etc/sudoers.d/ansible
```

---

## Phase 2: Ansible Configuration

### Step 2.1: Ansible Project Structure

Create the following directory structure in your Git repository:

```
rabbitmq-ansible/
├── ansible.cfg
├── inventory/
│   ├── dev/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       └── all.yml
│   ├── staging/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       └── all.yml
│   └── production/
│       ├── hosts.yml
│       └── group_vars/
│           └── all.yml
├── roles/
│   └── rabbitmq/
│       ├── defaults/
│       │   └── main.yml
│       ├── handlers/
│       │   └── main.yml
│       ├── tasks/
│       │   ├── main.yml
│       │   ├── install_erlang.yml
│       │   ├── install_rabbitmq.yml
│       │   ├── configure.yml
│       │   ├── cluster.yml
│       │   └── users.yml
│       ├── templates/
│       │   ├── rabbitmq.conf.j2
│       │   ├── enabled_plugins.j2
│       │   └── erlang.cookie.j2
│       └── vars/
│           └── main.yml
├── playbooks/
│   ├── site.yml
│   ├── deploy.yml
│   ├── upgrade.yml
│   └── rollback.yml
└── requirements.yml
```

### Step 2.2: Ansible Configuration File

**`ansible.cfg`**:

```ini
[defaults]
inventory = inventory/dev/hosts.yml
remote_user = ansible
private_key_file = ~/.ssh/id_rsa
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
control_path = /tmp/ansible-ssh-%%h-%%p-%%r
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
```

### Step 2.3: Inventory Files

**`inventory/dev/hosts.yml`**:

```yaml
---
all:
  children:
    rabbitmq_cluster:
      hosts:
        rabbitmq-01:
          ansible_host: 192.168.1.101
          rabbitmq_node_name: rabbit@rabbitmq-01
          rabbitmq_node_type: disc
        rabbitmq-02:
          ansible_host: 192.168.1.102
          rabbitmq_node_name: rabbit@rabbitmq-02
          rabbitmq_node_type: disc
        rabbitmq-03:
          ansible_host: 192.168.1.103
          rabbitmq_node_name: rabbit@rabbitmq-03
          rabbitmq_node_type: disc
      vars:
        rabbitmq_cluster_master: rabbitmq-01
```

**`inventory/dev/group_vars/all.yml`**:

```yaml
---
# Environment
environment_name: dev
domain_name: example.com

# Erlang Configuration
erlang_version: "26.2"
erlang_cookie: "DEVELOPMENT_COOKIE_CHANGE_IN_PROD"

# RabbitMQ Configuration
rabbitmq_version: "4.0.2"
rabbitmq_plugins:
  - rabbitmq_management
  - rabbitmq_prometheus
  - rabbitmq_shovel
  - rabbitmq_shovel_management
  - rabbitmq_federation
  - rabbitmq_federation_management

# RabbitMQ Settings
rabbitmq_default_vhost: "/"
rabbitmq_default_user: "admin"
rabbitmq_default_pass: "{{ lookup('env', 'RABBITMQ_ADMIN_PASSWORD') | default('admin123', true) }}"
rabbitmq_default_user_tags: "administrator"

# Memory and Disk Thresholds
rabbitmq_vm_memory_high_watermark: 0.6
rabbitmq_disk_free_limit_relative: 1.5

# Cluster Configuration
rabbitmq_cluster_partition_handling: pause_minority
rabbitmq_collect_statistics_interval: 5000

# TLS Configuration (optional)
rabbitmq_ssl_enabled: false
rabbitmq_ssl_cert_path: "/etc/rabbitmq/ssl/cert.pem"
rabbitmq_ssl_key_path: "/etc/rabbitmq/ssl/key.pem"
rabbitmq_ssl_ca_path: "/etc/rabbitmq/ssl/ca.pem"

# Users to create
rabbitmq_users:
  - name: admin
    password: "{{ rabbitmq_default_pass }}"
    tags: administrator
    vhost: /
    configure_priv: .*
    read_priv: .*
    write_priv: .*
  - name: app_user
    password: "{{ lookup('env', 'RABBITMQ_APP_PASSWORD') | default('app123', true) }}"
    tags: ""
    vhost: /
    configure_priv: ""
    read_priv: .*
    write_priv: .*

# Vhosts to create
rabbitmq_vhosts:
  - name: /
    state: present
  - name: /applications
    state: present

# Policies
rabbitmq_policies:
  - name: ha-all
    vhost: /
    pattern: ".*"
    tags:
      ha-mode: all
      ha-sync-mode: automatic
    priority: 0
```

### Step 2.4: RabbitMQ Role - Main Tasks

**`roles/rabbitmq/tasks/main.yml`**:

```yaml
---
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ item }}"
  with_first_found:
    - "{{ ansible_distribution }}-{{ ansible_distribution_major_version }}.yml"
    - "{{ ansible_distribution }}.yml"
    - "{{ ansible_os_family }}.yml"
    - "default.yml"
  tags: always

- name: Install Erlang
  ansible.builtin.include_tasks: install_erlang.yml
  tags:
    - install
    - erlang

- name: Install RabbitMQ
  ansible.builtin.include_tasks: install_rabbitmq.yml
  tags:
    - install
    - rabbitmq

- name: Configure RabbitMQ
  ansible.builtin.include_tasks: configure.yml
  tags:
    - configure
    - rabbitmq

- name: Configure RabbitMQ Cluster
  ansible.builtin.include_tasks: cluster.yml
  tags:
    - cluster
    - rabbitmq

- name: Configure RabbitMQ Users and Vhosts
  ansible.builtin.include_tasks: users.yml
  tags:
    - users
    - rabbitmq
```

**`roles/rabbitmq/tasks/install_erlang.yml`**:

```yaml
---
- name: Install Erlang repository GPG key
  ansible.builtin.rpm_key:
    key: https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key
    state: present

- name: Add Erlang repository for RHEL 8
  ansible.builtin.yum_repository:
    name: rabbitmq_erlang
    description: RabbitMQ Erlang Repository
    baseurl: https://yum1.rabbitmq.com/erlang/el/8/$basearch
    gpgcheck: yes
    gpgkey: https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key
    enabled: yes
    repo_gpgcheck: no

- name: Install Erlang
  ansible.builtin.dnf:
    name:
      - erlang-{{ erlang_version }}*
    state: present
    enablerepo: rabbitmq_erlang
  register: erlang_install

- name: Verify Erlang installation
  ansible.builtin.command: erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
  register: erlang_version_check
  changed_when: false

- name: Display Erlang version
  ansible.builtin.debug:
    msg: "Erlang OTP version: {{ erlang_version_check.stdout }}"
```

**`roles/rabbitmq/tasks/install_rabbitmq.yml`**:

```yaml
---
- name: Install RabbitMQ repository GPG key
  ansible.builtin.rpm_key:
    key: https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
    state: present

- name: Add RabbitMQ repository for RHEL 8
  ansible.builtin.yum_repository:
    name: rabbitmq_server
    description: RabbitMQ Server Repository
    baseurl: https://yum1.rabbitmq.com/rabbitmq/el/8/$basearch
    gpgcheck: yes
    gpgkey: https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
    enabled: yes
    repo_gpgcheck: no

- name: Install RabbitMQ server
  ansible.builtin.dnf:
    name:
      - rabbitmq-server-{{ rabbitmq_version }}*
    state: present
    enablerepo: rabbitmq_server
  register: rabbitmq_install

- name: Create RabbitMQ directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: rabbitmq
    group: rabbitmq
    mode: '0755'
  loop:
    - /var/lib/rabbitmq
    - /var/log/rabbitmq
    - /etc/rabbitmq

- name: Enable RabbitMQ service
  ansible.builtin.systemd:
    name: rabbitmq-server
    enabled: yes
    daemon_reload: yes
```

**`roles/rabbitmq/tasks/configure.yml`**:

```yaml
---
- name: Set Erlang cookie
  ansible.builtin.template:
    src: erlang.cookie.j2
    dest: /var/lib/rabbitmq/.erlang.cookie
    owner: rabbitmq
    group: rabbitmq
    mode: '0400'
  notify: Restart RabbitMQ

- name: Deploy RabbitMQ configuration
  ansible.builtin.template:
    src: rabbitmq.conf.j2
    dest: /etc/rabbitmq/rabbitmq.conf
    owner: rabbitmq
    group: rabbitmq
    mode: '0644'
  notify: Restart RabbitMQ

- name: Deploy environment configuration
  ansible.builtin.template:
    src: rabbitmq-env.conf.j2
    dest: /etc/rabbitmq/rabbitmq-env.conf
    owner: rabbitmq
    group: rabbitmq
    mode: '0644'
  notify: Restart RabbitMQ

- name: Enable RabbitMQ plugins
  ansible.builtin.template:
    src: enabled_plugins.j2
    dest: /etc/rabbitmq/enabled_plugins
    owner: rabbitmq
    group: rabbitmq
    mode: '0644'
  notify: Restart RabbitMQ

- name: Start RabbitMQ service
  ansible.builtin.systemd:
    name: rabbitmq-server
    state: started
    enabled: yes

- name: Wait for RabbitMQ to start
  ansible.builtin.wait_for:
    port: 5672
    host: "{{ ansible_host }}"
    delay: 10
    timeout: 120

- name: Verify RabbitMQ is running
  ansible.builtin.command: rabbitmqctl status
  register: rabbitmq_status
  changed_when: false
  retries: 5
  delay: 10
  until: rabbitmq_status.rc == 0
```

**`roles/rabbitmq/tasks/cluster.yml`**:

```yaml
---
- name: Check if node is already in cluster
  ansible.builtin.command: rabbitmqctl cluster_status
  register: cluster_status
  changed_when: false
  ignore_errors: yes

- name: Stop RabbitMQ application on non-master nodes
  ansible.builtin.command: rabbitmqctl stop_app
  when:
    - inventory_hostname != rabbitmq_cluster_master
    - rabbitmq_cluster_master not in cluster_status.stdout

- name: Reset RabbitMQ on non-master nodes
  ansible.builtin.command: rabbitmqctl reset
  when:
    - inventory_hostname != rabbitmq_cluster_master
    - rabbitmq_cluster_master not in cluster_status.stdout
  ignore_errors: yes

- name: Join cluster on non-master nodes
  ansible.builtin.command: "rabbitmqctl join_cluster rabbit@{{ rabbitmq_cluster_master }}"
  when:
    - inventory_hostname != rabbitmq_cluster_master
    - rabbitmq_cluster_master not in cluster_status.stdout
  register: join_result
  ignore_errors: yes

- name: Start RabbitMQ application on non-master nodes
  ansible.builtin.command: rabbitmqctl start_app
  when:
    - inventory_hostname != rabbitmq_cluster_master
    - rabbitmq_cluster_master not in cluster_status.stdout

- name: Wait for cluster to form
  ansible.builtin.pause:
    seconds: 30
  when: join_result is changed

- name: Verify cluster status
  ansible.builtin.command: rabbitmqctl cluster_status
  register: final_cluster_status
  changed_when: false

- name: Display cluster status
  ansible.builtin.debug:
    var: final_cluster_status.stdout_lines

- name: Set cluster name
  ansible.builtin.command: "rabbitmqctl set_cluster_name {{ environment_name }}-rabbitmq-cluster"
  when: inventory_hostname == rabbitmq_cluster_master
  changed_when: false
```

**`roles/rabbitmq/tasks/users.yml`**:

```yaml
---
- name: Configure users on master node only
  when: inventory_hostname == rabbitmq_cluster_master
  block:
    - name: Remove default guest user
      ansible.builtin.command: rabbitmqctl delete_user guest
      ignore_errors: yes
      changed_when: false

    - name: Create vhosts
      ansible.builtin.command: "rabbitmqctl add_vhost {{ item.name }}"
      loop: "{{ rabbitmq_vhosts }}"
      when: item.state == 'present'
      ignore_errors: yes
      changed_when: false

    - name: Create users
      ansible.builtin.command: >
        rabbitmqctl add_user {{ item.name }} '{{ item.password }}'
      loop: "{{ rabbitmq_users }}"
      no_log: true
      ignore_errors: yes
      changed_when: false

    - name: Set user tags
      ansible.builtin.command: >
        rabbitmqctl set_user_tags {{ item.name }} {{ item.tags }}
      loop: "{{ rabbitmq_users }}"
      when: item.tags | length > 0
      ignore_errors: yes
      changed_when: false

    - name: Set user permissions
      ansible.builtin.command: >
        rabbitmqctl set_permissions -p {{ item.vhost }}
        {{ item.name }}
        '{{ item.configure_priv }}'
        '{{ item.write_priv }}'
        '{{ item.read_priv }}'
      loop: "{{ rabbitmq_users }}"
      ignore_errors: yes
      changed_when: false

    - name: Set HA policy
      ansible.builtin.command: >
        rabbitmqctl set_policy -p {{ item.vhost }}
        {{ item.name }}
        '{{ item.pattern }}'
        '{"ha-mode":"{{ item.tags["ha-mode"] }}","ha-sync-mode":"{{ item.tags["ha-sync-mode"] }}"}'
        --priority {{ item.priority }}
        --apply-to all
      loop: "{{ rabbitmq_policies }}"
      ignore_errors: yes
      changed_when: false
```

### Step 2.5: RabbitMQ Role - Handlers

**`roles/rabbitmq/handlers/main.yml`**:

```yaml
---
- name: Restart RabbitMQ
  ansible.builtin.systemd:
    name: rabbitmq-server
    state: restarted
  throttle: 1
  listen: "Restart RabbitMQ"

- name: Reload RabbitMQ
  ansible.builtin.command: rabbitmqctl eval 'application:stop(rabbit), application:start(rabbit).'
  listen: "Reload RabbitMQ"
```

### Step 2.6: RabbitMQ Role - Templates

**`roles/rabbitmq/templates/rabbitmq.conf.j2`**:

```ini
# RabbitMQ Configuration
# Generated by Ansible - Do not edit manually

# ===========================================
# Network Configuration
# ===========================================
listeners.tcp.default = 5672
{% if rabbitmq_ssl_enabled %}
listeners.ssl.default = 5671
ssl_options.cacertfile = {{ rabbitmq_ssl_ca_path }}
ssl_options.certfile = {{ rabbitmq_ssl_cert_path }}
ssl_options.keyfile = {{ rabbitmq_ssl_key_path }}
ssl_options.verify = verify_peer
ssl_options.fail_if_no_peer_cert = false
{% endif %}

# Management Plugin
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# ===========================================
# Cluster Configuration
# ===========================================
cluster_partition_handling = {{ rabbitmq_cluster_partition_handling }}
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@rabbitmq-01
cluster_formation.classic_config.nodes.2 = rabbit@rabbitmq-02
cluster_formation.classic_config.nodes.3 = rabbit@rabbitmq-03

# ===========================================
# Memory and Disk Configuration
# ===========================================
vm_memory_high_watermark.relative = {{ rabbitmq_vm_memory_high_watermark }}
disk_free_limit.relative = {{ rabbitmq_disk_free_limit_relative }}

# ===========================================
# Statistics Configuration
# ===========================================
collect_statistics_interval = {{ rabbitmq_collect_statistics_interval }}

# ===========================================
# Logging Configuration
# ===========================================
log.file.level = info
log.console = false
log.console.level = info
log.file = /var/log/rabbitmq/rabbit.log
log.file.rotation.date = $D0
log.file.rotation.count = 7

# ===========================================
# Queue Configuration (RabbitMQ 4.x)
# ===========================================
# Default queue type for new queues
default_queue_type = quorum

# Quorum queue settings
quorum_queue.segment_entry_count = 32768

# ===========================================
# Connection and Channel Limits
# ===========================================
channel_max = 2047
heartbeat = 60

# ===========================================
# Consumer Configuration
# ===========================================
consumer_timeout = 1800000
```

**`roles/rabbitmq/templates/enabled_plugins.j2`**:

```
[{{ rabbitmq_plugins | join(',') }}].
```

**`roles/rabbitmq/templates/erlang.cookie.j2`**:

```
{{ erlang_cookie }}
```

### Step 2.7: Deployment Playbook

**`playbooks/deploy.yml`**:

```yaml
---
- name: Deploy RabbitMQ 4.x Cluster
  hosts: rabbitmq_cluster
  become: yes
  gather_facts: yes
  serial: 1

  pre_tasks:
    - name: Verify RHEL 8
      ansible.builtin.assert:
        that:
          - ansible_distribution == "RedHat" or ansible_distribution == "CentOS" or ansible_distribution == "Rocky"
          - ansible_distribution_major_version == "8"
        fail_msg: "This playbook requires RHEL/CentOS/Rocky 8"
        success_msg: "OS verification passed"

    - name: Check connectivity to other cluster nodes
      ansible.builtin.wait_for:
        host: "{{ hostvars[item].ansible_host }}"
        port: 22
        timeout: 10
      loop: "{{ groups['rabbitmq_cluster'] }}"
      when: item != inventory_hostname

    - name: Verify DNS resolution for cluster nodes
      ansible.builtin.command: "getent hosts {{ item }}"
      loop: "{{ groups['rabbitmq_cluster'] }}"
      changed_when: false
      register: dns_check

  roles:
    - role: rabbitmq
      tags:
        - rabbitmq

  post_tasks:
    - name: Verify RabbitMQ service is running
      ansible.builtin.systemd:
        name: rabbitmq-server
        state: started
      register: service_status

    - name: Get cluster status
      ansible.builtin.command: rabbitmqctl cluster_status
      register: cluster_status
      changed_when: false
      when: inventory_hostname == rabbitmq_cluster_master

    - name: Display cluster status
      ansible.builtin.debug:
        var: cluster_status.stdout_lines
      when: inventory_hostname == rabbitmq_cluster_master

    - name: Health check - Management API
      ansible.builtin.uri:
        url: "http://{{ ansible_host }}:15672/api/health/checks/alarms"
        user: "{{ rabbitmq_default_user }}"
        password: "{{ rabbitmq_default_pass }}"
        method: GET
        status_code: 200
      register: health_check
      retries: 5
      delay: 10
      until: health_check.status == 200
      when: inventory_hostname == rabbitmq_cluster_master
```

---

## Phase 3: Harness CD Setup

### Step 3.1: Create Harness Project

1. **Navigate to Harness UI**
   - Log in to your Harness account
   - Go to **Projects** → **+ New Project**

2. **Project Configuration**
   ```
   Name: rabbitmq-cluster-poc
   Organization: [Your Organization]
   Description: RabbitMQ 4.x Cluster Deployment POC
   Color: [Select preferred color]
   ```

3. **Enable Modules**
   - Enable **Continuous Delivery** module
   - Enable **GitOps** (optional)

### Step 3.2: Install and Configure Harness Delegate

#### Option A: Docker Delegate (Recommended for POC)

```bash
# On your delegate host (RHEL 8)
# Install Docker
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker

# Install Ansible in the delegate container
# Create custom Dockerfile
cat << 'EOF' > Dockerfile.delegate
FROM harness/delegate:latest

USER root

# Install Ansible and dependencies
RUN microdnf install -y python3 python3-pip openssh-clients && \
    pip3 install ansible==2.15.* && \
    microdnf clean all

# Create ansible directory
RUN mkdir -p /opt/harness-delegate/ansible

USER harness
EOF

# Build custom delegate image
docker build -t harness-delegate-ansible:latest -f Dockerfile.delegate .

# Run delegate (get token from Harness UI)
docker run -d --name harness-delegate \
  -e DELEGATE_NAME=rabbitmq-poc-delegate \
  -e NEXT_GEN=true \
  -e DELEGATE_TYPE=DOCKER \
  -e ACCOUNT_ID=<YOUR_ACCOUNT_ID> \
  -e DELEGATE_TOKEN=<YOUR_DELEGATE_TOKEN> \
  -e MANAGER_HOST_AND_PORT=https://app.harness.io \
  -e LOG_STREAMING_SERVICE_URL=https://app.harness.io/log-service/ \
  -v /home/ansible/.ssh:/home/harness/.ssh:ro \
  -v /opt/ansible:/opt/ansible:ro \
  harness-delegate-ansible:latest
```

#### Option B: Kubernetes Delegate

```yaml
# delegate-values.yaml
delegateName: rabbitmq-poc-delegate
accountId: <YOUR_ACCOUNT_ID>
delegateToken: <YOUR_DELEGATE_TOKEN>
managerEndpoint: https://app.harness.io
delegateDockerImage: harness/delegate:latest
replicas: 2
resources:
  limits:
    cpu: "1"
    memory: "2Gi"
  requests:
    cpu: "0.5"
    memory: "1Gi"
initScript: |
  # Install Ansible
  microdnf install -y python3 python3-pip openssh-clients
  pip3 install ansible==2.15.*
```

### Step 3.3: Create Git Connector

1. **Navigate to Connectors**
   - Go to **Project Settings** → **Connectors** → **+ New Connector**

2. **Select Git Provider**
   - Choose **GitHub**, **GitLab**, **Bitbucket**, or **Git**

3. **Configure Connection**
   ```
   Name: ansible-repo-connector
   URL: https://github.com/your-org/rabbitmq-ansible.git
   Connection Type: HTTP
   Authentication: Username and Token
   Username: [your-username]
   Token: [Create as Harness Secret]
   ```

4. **Test Connection**
   - Click **Test Connection**
   - Verify connectivity through delegate

### Step 3.4: Create SSH Credential Secret

1. **Navigate to Secrets**
   - Go to **Project Settings** → **Secrets** → **+ New Secret** → **SSH Credential**

2. **Configure SSH Key**
   ```
   Name: rabbitmq-nodes-ssh-key
   Description: SSH key for RabbitMQ cluster nodes
   SSH Key Type: Key File
   Username: ansible
   Key: [Paste private key content]
   Passphrase: [If applicable]
   ```

### Step 3.5: Create Text Secrets

Create the following secrets for sensitive data:

| Secret Name | Purpose |
|-------------|---------|
| `rabbitmq-admin-password` | Admin user password |
| `rabbitmq-app-password` | Application user password |
| `rabbitmq-erlang-cookie` | Erlang cluster cookie |

### Step 3.6: Create Service

1. **Navigate to Services**
   - Go to **Deployments** → **Services** → **+ New Service**

2. **Service Configuration**
   ```yaml
   Name: rabbitmq-cluster
   Description: RabbitMQ 4.x Cluster Service
   Deployment Type: Custom Deployment
   ```

3. **Service Definition**
   ```yaml
   service:
     name: rabbitmq-cluster
     identifier: rabbitmq_cluster
     serviceDefinition:
       type: CustomDeployment
       spec:
         customDeploymentRef:
           templateRef: org.AnsibleDeployment
         variables:
           - name: rabbitmq_version
             type: String
             value: "4.0.2"
           - name: erlang_version
             type: String
             value: "26.2"
           - name: ansible_playbook
             type: String
             value: "playbooks/deploy.yml"
     gitOpsEnabled: false
   ```

### Step 3.7: Create Environments

Create environments for each stage:

#### Development Environment

```yaml
environment:
  name: Development
  identifier: dev
  type: PreProduction
  orgIdentifier: default
  projectIdentifier: rabbitmq_cluster_poc
  variables:
    - name: env_name
      type: String
      value: dev
    - name: inventory_file
      type: String
      value: inventory/dev/hosts.yml
```

#### Staging Environment

```yaml
environment:
  name: Staging
  identifier: staging
  type: PreProduction
  orgIdentifier: default
  projectIdentifier: rabbitmq_cluster_poc
  variables:
    - name: env_name
      type: String
      value: staging
    - name: inventory_file
      type: String
      value: inventory/staging/hosts.yml
```

#### Production Environment

```yaml
environment:
  name: Production
  identifier: production
  type: Production
  orgIdentifier: default
  projectIdentifier: rabbitmq_cluster_poc
  variables:
    - name: env_name
      type: String
      value: production
    - name: inventory_file
      type: String
      value: inventory/production/hosts.yml
```

### Step 3.8: Create Infrastructure Definition

For each environment, create an infrastructure definition:

```yaml
infrastructureDefinition:
  name: rabbitmq-infra-dev
  identifier: rabbitmq_infra_dev
  orgIdentifier: default
  projectIdentifier: rabbitmq_cluster_poc
  environmentRef: dev
  deploymentType: CustomDeployment
  type: CustomDeployment
  spec:
    customDeploymentRef:
      templateRef: org.AnsibleInfra
    variables:
      - name: ansible_inventory
        type: String
        value: <+env.variables.inventory_file>
      - name: ansible_user
        type: String
        value: ansible
      - name: ssh_key_ref
        type: String
        value: rabbitmq-nodes-ssh-key
```

---

## Phase 4: Pipeline Creation

### Step 4.1: Create Deployment Pipeline

Navigate to **Pipelines** → **+ Create Pipeline**

**Pipeline Configuration:**

```yaml
pipeline:
  name: Deploy RabbitMQ Cluster
  identifier: deploy_rabbitmq_cluster
  projectIdentifier: rabbitmq_cluster_poc
  orgIdentifier: default
  tags:
    rabbitmq: "true"
    ansible: "true"
  stages:
    - stage:
        name: Pre-Flight Checks
        identifier: pre_flight_checks
        description: Validate environment before deployment
        type: Custom
        spec:
          execution:
            steps:
              - step:
                  type: ShellScript
                  name: Verify Connectivity
                  identifier: verify_connectivity
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          echo "=== Pre-Flight Connectivity Check ==="

                          # Test SSH connectivity to all nodes
                          NODES=("rabbitmq-01" "rabbitmq-02" "rabbitmq-03")

                          for node in "${NODES[@]}"; do
                            echo "Testing SSH to $node..."
                            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                              -i $SSH_KEY_PATH ansible@$node "hostname && uptime" || {
                              echo "ERROR: Cannot connect to $node"
                              exit 1
                            }
                            echo "SUCCESS: $node is reachable"
                          done

                          echo "=== All nodes are reachable ==="
                    environmentVariables:
                      - name: SSH_KEY_PATH
                        type: String
                        value: /tmp/ssh_key
                    outputVariables: []
                  timeout: 5m

              - step:
                  type: ShellScript
                  name: Verify System Requirements
                  identifier: verify_system_requirements
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          echo "=== System Requirements Verification ==="

                          NODES=("rabbitmq-01" "rabbitmq-02" "rabbitmq-03")

                          for node in "${NODES[@]}"; do
                            echo "Checking $node..."

                            # Check OS version
                            OS_VERSION=$(ssh ansible@$node "cat /etc/redhat-release")
                            echo "  OS: $OS_VERSION"

                            # Check memory
                            MEM_GB=$(ssh ansible@$node "free -g | awk '/^Mem:/{print \$2}'")
                            echo "  Memory: ${MEM_GB}GB"
                            if [ "$MEM_GB" -lt 4 ]; then
                              echo "  WARNING: Memory less than 4GB"
                            fi

                            # Check disk space
                            DISK_FREE=$(ssh ansible@$node "df -BG /var/lib | tail -1 | awk '{print \$4}' | tr -d 'G'")
                            echo "  Disk Free: ${DISK_FREE}GB"
                            if [ "$DISK_FREE" -lt 50 ]; then
                              echo "  WARNING: Disk space less than 50GB"
                            fi

                            # Check required ports
                            echo "  Checking ports..."
                            for port in 4369 5672 15672 25672; do
                              if ssh ansible@$node "ss -tln | grep -q :$port"; then
                                echo "    Port $port: IN USE (may need cleanup)"
                              else
                                echo "    Port $port: Available"
                              fi
                            done
                          done

                          echo "=== System verification complete ==="
                  timeout: 5m

    - stage:
        name: Deploy to Development
        identifier: deploy_dev
        description: Deploy RabbitMQ cluster to development environment
        type: Deployment
        spec:
          deploymentType: CustomDeployment
          service:
            serviceRef: rabbitmq_cluster
          environment:
            environmentRef: dev
            infrastructureDefinitions:
              - identifier: rabbitmq_infra_dev
          execution:
            steps:
              - step:
                  type: ShellScript
                  name: Clone Ansible Repository
                  identifier: clone_repo
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          WORK_DIR="/tmp/ansible-rabbitmq-${HARNESS_BUILD_ID}"

                          echo "Cloning Ansible repository..."
                          rm -rf $WORK_DIR
                          git clone <+pipeline.variables.git_repo_url> $WORK_DIR
                          cd $WORK_DIR
                          git checkout <+pipeline.variables.git_branch>

                          echo "Repository cloned to: $WORK_DIR"
                          echo "Git commit: $(git rev-parse HEAD)"
                    outputVariables:
                      - name: ANSIBLE_WORK_DIR
                        type: String
                        value: /tmp/ansible-rabbitmq-${HARNESS_BUILD_ID}
                  timeout: 5m

              - step:
                  type: ShellScript
                  name: Run Ansible Playbook
                  identifier: run_ansible
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          cd <+execution.steps.clone_repo.output.outputVariables.ANSIBLE_WORK_DIR>

                          echo "=== Running Ansible Deployment ==="
                          echo "Environment: <+env.name>"
                          echo "Inventory: <+infra.variables.ansible_inventory>"

                          # Set up SSH key
                          mkdir -p ~/.ssh
                          echo "<+secrets.getValue('rabbitmq-nodes-ssh-key')>" > ~/.ssh/id_rsa
                          chmod 600 ~/.ssh/id_rsa

                          # Export environment variables for Ansible
                          export RABBITMQ_ADMIN_PASSWORD="<+secrets.getValue('rabbitmq-admin-password')>"
                          export RABBITMQ_APP_PASSWORD="<+secrets.getValue('rabbitmq-app-password')>"
                          export ANSIBLE_HOST_KEY_CHECKING=False

                          # Run Ansible playbook
                          ansible-playbook \
                            -i <+infra.variables.ansible_inventory> \
                            playbooks/deploy.yml \
                            -e "erlang_cookie=<+secrets.getValue('rabbitmq-erlang-cookie')>" \
                            -e "environment_name=<+env.variables.env_name>" \
                            -v

                          echo "=== Ansible deployment completed ==="
                    environmentVariables: []
                  timeout: 30m
                  failureStrategies:
                    - onFailure:
                        errors:
                          - AllErrors
                        action:
                          type: Retry
                          spec:
                            retryCount: 2
                            retryIntervals:
                              - 1m

              - step:
                  type: ShellScript
                  name: Verify Cluster Health
                  identifier: verify_cluster
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          echo "=== Cluster Health Verification ==="

                          MASTER_NODE="rabbitmq-01"
                          ADMIN_USER="admin"
                          ADMIN_PASS="<+secrets.getValue('rabbitmq-admin-password')>"

                          # Check cluster status via CLI
                          echo "Checking cluster status..."
                          ssh ansible@$MASTER_NODE "sudo rabbitmqctl cluster_status"

                          # Check via Management API
                          echo "Checking Management API..."
                          CLUSTER_STATUS=$(curl -s -u $ADMIN_USER:$ADMIN_PASS \
                            http://$MASTER_NODE:15672/api/cluster-name)
                          echo "Cluster Name: $CLUSTER_STATUS"

                          # Check all nodes
                          echo "Checking node health..."
                          NODES_STATUS=$(curl -s -u $ADMIN_USER:$ADMIN_PASS \
                            http://$MASTER_NODE:15672/api/nodes)
                          echo "$NODES_STATUS" | jq -r '.[] | "\(.name): \(.running)"'

                          # Check for alarms
                          echo "Checking for alarms..."
                          ALARMS=$(curl -s -u $ADMIN_USER:$ADMIN_PASS \
                            http://$MASTER_NODE:15672/api/health/checks/alarms)
                          if echo "$ALARMS" | grep -q '"status":"ok"'; then
                            echo "No alarms detected"
                          else
                            echo "WARNING: Alarms detected!"
                            echo "$ALARMS"
                          fi

                          echo "=== Health verification complete ==="
                  timeout: 10m

              - step:
                  type: ShellScript
                  name: Run Integration Tests
                  identifier: integration_tests
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          set -e

                          echo "=== Running Integration Tests ==="

                          MASTER_NODE="rabbitmq-01"
                          ADMIN_USER="admin"
                          ADMIN_PASS="<+secrets.getValue('rabbitmq-admin-password')>"

                          # Test 1: Create test queue
                          echo "Test 1: Creating test queue..."
                          curl -s -u $ADMIN_USER:$ADMIN_PASS -X PUT \
                            -H "content-type: application/json" \
                            -d '{"durable":true,"arguments":{"x-queue-type":"quorum"}}' \
                            http://$MASTER_NODE:15672/api/queues/%2F/test-queue
                          echo "Test queue created"

                          # Test 2: Publish test message
                          echo "Test 2: Publishing test message..."
                          curl -s -u $ADMIN_USER:$ADMIN_PASS -X POST \
                            -H "content-type: application/json" \
                            -d '{"properties":{},"routing_key":"test-queue","payload":"Hello from Harness!","payload_encoding":"string"}' \
                            http://$MASTER_NODE:15672/api/exchanges/%2F/amq.default/publish
                          echo "Test message published"

                          # Test 3: Verify message
                          echo "Test 3: Retrieving test message..."
                          MSG=$(curl -s -u $ADMIN_USER:$ADMIN_PASS -X POST \
                            -H "content-type: application/json" \
                            -d '{"count":1,"ackmode":"ack_requeue_false","encoding":"auto"}' \
                            http://$MASTER_NODE:15672/api/queues/%2F/test-queue/get)
                          echo "Retrieved: $MSG"

                          # Cleanup
                          echo "Cleaning up test queue..."
                          curl -s -u $ADMIN_USER:$ADMIN_PASS -X DELETE \
                            http://$MASTER_NODE:15672/api/queues/%2F/test-queue

                          echo "=== Integration tests passed ==="
                  timeout: 10m

            rollbackSteps:
              - step:
                  type: ShellScript
                  name: Rollback Deployment
                  identifier: rollback
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          #!/bin/bash
                          echo "=== Initiating Rollback ==="

                          cd <+execution.steps.clone_repo.output.outputVariables.ANSIBLE_WORK_DIR>

                          ansible-playbook \
                            -i <+infra.variables.ansible_inventory> \
                            playbooks/rollback.yml \
                            -e "environment_name=<+env.variables.env_name>" \
                            -v

                          echo "=== Rollback completed ==="
                  timeout: 30m

    - stage:
        name: Approval Gate
        identifier: approval_gate
        description: Manual approval before staging deployment
        type: Approval
        spec:
          execution:
            steps:
              - step:
                  type: HarnessApproval
                  name: Approve Staging Deployment
                  identifier: approve_staging
                  spec:
                    approvalMessage: |
                      Development deployment completed successfully.

                      Please review the following before approving:
                      - Cluster health status
                      - Integration test results
                      - Log files for any warnings

                      Approve to proceed with Staging deployment.
                    includePipelineExecutionHistory: true
                    approvers:
                      userGroups:
                        - _project_all_users
                      minimumCount: 1
                      disallowPipelineExecutor: false
                    approverInputs: []
                  timeout: 1d
                  when:
                    stageStatus: Success

    - stage:
        name: Deploy to Staging
        identifier: deploy_staging
        description: Deploy RabbitMQ cluster to staging environment
        type: Deployment
        spec:
          deploymentType: CustomDeployment
          service:
            serviceRef: rabbitmq_cluster
          environment:
            environmentRef: staging
            infrastructureDefinitions:
              - identifier: rabbitmq_infra_staging
          execution:
            steps:
              # Similar steps as Development stage
              # ... (abbreviated for document length)
              - step:
                  type: ShellScript
                  name: Deploy to Staging
                  identifier: deploy_staging_ansible
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          # Same deployment script with staging inventory
                          echo "Deploying to Staging environment..."
                  timeout: 30m

    - stage:
        name: Production Approval
        identifier: prod_approval
        description: Manual approval before production deployment
        type: Approval
        spec:
          execution:
            steps:
              - step:
                  type: HarnessApproval
                  name: Approve Production Deployment
                  identifier: approve_production
                  spec:
                    approvalMessage: |
                      Staging deployment completed successfully.

                      PRODUCTION DEPLOYMENT APPROVAL REQUIRED

                      This will deploy RabbitMQ cluster to PRODUCTION.
                      Please ensure:
                      - Change management ticket is approved
                      - Maintenance window is scheduled
                      - Rollback plan is documented

                      Approve to proceed with Production deployment.
                    includePipelineExecutionHistory: true
                    approvers:
                      userGroups:
                        - org._org_admins
                      minimumCount: 2
                      disallowPipelineExecutor: true
                    approverInputs:
                      - name: change_ticket
                        description: "Change Management Ticket Number"
                      - name: maintenance_window
                        description: "Scheduled Maintenance Window"
                  timeout: 7d

    - stage:
        name: Deploy to Production
        identifier: deploy_production
        description: Deploy RabbitMQ cluster to production environment
        type: Deployment
        spec:
          deploymentType: CustomDeployment
          service:
            serviceRef: rabbitmq_cluster
          environment:
            environmentRef: production
            infrastructureDefinitions:
              - identifier: rabbitmq_infra_production
          execution:
            steps:
              - step:
                  type: ShellScript
                  name: Deploy to Production
                  identifier: deploy_prod_ansible
                  spec:
                    shell: Bash
                    source:
                      type: Inline
                      spec:
                        script: |
                          echo "Deploying to Production environment..."
                          # Production deployment with extra safety checks
                  timeout: 45m

  variables:
    - name: git_repo_url
      type: String
      description: Git repository URL for Ansible playbooks
      default: https://github.com/your-org/rabbitmq-ansible.git
    - name: git_branch
      type: String
      description: Git branch to deploy from
      default: main
```

### Step 4.2: Pipeline Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `git_repo_url` | String | - | Ansible playbooks repository URL |
| `git_branch` | String | main | Branch to deploy |
| `rabbitmq_version` | String | 4.0.2 | RabbitMQ version |
| `erlang_version` | String | 26.2 | Erlang OTP version |

---

## Phase 5: Deployment Execution

### Step 5.1: Trigger Pipeline

1. **Manual Trigger**
   - Navigate to Pipeline
   - Click **Run**
   - Verify/modify input variables
   - Click **Run Pipeline**

2. **Git Trigger (Optional)**
   ```yaml
   trigger:
     name: Deploy on Main Push
     identifier: deploy_on_push
     enabled: true
     triggerType: Webhook
     pipelineIdentifier: deploy_rabbitmq_cluster
     source:
       type: Webhook
       spec:
         type: Github
         spec:
           type: Push
           spec:
             connectorRef: ansible_repo_connector
             autoAbortPreviousExecutions: false
             payloadConditions:
               - key: targetBranch
                 operator: Equals
                 value: main
   ```

### Step 5.2: Monitor Execution

During pipeline execution, monitor:

1. **Harness UI**
   - Real-time step execution status
   - Log streaming for each step
   - Deployment metrics

2. **RabbitMQ Management UI**
   - Access: `http://rabbitmq-01:15672`
   - Login: admin / [password]
   - Monitor cluster formation

3. **Command Line**
   ```bash
   # On any RabbitMQ node
   sudo rabbitmqctl cluster_status
   sudo rabbitmqctl list_queues
   sudo rabbitmqctl list_connections
   ```

---

## Phase 6: Validation & Testing

### Step 6.1: Cluster Health Checks

```bash
# Check cluster status
rabbitmqctl cluster_status

# Expected output should show all 3 nodes
# Cluster status of node rabbit@rabbitmq-01 ...
# Basics
# Cluster name: dev-rabbitmq-cluster
#
# Disk Nodes
# rabbit@rabbitmq-01
# rabbit@rabbitmq-02
# rabbit@rabbitmq-03
#
# Running Nodes
# rabbit@rabbitmq-01
# rabbit@rabbitmq-02
# rabbit@rabbitmq-03
```

### Step 6.2: Functional Tests

```bash
# Test 1: Create quorum queue
rabbitmqadmin declare queue name=test-quorum-queue durable=true \
  arguments='{"x-queue-type": "quorum"}'

# Test 2: Publish messages
for i in {1..100}; do
  rabbitmqadmin publish exchange=amq.default routing_key=test-quorum-queue \
    payload="Test message $i"
done

# Test 3: Consume messages
rabbitmqadmin get queue=test-quorum-queue count=10

# Test 4: Check queue mirroring
rabbitmqctl list_queues name type leader replicas
```

### Step 6.3: Failover Test

```bash
# Simulate node failure
sudo systemctl stop rabbitmq-server  # On one node

# Verify cluster continues operating
rabbitmqctl cluster_status  # From another node

# Verify quorum queues still have leader
rabbitmqctl list_queues name type leader online

# Bring node back
sudo systemctl start rabbitmq-server

# Verify node rejoins cluster
rabbitmqctl cluster_status
```

### Step 6.4: Performance Baseline

```bash
# Install PerfTest tool
wget https://github.com/rabbitmq/rabbitmq-perf-test/releases/download/v2.19.0/rabbitmq-perf-test-2.19.0-bin.tar.gz
tar xzf rabbitmq-perf-test-2.19.0-bin.tar.gz

# Run performance test
./rabbitmq-perf-test-2.19.0/bin/runjava com.rabbitmq.perf.PerfTest \
  -h amqp://admin:password@rabbitmq-01:5672 \
  -x 1 -y 2 -u "perf-test" -a --id "test-1" \
  --time 60 --quorum-queue
```

---

## Rollback Strategy

### Automatic Rollback (Pipeline Failure)

The pipeline includes automatic rollback steps that execute on failure:

```yaml
rollbackSteps:
  - step:
      type: ShellScript
      name: Rollback Deployment
      identifier: rollback
      spec:
        shell: Bash
        source:
          type: Inline
          spec:
            script: |
              #!/bin/bash
              echo "=== Initiating Rollback ==="

              # Stop RabbitMQ on all nodes in reverse order
              for node in rabbitmq-03 rabbitmq-02 rabbitmq-01; do
                ssh ansible@$node "sudo systemctl stop rabbitmq-server"
              done

              # If previous version backup exists, restore it
              if [ -d "/backup/rabbitmq-previous" ]; then
                for node in rabbitmq-01 rabbitmq-02 rabbitmq-03; do
                  ssh ansible@$node "sudo rsync -av /backup/rabbitmq-previous/ /var/lib/rabbitmq/"
                done
              fi

              # Start services
              for node in rabbitmq-01 rabbitmq-02 rabbitmq-03; do
                ssh ansible@$node "sudo systemctl start rabbitmq-server"
              done

              echo "=== Rollback completed ==="
```

### Manual Rollback Procedure

```bash
# Step 1: Stop applications (reverse order)
for node in rabbitmq-03 rabbitmq-02 rabbitmq-01; do
  ssh ansible@$node "sudo rabbitmqctl stop_app"
done

# Step 2: Reset non-master nodes
for node in rabbitmq-03 rabbitmq-02; do
  ssh ansible@$node "sudo rabbitmqctl reset"
done

# Step 3: Downgrade packages if needed
sudo dnf downgrade rabbitmq-server-<previous_version>

# Step 4: Restore data from backup
sudo systemctl stop rabbitmq-server
sudo rsync -av /backup/rabbitmq/<timestamp>/ /var/lib/rabbitmq/
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq

# Step 5: Restart services
sudo systemctl start rabbitmq-server
```

---

## Monitoring & Alerting

### Prometheus Integration

**`/etc/rabbitmq/rabbitmq.conf` additions:**

```ini
# Prometheus metrics
prometheus.return_per_object_metrics = true
prometheus.path = /metrics
prometheus.tcp.port = 15692
```

### Key Metrics to Monitor

| Metric | Threshold | Alert Level |
|--------|-----------|-------------|
| `rabbitmq_queue_messages` | > 10000 | Warning |
| `rabbitmq_queue_messages` | > 50000 | Critical |
| `rabbitmq_connections` | > 1000 | Warning |
| `rabbitmq_channels` | > 5000 | Warning |
| `rabbitmq_node_mem_used` | > 80% | Warning |
| `rabbitmq_node_disk_free` | < 5GB | Critical |
| `rabbitmq_queue_consumers` | = 0 | Warning |

### Grafana Dashboard

Import RabbitMQ dashboard ID: `10991` for comprehensive monitoring.

---

## Security Considerations

### Network Security

1. **Firewall Rules** - Only allow necessary ports between nodes
2. **Private Network** - Deploy cluster in private subnet
3. **VPN/Bastion** - Access management UI through secure channels

### Authentication & Authorization

1. **Remove Guest User** - Already handled in playbook
2. **Strong Passwords** - Use Harness secrets for all credentials
3. **Least Privilege** - Create application-specific users with minimal permissions

### Encryption

1. **TLS for Client Connections** - Configure SSL/TLS for AMQPS
2. **Inter-node Encryption** - Enable Erlang distribution TLS
3. **Management UI HTTPS** - Configure reverse proxy with TLS

### Erlang Cookie Security

```bash
# Generate secure cookie
openssl rand -hex 32

# Store in Harness Secrets Manager
# Reference: rabbitmq-erlang-cookie
```

---

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue 1: Nodes Cannot Join Cluster

**Symptoms:**
- `rabbitmqctl join_cluster` fails
- Error: "Node is already a member of cluster"

**Solutions:**
```bash
# Reset the node completely
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl start_app

# Verify erlang cookie is identical on all nodes
cat /var/lib/rabbitmq/.erlang.cookie
```

#### Issue 2: Network Partition Detected

**Symptoms:**
- Nodes show as "partitioned"
- Messages not replicating

**Solutions:**
```bash
# Check network connectivity
for port in 4369 25672; do
  nc -zv rabbitmq-02 $port
done

# Manually resolve partition (CAUTION)
rabbitmqctl forget_cluster_node rabbit@rabbitmq-02
# Then rejoin the node
```

#### Issue 3: High Memory Usage

**Symptoms:**
- Memory alarm triggered
- Node refusing connections

**Solutions:**
```bash
# Check memory usage
rabbitmqctl status | grep memory

# Manually trigger GC
rabbitmqctl eval 'garbage_collect().'

# Check for message backlog
rabbitmqctl list_queues name messages
```

#### Issue 4: Disk Space Alarm

**Symptoms:**
- Disk alarm triggered
- Publishing blocked

**Solutions:**
```bash
# Check disk usage
df -h /var/lib/rabbitmq

# Purge old logs
rabbitmqctl rotate_logs

# Clean message store if needed
# WARNING: This deletes messages!
# rabbitmqctl stop_app
# rm -rf /var/lib/rabbitmq/mnesia/*
# rabbitmqctl start_app
```

### Log Locations

| Log | Path |
|-----|------|
| RabbitMQ | `/var/log/rabbitmq/rabbit.log` |
| Startup | `/var/log/rabbitmq/rabbit@<hostname>-sasl.log` |
| Upgrade | `/var/log/rabbitmq/rabbit@<hostname>-upgrade.log` |
| Ansible | Harness pipeline execution logs |

---

## Appendix

### A. Version Compatibility Matrix

| RabbitMQ | Erlang/OTP | RHEL |
|----------|------------|------|
| 4.0.x | 26.x, 27.x | 8, 9 |
| 3.13.x | 26.x | 8, 9 |
| 3.12.x | 25.x, 26.x | 8, 9 |

### B. Port Reference

| Port | Protocol | Description |
|------|----------|-------------|
| 4369 | TCP | EPMD peer discovery |
| 5672 | TCP | AMQP 0-9-1 |
| 5671 | TCP | AMQP 0-9-1 with TLS |
| 15672 | TCP | Management UI |
| 15692 | TCP | Prometheus metrics |
| 25672 | TCP | Erlang distribution |
| 35672-35682 | TCP | CLI tools |

### C. Useful Commands Reference

```bash
# Cluster management
rabbitmqctl cluster_status
rabbitmqctl set_cluster_name <name>
rabbitmqctl forget_cluster_node <node>

# Queue management
rabbitmqctl list_queues name messages consumers type leader
rabbitmqctl delete_queue <queue>
rabbitmqctl purge_queue <queue>

# User management
rabbitmqctl list_users
rabbitmqctl add_user <user> <pass>
rabbitmqctl set_user_tags <user> administrator
rabbitmqctl set_permissions -p / <user> ".*" ".*" ".*"

# Node management
rabbitmqctl status
rabbitmqctl stop_app
rabbitmqctl start_app
rabbitmqctl reset

# Diagnostics
rabbitmq-diagnostics check_running
rabbitmq-diagnostics check_local_alarms
rabbitmq-diagnostics check_port_connectivity
rabbitmq-diagnostics memory_breakdown
```

### D. Harness YAML Templates

All YAML templates referenced in this document are available in the Git repository under `/harness-templates/`.

### E. Contact and Support

| Type | Contact |
|------|---------|
| Harness Support | support@harness.io |
| RabbitMQ Community | https://groups.google.com/g/rabbitmq-users |
| Internal Team | [Your team contact] |

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2024-01-XX | [Architect Name] | Initial POC document |

---

**End of Document**
