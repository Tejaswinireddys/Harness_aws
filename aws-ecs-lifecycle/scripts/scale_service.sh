#!/bin/bash
###############################################################################
# Script: scale_service.sh
# Purpose: Scale ECS services up/down, restart, or stop
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
NC='\033[0m'

# Input parameters
ACTION="${ACTION:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
SERVICE_NAMES="${SERVICE_NAMES:-}"
DESIRED_COUNT="${DESIRED_COUNT:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DRY_RUN="${DRY_RUN:-false}"
WAIT_FOR_STABLE="${WAIT_FOR_STABLE:-true}"
FORCE_NEW_DEPLOYMENT="${FORCE_NEW_DEPLOYMENT:-false}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    ECS SERVICE SCALING EXECUTOR                          ║"
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
        echo -e "${RED}❌ ERROR: ACTION is required (scale_up/scale_down/scale_to/restart/stop)${NC}"
        exit 1
    fi

    if [[ ! "$ACTION" =~ ^(scale_up|scale_down|scale_to|restart|stop)$ ]]; then
        echo -e "${RED}❌ ERROR: Invalid ACTION: $ACTION${NC}"
        echo "  Valid actions: scale_up, scale_down, scale_to, restart, stop"
        exit 1
    fi
    echo -e "${GREEN}✅ Action validated: $ACTION${NC}"

    # Validate cluster
    if [[ -z "$CLUSTER_NAME" ]]; then
        echo -e "${RED}❌ ERROR: CLUSTER_NAME is required${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Cluster: $CLUSTER_NAME${NC}"

    # Validate services
    if [[ -z "$SERVICE_NAMES" ]]; then
        echo -e "${RED}❌ ERROR: SERVICE_NAMES is required${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Services: $SERVICE_NAMES${NC}"

    # Validate desired count for scale actions
    if [[ "$ACTION" == "scale_to" && -z "$DESIRED_COUNT" ]]; then
        echo -e "${RED}❌ ERROR: DESIRED_COUNT required for scale_to action${NC}"
        exit 1
    fi

    if [[ -n "$DESIRED_COUNT" ]]; then
        if ! [[ "$DESIRED_COUNT" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}❌ ERROR: DESIRED_COUNT must be a number${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ Desired count: $DESIRED_COUNT${NC}"
    fi

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

    case $ACTION in
        "scale_up")
            echo "  │  Action          : ${GREEN}SCALE UP${NC}                                   │"
            ;;
        "scale_down")
            echo "  │  Action          : ${YELLOW}SCALE DOWN${NC}                                 │"
            ;;
        "scale_to")
            echo "  │  Action          : ${BLUE}SCALE TO $DESIRED_COUNT${NC}                               │"
            ;;
        "restart")
            echo "  │  Action          : ${CYAN}FORCE NEW DEPLOYMENT${NC}                       │"
            ;;
        "stop")
            echo "  │  Action          : ${RED}STOP (SCALE TO 0)${NC}                          │"
            ;;
    esac

    printf "  │  Cluster         : %-44s │\n" "$CLUSTER_NAME"
    printf "  │  Region          : %-44s │\n" "$AWS_REGION"
    printf "  │  Dry Run         : %-44s │\n" "$DRY_RUN"
    printf "  │  Wait for Stable : %-44s │\n" "$WAIT_FOR_STABLE"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""

    echo "  Target Services:"
    IFS=',' read -ra SERVICES <<< "$SERVICE_NAMES"
    for svc in "${SERVICES[@]}"; do
        echo "    → $(echo "$svc" | tr -d ' ')"
    done
    echo ""
}

