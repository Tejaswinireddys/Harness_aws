#!/bin/bash
###############################################################################
# Script: discover_instances.sh
# Purpose: Discover and list EC2 instances with various filters
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
FILTER_TAG_KEY="${FILTER_TAG_KEY:-}"
FILTER_TAG_VALUE="${FILTER_TAG_VALUE:-}"
ENVIRONMENT_FILTER="${ENVIRONMENT_FILTER:-}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    EC2 INSTANCE DISCOVERY SERVICE                        ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Function to print formatted table header
print_table_header() {
    echo ""
    echo "┌────────────────────┬─────────────┬───────────────┬──────────────────┬────────────────────────────┐"
    echo "│ Instance ID        │ State       │ Type          │ Private IP       │ Name                       │"
    echo "├────────────────────┼─────────────┼───────────────┼──────────────────┼────────────────────────────┤"
}

print_table_footer() {
    echo "└────────────────────┴─────────────┴───────────────┴──────────────────┴────────────────────────────┘"
}

# Function to get state color
get_state_color() {
    local state=$1
    case $state in
        "running") echo -e "${GREEN}running${NC}    " ;;
        "stopped") echo -e "${RED}stopped${NC}    " ;;
        "pending") echo -e "${YELLOW}pending${NC}    " ;;
        "stopping") echo -e "${YELLOW}stopping${NC}   " ;;
        "terminated") echo -e "${MAGENTA}terminated${NC} " ;;
        *) echo "$state" ;;
    esac
}

# Function to truncate string
truncate_string() {
    local str=$1
    local max_len=$2
    if [[ ${#str} -gt $max_len ]]; then
        echo "${str:0:$((max_len-3))}..."
    else
        printf "%-${max_len}s" "$str"
    fi
}

# Print configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DISCOVERY CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Action          : $ACTION"
echo "  Region          : $AWS_REGION"
echo "  Tag Filter Key  : ${FILTER_TAG_KEY:-None}"
echo "  Tag Filter Value: ${FILTER_TAG_VALUE:-None}"
echo "  Environment     : ${ENVIRONMENT_FILTER:-All}"
echo ""

# Build filter based on action
build_filter() {
    local filter=""

    case $ACTION in
        "list_running")
            filter="Name=instance-state-name,Values=running"
            ;;
        "list_stopped")
            filter="Name=instance-state-name,Values=stopped"
            ;;
        "list_all")
            filter="Name=instance-state-name,Values=running,stopped,pending,stopping"
            ;;
        *)
            filter="Name=instance-state-name,Values=running,stopped,pending,stopping"
            ;;
    esac

    # Add tag filters if specified
    if [[ -n "$FILTER_TAG_KEY" && -n "$FILTER_TAG_VALUE" ]]; then
        filter="$filter Name=tag:$FILTER_TAG_KEY,Values=$FILTER_TAG_VALUE"
    fi

    # Add environment filter if specified
    if [[ -n "$ENVIRONMENT_FILTER" ]]; then
        filter="$filter Name=tag:Environment,Values=$ENVIRONMENT_FILTER"
    fi

    echo "$filter"
}

# Fetch instances
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  FETCHING EC2 INSTANCES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

FILTER=$(build_filter)
echo "Applied filter: $FILTER"
echo ""

# Query EC2 instances
INSTANCES=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters $FILTER \
    --query 'Reservations[].Instances[].{
        InstanceId: InstanceId,
        State: State.Name,
        InstanceType: InstanceType,
        PrivateIp: PrivateIpAddress,
        PublicIp: PublicIpAddress,
        Name: Tags[?Key==`Name`].Value | [0],
        Environment: Tags[?Key==`Environment`].Value | [0],
        LaunchTime: LaunchTime
    }' \
    --output json 2>&1) || {
    echo -e "${RED}❌ Failed to fetch instances${NC}"
    echo "Error: $INSTANCES"
    exit 1
}

# Parse and display instances
INSTANCE_COUNT=$(echo "$INSTANCES" | jq 'length')

