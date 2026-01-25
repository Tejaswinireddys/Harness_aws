#!/bin/bash
###############################################################################
# Script: discover_instances.sh
# Purpose: Discover and list RDS instances and Aurora clusters
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
ACTION="${ACTION:-list_all}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENGINE_FILTER="${ENGINE_FILTER:-}"
ENVIRONMENT_FILTER="${ENVIRONMENT_FILTER:-}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    RDS INSTANCE DISCOVERY SERVICE                        ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Function to get state color
get_state_color() {
    local state=$1
    case $state in
        "available") echo -e "${GREEN}$state${NC}" ;;
        "stopped") echo -e "${RED}$state${NC}" ;;
        "starting"|"stopping"|"modifying") echo -e "${YELLOW}$state${NC}" ;;
        "creating"|"deleting") echo -e "${MAGENTA}$state${NC}" ;;
        *) echo "$state" ;;
    esac
}

# Print configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DISCOVERY CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Action          : $ACTION"
echo "  Region          : $AWS_REGION"
echo "  Engine Filter   : ${ENGINE_FILTER:-All Engines}"
echo "  Environment     : ${ENVIRONMENT_FILTER:-All Environments}"
echo ""

# Fetch RDS instances
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  FETCHING RDS INSTANCES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Query RDS instances
INSTANCES=$(aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --query 'DBInstances[].{
        DBIdentifier: DBInstanceIdentifier,
        Status: DBInstanceStatus,
        Engine: Engine,
        EngineVersion: EngineVersion,
        Class: DBInstanceClass,
        Storage: AllocatedStorage,
        Endpoint: Endpoint.Address,
        Port: Endpoint.Port,
        MultiAZ: MultiAZ,
        ReadReplica: ReadReplicaSourceDBInstanceIdentifier
    }' \
    --output json 2>&1) || {
    echo -e "${RED}❌ Failed to fetch RDS instances${NC}"
    exit 1
}

# Filter by engine if specified
if [[ -n "$ENGINE_FILTER" ]]; then
    INSTANCES=$(echo "$INSTANCES" | jq --arg engine "$ENGINE_FILTER" '[.[] | select(.Engine | contains($engine))]')
fi

# Filter by status based on action
case $ACTION in
    "list_available")
        INSTANCES=$(echo "$INSTANCES" | jq '[.[] | select(.Status == "available")]')
        ;;
    "list_stopped")
        INSTANCES=$(echo "$INSTANCES" | jq '[.[] | select(.Status == "stopped")]')
        ;;
esac

# Count instances
TOTAL_COUNT=$(echo "$INSTANCES" | jq 'length')
AVAILABLE_COUNT=$(echo "$INSTANCES" | jq '[.[] | select(.Status == "available")] | length')
STOPPED_COUNT=$(echo "$INSTANCES" | jq '[.[] | select(.Status == "stopped")] | length')
OTHER_COUNT=$((TOTAL_COUNT - AVAILABLE_COUNT - STOPPED_COUNT))

# Display summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RDS INSTANCES SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │                  INSTANCE COUNT BY STATUS                       │"
echo "  ├─────────────────────────────────────────────────────────────────┤"
printf "  │  ${GREEN}● Available${NC}  : %-48s │\n" "$AVAILABLE_COUNT instances"
printf "  │  ${RED}● Stopped${NC}    : %-48s │\n" "$STOPPED_COUNT instances"
printf "  │  ${YELLOW}● Other${NC}      : %-48s │\n" "$OTHER_COUNT instances"
echo "  ├─────────────────────────────────────────────────────────────────┤"
printf "  │  ${CYAN}Total${NC}        : %-48s │\n" "$TOTAL_COUNT instances"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""