# Pre-flight check
preflight_check() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  PRE-FLIGHT CHECK"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Fetching current service states..."
    echo ""

    echo "┌──────────────────────────────┬──────────┬─────────┬─────────┬────────────────┐"
    echo "│ Service Name                 │ Status   │ Desired │ Running │ Action         │"
    echo "├──────────────────────────────┼──────────┼─────────┼─────────┼────────────────┤"

    IFS=',' read -ra SERVICES <<< "$SERVICE_NAMES"
    for svc in "${SERVICES[@]}"; do
        svc=$(echo "$svc" | tr -d ' ')

        SVC_INFO=$(aws ecs describe-services \
            --region "$AWS_REGION" \
            --cluster "$CLUSTER_NAME" \
            --services "$svc" \
            --query 'services[0].{Status: status, Desired: desiredCount, Running: runningCount}' \
            --output json 2>/dev/null) || {
            printf "│ %-28s │ ${RED}%-8s${NC} │ %7s │ %7s │ ${RED}%-14s${NC} │\n" "${svc:0:28}" "ERROR" "N/A" "N/A" "NOT FOUND"
            continue
        }

        status=$(echo "$SVC_INFO" | jq -r '.Status')
        desired=$(echo "$SVC_INFO" | jq -r '.Desired')
        running=$(echo "$SVC_INFO" | jq -r '.Running')

        # Determine new desired count
        new_desired=""
        case $ACTION in
            "scale_up")
                new_desired=$((desired + 1))
                action_label="→ $new_desired"
                ;;
            "scale_down")
                new_desired=$((desired > 0 ? desired - 1 : 0))
                action_label="→ $new_desired"
                ;;
            "scale_to")
                new_desired=$DESIRED_COUNT
                action_label="→ $new_desired"
                ;;
            "restart")
                new_desired=$desired
                action_label="REDEPLOY"
                ;;
            "stop")
                new_desired=0
                action_label="→ 0 (STOP)"
                ;;
        esac

        printf "│ %-28s │ %-8s │ %7s │ %7s │ ${GREEN}%-14s${NC} │\n" \
            "${svc:0:28}" "$status" "$desired" "$running" "$action_label"
    done

    echo "└──────────────────────────────┴──────────┴─────────┴─────────┴────────────────┘"
    echo ""
}

# Execute scaling action
execute_action() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  EXECUTING ACTION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
        echo ""
        echo "Would execute $ACTION on:"
        IFS=',' read -ra SERVICES <<< "$SERVICE_NAMES"
        for svc in "${SERVICES[@]}"; do
            echo "  - $svc"
        done
        echo ""
        echo "ACTION_RESULT=dry_run" >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true
        return 0
    fi

    SUCCESS_COUNT=0
    FAILED_COUNT=0
    EXECUTED_SERVICES=""

    IFS=',' read -ra SERVICES <<< "$SERVICE_NAMES"
    for svc in "${SERVICES[@]}"; do
        svc=$(echo "$svc" | tr -d ' ')

        echo "Processing: $svc"

        # Get current desired count
        CURRENT_DESIRED=$(aws ecs describe-services \
            --region "$AWS_REGION" \
            --cluster "$CLUSTER_NAME" \
            --services "$svc" \
            --query 'services[0].desiredCount' \
            --output text 2>/dev/null) || {
            echo -e "  ${RED}❌ Failed to get service info${NC}"
            FAILED_COUNT=$((FAILED_COUNT + 1))
            continue
        }

        # Calculate new desired count
        NEW_DESIRED=""
        case $ACTION in
            "scale_up")
                NEW_DESIRED=$((CURRENT_DESIRED + 1))
                ;;
            "scale_down")
                NEW_DESIRED=$((CURRENT_DESIRED > 0 ? CURRENT_DESIRED - 1 : 0))
                ;;
            "scale_to")
                NEW_DESIRED=$DESIRED_COUNT
                ;;
            "stop")
                NEW_DESIRED=0
                ;;
            "restart")
                NEW_DESIRED=$CURRENT_DESIRED
                ;;
        esac

        # Build update command
        UPDATE_CMD="aws ecs update-service --region $AWS_REGION --cluster $CLUSTER_NAME --service $svc"

        if [[ "$ACTION" == "restart" || "$FORCE_NEW_DEPLOYMENT" == "true" ]]; then
            UPDATE_CMD="$UPDATE_CMD --force-new-deployment"
            echo -e "  🔄 Forcing new deployment..."
        else
            UPDATE_CMD="$UPDATE_CMD --desired-count $NEW_DESIRED"
            echo -e "  📊 Scaling from $CURRENT_DESIRED → $NEW_DESIRED"
        fi

        # Execute update
        RESULT=$($UPDATE_CMD --output json 2>&1) || {
            echo -e "  ${RED}❌ Failed: $RESULT${NC}"
            FAILED_COUNT=$((FAILED_COUNT + 1))
            continue
        }

        NEW_STATUS=$(echo "$RESULT" | jq -r '.service.status')
        echo -e "  ${GREEN}✅ Success (Status: $NEW_STATUS)${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        EXECUTED_SERVICES="$EXECUTED_SERVICES$svc,"
        echo ""
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ACTION RESULTS: $SUCCESS_COUNT succeeded, $FAILED_COUNT failed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Export results
    {
        echo "ACTION_RESULT=success"
        echo "SUCCESS_COUNT=$SUCCESS_COUNT"
        echo "FAILED_COUNT=$FAILED_COUNT"
        echo "EXECUTED_SERVICES=${EXECUTED_SERVICES%,}"
    } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true
}

