# RabbitMQ 4.x Cluster POC - Quick Reference Checklist

## For Management & Confluence

---

## Executive Overview

| Item | Details |
|------|---------|
| **Project** | RabbitMQ 4.x Cluster Deployment with Harness CD |
| **Technology Stack** | RabbitMQ 4.0.x, Erlang 26.x, Ansible 2.15+, RHEL 8 |
| **Deployment Method** | Harness CD Pipeline with Ansible Playbooks |
| **Cluster Size** | 3-node quorum cluster |
| **Environments** | Development → Staging → Production |

---

## POC Success Criteria

- [ ] Successfully deploy 3-node RabbitMQ cluster
- [ ] Demonstrate automated deployment via Harness CD
- [ ] Validate cluster high availability (node failover)
- [ ] Confirm quorum queue functionality
- [ ] Document deployment process for production

---

## Pre-POC Checklist

### Infrastructure Requirements

| Requirement | Specification | Status |
|-------------|---------------|--------|
| RabbitMQ VMs (3) | RHEL 8, 4 vCPU, 8GB RAM, 100GB SSD | [ ] Ready |
| Harness Delegate VM | RHEL 8, 2 vCPU, 4GB RAM | [ ] Ready |
| Network Connectivity | Nodes can communicate on ports 4369, 5672, 15672, 25672 | [ ] Verified |
| DNS/Hosts Resolution | All nodes resolvable by hostname | [ ] Verified |
| SSH Key Pair | Generated for passwordless access | [ ] Created |
| Git Repository | For storing Ansible playbooks | [ ] Created |

### Harness Account Setup

| Task | Status |
|------|--------|
| Harness account created/available | [ ] Done |
| Project created: `rabbitmq-cluster-poc` | [ ] Done |
| Delegate installed with Ansible | [ ] Done |
| Git connector configured | [ ] Done |
| SSH credential secret stored | [ ] Done |
| Password secrets stored | [ ] Done |

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                     HARNESS CD                               │
│  Pipeline → Git Repo (Ansible) → Delegate → Target VMs      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              RABBITMQ 3-NODE CLUSTER                         │
│                                                              │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│   │ rabbitmq-01 │  │ rabbitmq-02 │  │ rabbitmq-03 │        │
│   │   (Master)  │  │  (Replica)  │  │  (Replica)  │        │
│   │  RHEL 8     │  │  RHEL 8     │  │  RHEL 8     │        │
│   └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │                  │
│         └────────────────┼────────────────┘                  │
│                          │                                   │
│              Erlang Distribution Protocol                    │
│                 (Quorum Consensus)                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Configuration Values

### Network Ports

| Port | Purpose |
|------|---------|
| 4369 | EPMD (Erlang Port Mapper) |
| 5672 | AMQP Client Connections |
| 5671 | AMQPS (TLS) |
| 15672 | Management UI/API |
| 15692 | Prometheus Metrics |
| 25672 | Erlang Distribution |

### Default Credentials (POC Only)

| User | Purpose | Tags |
|------|---------|------|
| admin | Administrative access | administrator |
| monitoring | Metrics/monitoring | monitoring |
| app_user | Application access | (none) |

> **Note:** Change all default passwords before production use!

---

## Deployment Pipeline Stages

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Stage 1    │───▶│   Stage 2    │───▶│   Stage 3    │───▶│   Stage 4    │
│  Pre-Flight  │    │  Deploy Dev  │    │   Approval   │    │ Deploy Stg   │
│   Checks     │    │              │    │    Gate      │    │              │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
       │                                                            │
       │                                                            ▼
       │                                      ┌──────────────┐    ┌──────────────┐
       │                                      │   Stage 6    │◀───│   Stage 5    │
       │                                      │ Deploy Prod  │    │ Prod Approval│
       │                                      └──────────────┘    └──────────────┘
       │
       └──── Validates: OS, Memory, Disk, DNS, Ports
```

---

## Harness Pipeline Flow (Passwordless Connection)

### Step 1: Code Repository Setup
```
Git Repository
    └── rabbitmq-ansible/
        ├── ansible.cfg
        ├── inventory/
        │   ├── dev/hosts.yml
        │   ├── staging/hosts.yml
        │   └── production/hosts.yml
        ├── roles/rabbitmq/
        └── playbooks/deploy.yml
```

### Step 2: Harness Delegate Configuration
```
Delegate VM (RHEL 8)
    ├── Harness Delegate Agent (Docker/Native)
    ├── Ansible 2.15+ installed
    ├── SSH Private Key stored
    └── Network access to target VMs
```

### Step 3: Passwordless SSH Setup
```bash
# On Delegate:
# 1. SSH key stored in Harness Secrets Manager
# 2. Key injected at runtime during pipeline execution

# On Target VMs (rabbitmq-01, 02, 03):
# 1. 'ansible' user created with SSH key
# 2. Passwordless sudo configured
# 3. SSH key in ~/.ssh/authorized_keys
```

### Step 4: Pipeline Execution Flow
```
Harness Pipeline Trigger
    │
    ▼
Clone Ansible Code from Git
    │
    ▼
Inject SSH Key from Harness Secrets
    │
    ▼
Delegate executes: ansible-playbook -i inventory/dev/hosts.yml playbooks/deploy.yml
    │
    ▼
