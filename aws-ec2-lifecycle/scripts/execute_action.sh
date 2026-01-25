#!/bin/bash
###############################################################################
# Script: execute_action.sh
# Purpose: Execute start/stop actions on EC2 instances
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
ACTION="${ACTION:-}"
INSTANCE_IDS="${INSTANCE_IDS:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DRY_RUN="${DRY_RUN:-false}"
WAIT_FOR_STATE="${WAIT_FOR_STATE:-true}"
MAX_WAIT_TIME="${MAX_WAIT_TIME:-300}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    EC2 LIFECYCLE ACTION EXECUTOR                         ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Validate inputs
validate_inputs() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  INPUT VALIDATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Validate action
    if [[ -z "$ACTION" ]]; then
        echo -e "${RED}❌ ERROR: ACTION is required (start/stop)${NC}"
        exit 1
    fi

    if [[ "$ACTION" != "start" && "$ACTION" != "stop" ]]; then
        echo -e "${RED}❌ ERROR: ACTION must be 'start' or 'stop'. Got: $ACTION${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Action validated: $ACTION${NC}"

    # Validate instance IDs
    if [[ -z "$INSTANCE_IDS" ]]; then
        echo -e "${RED}❌ ERROR: INSTANCE_IDS is required${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Instance IDs provided${NC}"

    # Validate instance ID format
    IFS=',' read -ra IDS <<< "$INSTANCE_IDS"
    for id in "${IDS[@]}"; do
        id=$(echo "$id" | tr -d ' ')
        if [[ ! $id =~ ^i-[a-f0-9]{8,17}$ ]]; then
            echo -e "${RED}❌ ERROR: Invalid instance ID format: $id${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}✅ Instance ID format validated${NC}"

    # Count instances
    INSTANCE_COUNT=${#IDS[@]}
    if [[ $INSTANCE_COUNT -gt 20 ]]; then
        echo -e "${YELLOW}⚠️  WARNING: Operating on $INSTANCE_COUNT instances (limit: 20)${NC}"
    fi
    echo -e "${GREEN}✅ Instance count: $INSTANCE_COUNT${NC}"

    echo ""
}

# Display configuration
display_config() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  EXECUTION CONFIGURATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │  OPERATION DETAILS                                              │"
    echo "  ├─────────────────────────────────────────────────────────────────┤"

    if [[ "$ACTION" == "start" ]]; then
        echo "  │  Action          : ${GREEN}START INSTANCES${NC}                           │"
    else
        echo "  │  Action          : ${RED}STOP INSTANCES${NC}                            │"
    fi

    printf "  │  Region          : %-44s │\n" "$AWS_REGION"
    printf "  │  Dry Run         : %-44s │\n" "$DRY_RUN"
    printf "  │  Wait for State  : %-44s │\n" "$WAIT_FOR_STATE"
    printf "  │  Max Wait Time   : %-44s │\n" "${MAX_WAIT_TIME}s"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Target Instances:"
    IFS=',' read -ra IDS <<< "$INSTANCE_IDS"
    for id in "${IDS[@]}"; do
        id=$(echo "$id" | tr -d ' ')
        echo "    → $id"
    done
    echo ""
}

# Pre-flight check - get current state
preflight_check() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  PRE-FLIGHT CHECK"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Fetching current instance states..."
    echo ""

    # Convert comma-separated to space-separated for AWS CLI
    INSTANCE_LIST=$(echo "$INSTANCE_IDS" | tr ',' ' ')

    CURRENT_STATES=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids $INSTANCE_LIST \
        --query 'Reservations[].Instances[].{InstanceId: InstanceId, State: State.Name, Name: Tags[?Key==`Name`].Value | [0]}' \
        --output json 2>&1) || {
        echo -e "${RED}❌ ERROR: Failed to fetch instance states${NC}"
        echo "$CURRENT_STATES"
        exit 1
    }

    echo "┌────────────────────┬─────────────┬────────────────────────────────────┐"
    echo "│ Instance ID        │ State       │ Name                               │"
    echo "├────────────────────┼─────────────┼────────────────────────────────────┤"

    SKIP_LIST=""
    EXECUTE_LIST=""

    echo "$CURRENT_STATES" | jq -r '.[] | [.InstanceId, .State, .Name // "Unnamed"] | @tsv' | while IFS=$'\t' read -r id state name; do
        state_padded=$(printf "%-11s" "$state")
        name_truncated="${name:0:34}"

        # Determine if action is needed
        if [[ "$ACTION" == "start" && "$state" == "running" ]]; then
            printf "│ %-18s │ ${GREEN}%-11s${NC} │ %-34s │ ${YELLOW}SKIP${NC}\n" "$id" "$state" "$name_truncated"
        elif [[ "$ACTION" == "stop" && "$state" == "stopped" ]]; then
            printf "│ %-18s │ ${RED}%-11s${NC} │ %-34s │ ${YELLOW}SKIP${NC}\n" "$id" "$state" "$name_truncated"
        else
            printf "│ %-18s │ %-11s │ %-34s │ ${GREEN}EXECUTE${NC}\n" "$id" "$state" "$name_truncated"
        fi
    done

    echo "└────────────────────┴─────────────┴────────────────────────────────────┘"
    echo ""
}