# Wait for services to stabilize
wait_for_stable() {
    if [[ "$WAIT_FOR_STABLE" != "true" || "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}⏭️  Skipping stability wait${NC}"
        return 0
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  WAITING FOR SERVICES TO STABILIZE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo -e "${YELLOW}⏳ This may take several minutes...${NC}"
    echo ""

    IFS=',' read -ra SERVICES <<< "$SERVICE_NAMES"
    for svc in "${SERVICES[@]}"; do
        svc=$(echo "$svc" | tr -d ' ')
        echo "  Waiting for $svc to stabilize..."

        aws ecs wait services-stable \
            --region "$AWS_REGION" \
            --cluster "$CLUSTER_NAME" \
            --services "$svc" 2>/dev/null && {
            echo -e "  ${GREEN}✅ $svc is stable${NC}"
        } || {
            echo -e "  ${YELLOW}⚠️  Timeout waiting for $svc${NC}"
        }
    done

    echo ""
}

# Generate summary
generate_summary() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  FINAL SERVICE STATES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "┌──────────────────────────────┬──────────┬─────────┬─────────┬────────────────┐"
    echo "│ Service Name                 │ Status   │ Desired │ Running │ Health         │"
    echo "├──────────────────────────────┼──────────┼─────────┼─────────┼────────────────┤"

    IFS=',' read -ra SERVICES <<< "$SERVICE_NAMES"
    for svc in "${SERVICES[@]}"; do
        svc=$(echo "$svc" | tr -d ' ')

        SVC_INFO=$(aws ecs describe-services \
            --region "$AWS_REGION" \
            --cluster "$CLUSTER_NAME" \
            --services "$svc" \
            --query 'services[0].{Status: status, Desired: desiredCount, Running: runningCount}' \
            --output json 2>/dev/null) || continue

        status=$(echo "$SVC_INFO" | jq -r '.Status')
        desired=$(echo "$SVC_INFO" | jq -r '.Desired')
        running=$(echo "$SVC_INFO" | jq -r '.Running')

        if [[ "$running" -eq "$desired" ]]; then
            health="${GREEN}✅ HEALTHY${NC}"
        elif [[ "$desired" -eq 0 ]]; then
            health="${YELLOW}⏹️  STOPPED${NC}"
        else
            health="${YELLOW}⏳ SCALING${NC}"
        fi

        printf "│ %-28s │ %-8s │ %7s │ %7s │ %-14s │\n" \
            "${svc:0:28}" "$status" "$desired" "$running" "$health"
    done

    echo "└──────────────────────────────┴──────────┴─────────┴─────────┴────────────────┘"
    echo ""

    echo -e "${GREEN}✅ ECS scaling action completed!${NC}"
    echo ""
}

# Main
main() {
    validate_inputs
    display_config
    preflight_check
    execute_action
    wait_for_stable
    generate_summary
}

main "$@"