Ansible connects to VMs via SSH (passwordless)
    │
    ▼
Playbook installs and configures RabbitMQ cluster
```

---

## POC Execution Steps

### Day 1: Infrastructure Setup

| # | Task | Owner | Duration | Status |
|---|------|-------|----------|--------|
| 1 | Provision 3 RHEL 8 VMs for RabbitMQ | Infra Team | 2 hrs | [ ] |
| 2 | Provision 1 RHEL 8 VM for Delegate | Infra Team | 1 hr | [ ] |
| 3 | Configure network/firewall rules | Network Team | 2 hrs | [ ] |
| 4 | Create DNS entries or /etc/hosts | Infra Team | 30 min | [ ] |
| 5 | Generate SSH key pair | DevOps | 15 min | [ ] |
| 6 | Create ansible user on all VMs | DevOps | 1 hr | [ ] |
| 7 | Configure passwordless sudo | DevOps | 30 min | [ ] |

### Day 2: Harness & Ansible Setup

| # | Task | Owner | Duration | Status |
|---|------|-------|----------|--------|
| 1 | Install Harness Delegate | DevOps | 1 hr | [ ] |
| 2 | Verify Delegate connectivity | DevOps | 30 min | [ ] |
| 3 | Push Ansible code to Git repo | DevOps | 30 min | [ ] |
| 4 | Create Harness Git connector | DevOps | 30 min | [ ] |
| 5 | Store SSH key in Harness Secrets | DevOps | 15 min | [ ] |
| 6 | Store passwords in Harness Secrets | DevOps | 15 min | [ ] |
| 7 | Create Harness Service | DevOps | 30 min | [ ] |
| 8 | Create Harness Environments | DevOps | 30 min | [ ] |

### Day 3: Pipeline Creation & Testing

| # | Task | Owner | Duration | Status |
|---|------|-------|----------|--------|
| 1 | Create Harness Pipeline | DevOps | 2 hrs | [ ] |
| 2 | Test Pre-Flight stage | DevOps | 30 min | [ ] |
| 3 | Execute Dev deployment | DevOps | 1 hr | [ ] |
| 4 | Validate cluster formation | DevOps | 30 min | [ ] |
| 5 | Test failover scenario | DevOps | 1 hr | [ ] |
| 6 | Document any issues | DevOps | 30 min | [ ] |

### Day 4: Validation & Demo

| # | Task | Owner | Duration | Status |
|---|------|-------|----------|--------|
| 1 | Full pipeline execution | DevOps | 1 hr | [ ] |
| 2 | Performance baseline | DevOps | 1 hr | [ ] |
| 3 | Prepare demo environment | DevOps | 1 hr | [ ] |
| 4 | Management demo/presentation | DevOps | 1 hr | [ ] |

---

## Validation Checklist

### Cluster Health
- [ ] All 3 nodes visible in cluster status
- [ ] All nodes show "running" state
- [ ] No alarms present
- [ ] Management UI accessible on all nodes

### Functionality
- [ ] Can create quorum queue
- [ ] Messages replicate across nodes
- [ ] Cluster survives single node failure
- [ ] Node rejoins cluster after restart

### Harness Pipeline
- [ ] Pipeline executes without errors
- [ ] All stages complete successfully
- [ ] Approval gates function correctly
- [ ] Rollback works as expected

---

## Risk & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Network latency between nodes | Cluster instability | Use low-latency network, same availability zone |
| Disk space exhaustion | Message loss | Configure disk alarms, monitor usage |
| Erlang cookie mismatch | Nodes can't join | Store cookie in Harness Secrets |
| Port blocked by firewall | Cluster formation fails | Pre-verify all ports open |

---

## Post-POC Recommendations

1. **Production Readiness**
   - Enable TLS for all connections
   - Implement proper backup strategy
   - Configure Prometheus/Grafana monitoring
   - Set up alerting for critical metrics

2. **Security Hardening**
   - Remove default users
   - Use strong passwords (Harness Secrets)
   - Enable audit logging
   - Implement network segmentation

3. **Scaling Considerations**
   - Plan for 5-node cluster for higher availability
   - Consider federation for multi-DC setup
   - Implement shovel for cross-cluster messaging

---

## Quick Commands Reference

```bash
# Check cluster status
rabbitmqctl cluster_status

# List queues
rabbitmqctl list_queues name type messages consumers

# Check node health
rabbitmq-diagnostics check_running

# Check for alarms
rabbitmq-diagnostics check_local_alarms

# View connections
rabbitmqctl list_connections

# Access Management UI
http://<node-ip>:15672
```

---

## Support & Contacts

| Role | Contact |
|------|---------|
| Project Lead | [Name] |
| DevOps Engineer | [Name] |
| Infrastructure | [Name] |
| Harness Support | support@harness.io |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | YYYY-MM-DD | [Name] | Initial POC documentation |

---

## Attachments

1. [HARNESS_RABBITMQ_CLUSTER_POC.md](./HARNESS_RABBITMQ_CLUSTER_POC.md) - Detailed technical guide
2. [rabbitmq-ansible/](./rabbitmq-ansible/) - Ansible playbooks and roles

---

**End of Quick Reference**