# Execute the action
execute_action() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  EXECUTING ACTION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    INSTANCE_LIST=$(echo "$INSTANCE_IDS" | tr ',' ' ')

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
        echo ""
        echo "Would execute: aws ec2 ${ACTION}-instances --instance-ids $INSTANCE_LIST"
        echo ""
        echo "DRY_RUN_SUCCESS=true" >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true
        return 0
    fi

    # Execute start or stop
    if [[ "$ACTION" == "start" ]]; then
        echo -e "${GREEN}🚀 Starting instances...${NC}"
        echo ""

        RESULT=$(aws ec2 start-instances \
            --region "$AWS_REGION" \
            --instance-ids $INSTANCE_LIST \
            --output json 2>&1) || {
            echo -e "${RED}❌ ERROR: Failed to start instances${NC}"
            echo "$RESULT"
            exit 1
        }

        echo "Start command issued successfully!"
        echo ""
        echo "$RESULT" | jq -r '.StartingInstances[] | "  \(.InstanceId): \(.PreviousState.Name) → \(.CurrentState.Name)"'

    else
        echo -e "${RED}⏹️  Stopping instances...${NC}"
        echo ""

        RESULT=$(aws ec2 stop-instances \
            --region "$AWS_REGION" \
            --instance-ids $INSTANCE_LIST \
            --output json 2>&1) || {
            echo -e "${RED}❌ ERROR: Failed to stop instances${NC}"
            echo "$RESULT"
            exit 1
        }

        echo "Stop command issued successfully!"
        echo ""
        echo "$RESULT" | jq -r '.StoppingInstances[] | "  \(.InstanceId): \(.PreviousState.Name) → \(.CurrentState.Name)"'
    fi

    echo ""
}

# Wait for instances to reach target state
wait_for_state() {
    if [[ "$WAIT_FOR_STATE" != "true" ]]; then
        echo -e "${YELLOW}⏭️  Skipping state wait (WAIT_FOR_STATE=false)${NC}"
        return 0
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  WAITING FOR TARGET STATE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    INSTANCE_LIST=$(echo "$INSTANCE_IDS" | tr ',' ' ')
    TARGET_STATE=""

    if [[ "$ACTION" == "start" ]]; then
        TARGET_STATE="running"
        echo -e "Waiting for instances to reach ${GREEN}running${NC} state..."
    else
        TARGET_STATE="stopped"
        echo -e "Waiting for instances to reach ${RED}stopped${NC} state..."
    fi

    echo ""

    # Wait with timeout
    START_TIME=$(date +%s)
    WAIT_INTERVAL=10
    SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    SPINNER_IDX=0

    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))

        if [[ $ELAPSED -ge $MAX_WAIT_TIME ]]; then
            echo ""
            echo -e "${YELLOW}⚠️  WARNING: Timeout reached ($MAX_WAIT_TIME seconds)${NC}"
            echo "Some instances may not have reached target state."
            break
        fi

        # Check current states
        STATES=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids $INSTANCE_LIST \
            --query "Reservations[].Instances[].[InstanceId, State.Name]" \
            --output text 2>/dev/null)

        ALL_READY=true
        NOT_READY_COUNT=0

        while IFS=$'\t' read -r id state; do
            if [[ "$state" != "$TARGET_STATE" ]]; then
                ALL_READY=false
                NOT_READY_COUNT=$((NOT_READY_COUNT + 1))
            fi
        done <<< "$STATES"

        if [[ "$ALL_READY" == "true" ]]; then
            echo ""
            echo -e "${GREEN}✅ All instances have reached target state: $TARGET_STATE${NC}"
            break
        fi

        # Show progress
        printf "\r  ${SPINNER[$SPINNER_IDX]} Waiting... (%ds elapsed, %d instance(s) transitioning)   " "$ELAPSED" "$NOT_READY_COUNT"
        SPINNER_IDX=$(( (SPINNER_IDX + 1) % 10 ))

        sleep $WAIT_INTERVAL
    done

    echo ""
}

# Generate summary report
generate_report() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  EXECUTION SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    INSTANCE_LIST=$(echo "$INSTANCE_IDS" | tr ',' ' ')

    FINAL_STATES=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids $INSTANCE_LIST \
        --query 'Reservations[].Instances[].{InstanceId: InstanceId, State: State.Name, Name: Tags[?Key==`Name`].Value | [0]}' \
        --output json 2>/dev/null)

    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │                    FINAL INSTANCE STATES                        │"
    echo "  ├─────────────────────────────────────────────────────────────────┤"

    SUCCESS_COUNT=0
    TOTAL_COUNT=0

    TARGET_STATE=""
    if [[ "$ACTION" == "start" ]]; then
        TARGET_STATE="running"
    else
        TARGET_STATE="stopped"
    fi

    echo "$FINAL_STATES" | jq -r '.[] | [.InstanceId, .State, .Name // "Unnamed"] | @tsv' | while IFS=$'\t' read -r id state name; do
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        if [[ "$state" == "$TARGET_STATE" ]]; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            printf "  │  ${GREEN}✅${NC} %-17s │ ${GREEN}%-10s${NC} │ %-20s │\n" "$id" "$state" "${name:0:20}"
        else
            printf "  │  ${YELLOW}⏳${NC} %-17s │ ${YELLOW}%-10s${NC} │ %-20s │\n" "$id" "$state" "${name:0:20}"
        fi
    done

    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""

    # Export results
    {
        echo "ACTION_EXECUTED=$ACTION"
        echo "INSTANCES_PROCESSED=$INSTANCE_IDS"
        echo "TARGET_STATE=$TARGET_STATE"
        echo "EXECUTION_STATUS=success"
    } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

    echo -e "${GREEN}✅ Action execution completed successfully!${NC}"
    echo ""
}

# Main execution
main() {
    validate_inputs
    display_config
    preflight_check

    # Confirmation prompt in non-Harness environments
    if [[ -z "${HARNESS_OUTPUT_FILE:-}" ]]; then
        echo -e "${YELLOW}⚠️  About to $ACTION ${#IDS[@]} instance(s)${NC}"
        read -p "Continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            exit 0
        fi
    fi

    execute_action
    wait_for_state
    generate_report
}

# Run main
main "$@"
