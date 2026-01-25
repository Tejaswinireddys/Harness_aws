#!/bin/bash
###############################################################################
# Script: discover_clusters.sh
# Purpose: Discover and list ECS clusters, services, and tasks
# Author: Platform Team
# Version: 1.0.0
###############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Input parameters
ACTION="${ACTION:-list_clusters}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
SERVICE_NAME="${SERVICE_NAME:-}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    ECS CLUSTER DISCOVERY SERVICE                         ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Print configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DISCOVERY CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Action          : $ACTION"
echo "  Region          : $AWS_REGION"
echo "  Cluster Filter  : ${CLUSTER_NAME:-All Clusters}"
echo "  Service Filter  : ${SERVICE_NAME:-All Services}"
echo ""

# Function to get status color
get_status_color() {
    local status=$1
    case $status in
        "ACTIVE") echo -e "${GREEN}$status${NC}" ;;
        "INACTIVE"|"DRAINING") echo -e "${RED}$status${NC}" ;;
        "PROVISIONING"|"PENDING") echo -e "${YELLOW}$status${NC}" ;;
        "RUNNING") echo -e "${GREEN}$status${NC}" ;;
        "STOPPED") echo -e "${RED}$status${NC}" ;;
        *) echo "$status" ;;
    esac
}

# Fetch clusters
fetch_clusters() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ECS CLUSTERS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Get cluster ARNs
    CLUSTER_ARNS=$(aws ecs list-clusters --region "$AWS_REGION" --query 'clusterArns' --output json 2>&1) || {
        echo -e "${RED}❌ Failed to list clusters${NC}"
        exit 1
    }

    CLUSTER_COUNT=$(echo "$CLUSTER_ARNS" | jq 'length')

    if [[ "$CLUSTER_COUNT" -eq 0 ]]; then
        echo "  No ECS clusters found in $AWS_REGION"
        echo ""
        echo "CLUSTER_COUNT=0" >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true
        return
    fi

    # Get cluster details
    CLUSTERS=$(aws ecs describe-clusters \
        --region "$AWS_REGION" \
        --clusters $(echo "$CLUSTER_ARNS" | jq -r '.[]') \
        --query 'clusters[].{
            Name: clusterName,
            Status: status,
            RunningTasks: runningTasksCount,
            PendingTasks: pendingTasksCount,
            ActiveServices: activeServicesCount,
            RegisteredInstances: registeredContainerInstancesCount
        }' \
        --output json 2>&1)

    # Display cluster summary
    echo "┌────────────────────────────┬──────────┬──────────┬──────────┬──────────┬────────────┐"
    echo "│ Cluster Name               │ Status   │ Running  │ Pending  │ Services │ Instances  │"
    echo "├────────────────────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤"

    TOTAL_RUNNING=0
    TOTAL_SERVICES=0

    echo "$CLUSTERS" | jq -r '.[] | [.Name, .Status, (.RunningTasks|tostring), (.PendingTasks|tostring), (.ActiveServices|tostring), (.RegisteredInstances|tostring)] | @tsv' | while IFS=$'\t' read -r name status running pending services instances; do
        printf "│ %-26s │ %-8s │ %8s │ %8s │ %8s │ %10s │\n" \
            "${name:0:26}" "$status" "$running" "$pending" "$services" "$instances"

        TOTAL_RUNNING=$((TOTAL_RUNNING + running))
        TOTAL_SERVICES=$((TOTAL_SERVICES + services))
    done

    echo "└────────────────────────────┴──────────┴──────────┴──────────┴──────────┴────────────┘"
    echo ""

    # Summary
    ACTIVE_CLUSTERS=$(echo "$CLUSTERS" | jq '[.[] | select(.Status == "ACTIVE")] | length')

    echo "  Summary: $CLUSTER_COUNT clusters | $ACTIVE_CLUSTERS active"
    echo ""

    # Export
    {
        echo "CLUSTER_COUNT=$CLUSTER_COUNT"
        echo "ACTIVE_CLUSTERS=$ACTIVE_CLUSTERS"
        echo "CLUSTER_NAMES=$(echo "$CLUSTERS" | jq -r '[.[].Name] | join(",")')"
    } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true
}