if [[ "$TOTAL_COUNT" -gt 0 ]]; then
    # Display instance details
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  RDS INSTANCE DETAILS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "┌──────────────────────────┬─────────────┬──────────────┬───────────────┬────────┬─────────┐"
    echo "│ DB Identifier            │ Status      │ Engine       │ Class         │ Storage│ Multi-AZ│"
    echo "├──────────────────────────┼─────────────┼──────────────┼───────────────┼────────┼─────────┤"

    echo "$INSTANCES" | jq -r '.[] | [.DBIdentifier, .Status, .Engine, .Class, (.Storage | tostring), (if .MultiAZ then "Yes" else "No" end)] | @tsv' | while IFS=$'\t' read -r id status engine class storage multiaz; do
        id_display="${id:0:24}"
        engine_display="${engine:0:12}"
        class_display="${class:0:13}"

        printf "│ %-24s │ %-11s │ %-12s │ %-13s │ %4s GB│ %-7s │\n" \
            "$id_display" "$status" "$engine_display" "$class_display" "$storage" "$multiaz"
    done

    echo "└──────────────────────────┴─────────────┴──────────────┴───────────────┴────────┴─────────┘"
    echo ""

    # Engine breakdown
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ENGINE BREAKDOWN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "$INSTANCES" | jq -r 'group_by(.Engine) | .[] | "\(.[0].Engine): \(length)"' | while read -r line; do
        engine_name=$(echo "$line" | cut -d: -f1)
        engine_count=$(echo "$line" | cut -d: -f2 | tr -d ' ')
        printf "  %-20s: %s instances\n" "$engine_name" "$engine_count"
    done
    echo ""
fi

# Fetch Aurora Clusters
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AURORA CLUSTERS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CLUSTERS=$(aws rds describe-db-clusters \
    --region "$AWS_REGION" \
    --query 'DBClusters[].{
        ClusterIdentifier: DBClusterIdentifier,
        Status: Status,
        Engine: Engine,
        EngineVersion: EngineVersion,
        Members: DBClusterMembers,
        Endpoint: Endpoint,
        ReaderEndpoint: ReaderEndpoint
    }' \
    --output json 2>&1) || {
    echo "No Aurora clusters found or permission denied"
    CLUSTERS="[]"
}

CLUSTER_COUNT=$(echo "$CLUSTERS" | jq 'length')

if [[ "$CLUSTER_COUNT" -gt 0 ]]; then
    echo "┌──────────────────────────┬─────────────┬──────────────────────┬─────────┐"
    echo "│ Cluster Identifier       │ Status      │ Engine               │ Members │"
    echo "├──────────────────────────┼─────────────┼──────────────────────┼─────────┤"

    echo "$CLUSTERS" | jq -r '.[] | [.ClusterIdentifier, .Status, .Engine, (.Members | length | tostring)] | @tsv' | while IFS=$'\t' read -r id status engine members; do
        printf "│ %-24s │ %-11s │ %-20s │ %-7s │\n" "${id:0:24}" "$status" "${engine:0:20}" "$members"
    done

    echo "└──────────────────────────┴─────────────┴──────────────────────┴─────────┘"
else
    echo "  No Aurora clusters found in $AWS_REGION"
fi
echo ""

# Create ID lists for export
AVAILABLE_IDS=$(echo "$INSTANCES" | jq -r '[.[] | select(.Status == "available") | .DBIdentifier] | join(",")')
STOPPED_IDS=$(echo "$INSTANCES" | jq -r '[.[] | select(.Status == "stopped") | .DBIdentifier] | join(",")')
ALL_IDS=$(echo "$INSTANCES" | jq -r '[.[] | .DBIdentifier] | join(",")')
CLUSTER_IDS=$(echo "$CLUSTERS" | jq -r '[.[] | .ClusterIdentifier] | join(",")')

# Export outputs
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  EXPORTING RESULTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

{
    echo "TOTAL_INSTANCES=$TOTAL_COUNT"
    echo "AVAILABLE_INSTANCES=$AVAILABLE_COUNT"
    echo "STOPPED_INSTANCES=$STOPPED_COUNT"
    echo "CLUSTER_COUNT=$CLUSTER_COUNT"
    echo "AVAILABLE_IDS=$AVAILABLE_IDS"
    echo "STOPPED_IDS=$STOPPED_IDS"
    echo "ALL_IDS=$ALL_IDS"
    echo "CLUSTER_IDS=$CLUSTER_IDS"
} >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

echo -e "${GREEN}✅ Discovery complete!${NC}"
echo ""
echo "  Output Variables Exported:"
echo "  ├── TOTAL_INSTANCES     : $TOTAL_COUNT"
echo "  ├── AVAILABLE_INSTANCES : $AVAILABLE_COUNT"
echo "  ├── STOPPED_INSTANCES   : $STOPPED_COUNT"
echo "  ├── CLUSTER_COUNT       : $CLUSTER_COUNT"
echo "  ├── AVAILABLE_IDS       : ${AVAILABLE_IDS:-None}"
echo "  └── STOPPED_IDS         : ${STOPPED_IDS:-None}"
echo ""