if [[ "$INSTANCE_COUNT" -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  No instances found matching the criteria${NC}"
    echo ""
    # Export empty results
    echo "TOTAL_INSTANCES=0" >> $HARNESS_OUTPUT_FILE 2>/dev/null || true
    echo "RUNNING_INSTANCES=0" >> $HARNESS_OUTPUT_FILE 2>/dev/null || true
    echo "STOPPED_INSTANCES=0" >> $HARNESS_OUTPUT_FILE 2>/dev/null || true
    echo "INSTANCE_LIST=" >> $HARNESS_OUTPUT_FILE 2>/dev/null || true
    exit 0
fi

# Count by state
RUNNING_COUNT=$(echo "$INSTANCES" | jq '[.[] | select(.State == "running")] | length')
STOPPED_COUNT=$(echo "$INSTANCES" | jq '[.[] | select(.State == "stopped")] | length')
PENDING_COUNT=$(echo "$INSTANCES" | jq '[.[] | select(.State == "pending")] | length')
STOPPING_COUNT=$(echo "$INSTANCES" | jq '[.[] | select(.State == "stopping")] | length')

# Display summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DISCOVERY SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │                    INSTANCE COUNT BY STATE                      │"
echo "  ├─────────────────────────────────────────────────────────────────┤"
printf "  │  ${GREEN}● Running${NC}   : %-48s │\n" "$RUNNING_COUNT instances"
printf "  │  ${RED}● Stopped${NC}   : %-48s │\n" "$STOPPED_COUNT instances"
printf "  │  ${YELLOW}● Pending${NC}   : %-48s │\n" "$PENDING_COUNT instances"
printf "  │  ${YELLOW}● Stopping${NC}  : %-48s │\n" "$STOPPING_COUNT instances"
echo "  ├─────────────────────────────────────────────────────────────────┤"
printf "  │  ${CYAN}Total${NC}       : %-48s │\n" "$INSTANCE_COUNT instances"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""

# Display instance details
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  INSTANCE DETAILS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

print_table_header

echo "$INSTANCES" | jq -r '.[] | [.InstanceId, .State, .InstanceType, .PrivateIp // "N/A", .Name // "Unnamed"] | @tsv' | while IFS=$'\t' read -r id state type ip name; do
    state_display=$(get_state_color "$state")
    name_truncated=$(truncate_string "${name:-Unnamed}" 26)
    ip_display=$(printf "%-16s" "${ip:-N/A}")
    type_display=$(printf "%-13s" "$type")

    printf "│ %-18s │ %-11s │ %-13s │ %-16s │ %-26s │\n" "$id" "$state" "$type" "${ip:-N/A}" "${name:-Unnamed}"
done

print_table_footer
echo ""

# Create instance lists for export
RUNNING_IDS=$(echo "$INSTANCES" | jq -r '[.[] | select(.State == "running") | .InstanceId] | join(",")')
STOPPED_IDS=$(echo "$INSTANCES" | jq -r '[.[] | select(.State == "stopped") | .InstanceId] | join(",")')
ALL_IDS=$(echo "$INSTANCES" | jq -r '[.[] | .InstanceId] | join(",")')

# Environment breakdown
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ENVIRONMENT BREAKDOWN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "$INSTANCES" | jq -r 'group_by(.Environment) | .[] | "\(.[0].Environment // "Untagged"): \(length)"' | while read -r line; do
    env_name=$(echo "$line" | cut -d: -f1)
    env_count=$(echo "$line" | cut -d: -f2 | tr -d ' ')
    printf "  %-20s: %s instances\n" "$env_name" "$env_count"
done

echo ""

# Export output variables for Harness
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  EXPORTING RESULTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Write to Harness output file
{
    echo "TOTAL_INSTANCES=$INSTANCE_COUNT"
    echo "RUNNING_INSTANCES=$RUNNING_COUNT"
    echo "STOPPED_INSTANCES=$STOPPED_COUNT"
    echo "RUNNING_IDS=$RUNNING_IDS"
    echo "STOPPED_IDS=$STOPPED_IDS"
    echo "ALL_IDS=$ALL_IDS"
} >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

echo -e "${GREEN}✅ Discovery complete!${NC}"
echo ""
echo "  Output Variables Exported:"
echo "  ├── TOTAL_INSTANCES   : $INSTANCE_COUNT"
echo "  ├── RUNNING_INSTANCES : $RUNNING_COUNT"
echo "  ├── STOPPED_INSTANCES : $STOPPED_COUNT"
echo "  ├── RUNNING_IDS       : ${RUNNING_IDS:-None}"
echo "  └── STOPPED_IDS       : ${STOPPED_IDS:-None}"
echo ""