# Fetch services for a cluster
fetch_services() {
    local cluster=$1

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  SERVICES IN CLUSTER: $cluster"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Get service ARNs
    SERVICE_ARNS=$(aws ecs list-services \
        --region "$AWS_REGION" \
        --cluster "$cluster" \
        --query 'serviceArns' \
        --output json 2>&1) || {
        echo -e "${YELLOW}⚠️  No services found or access denied${NC}"
        return
    }

    SERVICE_COUNT=$(echo "$SERVICE_ARNS" | jq 'length')

    if [[ "$SERVICE_COUNT" -eq 0 ]]; then
        echo "  No services found in cluster: $cluster"
        echo ""
        return
    fi

    # Get service details (batch of 10)
    SERVICES=$(aws ecs describe-services \
        --region "$AWS_REGION" \
        --cluster "$cluster" \
        --services $(echo "$SERVICE_ARNS" | jq -r '.[]' | head -10) \
        --query 'services[].{
            Name: serviceName,
            Status: status,
            Desired: desiredCount,
            Running: runningCount,
            Pending: pendingCount,
            LaunchType: launchType,
            TaskDef: taskDefinition
        }' \
        --output json 2>&1)

    echo "┌──────────────────────────────┬──────────┬─────────┬─────────┬─────────┬──────────┐"
    echo "│ Service Name                 │ Status   │ Desired │ Running │ Pending │ Launch   │"
    echo "├──────────────────────────────┼──────────┼─────────┼─────────┼─────────┼──────────┤"

    echo "$SERVICES" | jq -r '.[] | [.Name, .Status, (.Desired|tostring), (.Running|tostring), (.Pending|tostring), (.LaunchType // "EC2")] | @tsv' | while IFS=$'\t' read -r name status desired running pending launch; do
        # Color coding for health
        if [[ "$running" -eq "$desired" && "$desired" -gt 0 ]]; then
            health="${GREEN}●${NC}"
        elif [[ "$running" -eq 0 && "$desired" -eq 0 ]]; then
            health="${YELLOW}○${NC}"
        else
            health="${RED}●${NC}"
        fi

        printf "│ %-28s │ %-8s │ %7s │ %7s │ %7s │ %-8s │\n" \
            "${name:0:28}" "$status" "$desired" "$running" "$pending" "${launch:0:8}"
    done

    echo "└──────────────────────────────┴──────────┴─────────┴─────────┴─────────┴──────────┘"
    echo ""

    # Calculate health stats
    HEALTHY=$(echo "$SERVICES" | jq '[.[] | select(.Running == .Desired and .Desired > 0)] | length')
    SCALED_DOWN=$(echo "$SERVICES" | jq '[.[] | select(.Desired == 0)] | length')
    UNHEALTHY=$(echo "$SERVICES" | jq '[.[] | select(.Running != .Desired and .Desired > 0)] | length')

    echo "  Health: ${GREEN}$HEALTHY healthy${NC} | ${YELLOW}$SCALED_DOWN scaled to 0${NC} | ${RED}$UNHEALTHY unhealthy${NC}"
    echo ""

    # Export
    {
        echo "SERVICE_COUNT_${cluster}=$SERVICE_COUNT"
        echo "SERVICE_NAMES_${cluster}=$(echo "$SERVICES" | jq -r '[.[].Name] | join(",")')"
        echo "HEALTHY_SERVICES_${cluster}=$HEALTHY"
        echo "SCALED_DOWN_SERVICES_${cluster}=$SCALED_DOWN"
    } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true
}

# Fetch tasks for a service
fetch_tasks() {
    local cluster=$1
    local service=$2

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  TASKS IN SERVICE: $cluster/$service"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Get task ARNs
    TASK_ARNS=$(aws ecs list-tasks \
        --region "$AWS_REGION" \
        --cluster "$cluster" \
        --service-name "$service" \
        --query 'taskArns' \
        --output json 2>&1) || {
        echo "  No tasks found"
        return
    }

    TASK_COUNT=$(echo "$TASK_ARNS" | jq 'length')

    if [[ "$TASK_COUNT" -eq 0 ]]; then
        echo "  No running tasks in service: $service"
        echo ""
        return
    fi

    # Get task details
    TASKS=$(aws ecs describe-tasks \
        --region "$AWS_REGION" \
        --cluster "$cluster" \
        --tasks $(echo "$TASK_ARNS" | jq -r '.[]') \
        --query 'tasks[].{
            TaskArn: taskArn,
            Status: lastStatus,
            DesiredStatus: desiredStatus,
            LaunchType: launchType,
            CPU: cpu,
            Memory: memory,
            StartedAt: startedAt,
            Health: healthStatus
        }' \
        --output json 2>&1)

    echo "┌──────────────────────────────────────┬──────────┬──────────┬────────┬────────┬──────────┐"
    echo "│ Task ID                              │ Status   │ Desired  │ CPU    │ Memory │ Health   │"
    echo "├──────────────────────────────────────┼──────────┼──────────┼────────┼────────┼──────────┤"

    echo "$TASKS" | jq -r '.[] | [(.TaskArn | split("/") | .[-1]), .Status, .DesiredStatus, (.CPU // "256"), (.Memory // "512"), (.Health // "UNKNOWN")] | @tsv' | while IFS=$'\t' read -r id status desired cpu memory health; do
        printf "│ %-36s │ %-8s │ %-8s │ %-6s │ %-6s │ %-8s │\n" \
            "${id:0:36}" "$status" "$desired" "$cpu" "$memory" "$health"
    done

    echo "└──────────────────────────────────────┴──────────┴──────────┴────────┴────────┴──────────┘"
    echo ""

    echo "  Total Tasks: $TASK_COUNT"
    echo ""
}

# Main execution based on action
main() {
    case $ACTION in
        "list_clusters")
            fetch_clusters
            ;;
        "list_services")
            if [[ -z "$CLUSTER_NAME" ]]; then
                # List services for all clusters
                CLUSTER_ARNS=$(aws ecs list-clusters --region "$AWS_REGION" --query 'clusterArns' --output json)
                echo "$CLUSTER_ARNS" | jq -r '.[]' | while read -r arn; do
                    cluster=$(echo "$arn" | awk -F'/' '{print $NF}')
                    fetch_services "$cluster"
                done
            else
                fetch_services "$CLUSTER_NAME"
            fi
            ;;
        "list_tasks")
            if [[ -z "$CLUSTER_NAME" || -z "$SERVICE_NAME" ]]; then
                echo -e "${RED}❌ CLUSTER_NAME and SERVICE_NAME required for list_tasks${NC}"
                exit 1
            fi
            fetch_tasks "$CLUSTER_NAME" "$SERVICE_NAME"
            ;;
        "list_all")
            fetch_clusters
            echo ""
            CLUSTER_ARNS=$(aws ecs list-clusters --region "$AWS_REGION" --query 'clusterArns' --output json)
            echo "$CLUSTER_ARNS" | jq -r '.[]' | while read -r arn; do
                cluster=$(echo "$arn" | awk -F'/' '{print $NF}')
                fetch_services "$cluster"
            done
            ;;
        *)
            echo -e "${RED}❌ Unknown action: $ACTION${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}✅ Discovery complete!${NC}"
    echo ""
}

main "$@"
