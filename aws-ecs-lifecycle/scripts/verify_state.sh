#!/bin/bash
###############################################################################
# Script: verify_state.sh
# Purpose: Verify ECS services are in expected state after action
# Author: Platform Team
# Version: 1.0.0
###############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Input parameters
CLUSTER_NAME="${CLUSTER_NAME:-}"
SERVICE_NAMES="${SERVICE_NAMES:-}"
EXPECTED_COUNT="${EXPECTED_COUNT:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
RETRY_COUNT="${RETRY_COUNT:-5}"
RETRY_INTERVAL="${RETRY_INTERVAL:-15}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    ECS STATE VERIFICATION SERVICE                        ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Print configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VERIFICATION CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Cluster         : $CLUSTER_NAME"
echo "  Services        : $SERVICE_NAMES"
echo "  Expected Count  : ${EXPECTED_COUNT:-Match Desired}"
echo "  Region          : $AWS_REGION"
echo "  Retry Count     : $RETRY_COUNT"
echo "  Retry Interval  : ${RETRY_INTERVAL}s"
echo ""

# Validate inputs
if [[ -z "$CLUSTER_NAME" ]]; then
    echo -e "${RED}❌ ERROR: CLUSTER_NAME is required${NC}"
    exit 1
fi

if [[ -z "$SERVICE_NAMES" ]]; then
    echo -e "${RED}❌ ERROR: SERVICE_NAMES is required${NC}"
    exit 1
fi

# Verification function
verify_services() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  VERIFYING SERVICE STATES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    ATTEMPT=1
    ALL_VERIFIED=false
    VERIFIED_COUNT=0
    TOTAL_COUNT=0
    FAILED_SERVICES=""

    while [[ $ATTEMPT -le $RETRY_COUNT ]]; do
        echo "Verification Attempt $ATTEMPT of $RETRY_COUNT..."
        echo ""

        VERIFIED_COUNT=0
        TOTAL_COUNT=0
        FAILED_SERVICES=""

        echo "┌──────────────────────────────┬──────────┬─────────┬─────────┬────────────────┐"
        echo "│ Service Name                 │ Status   │ Desired │ Running │ Verification   │"
        echo "├──────────────────────────────┼──────────┼─────────┼─────────┼────────────────┤"

        IFS=',' read -ra SERVICES <<< "$SERVICE_NAMES"
        for svc in "${SERVICES[@]}"; do
            svc=$(echo "$svc" | tr -d ' ')
            TOTAL_COUNT=$((TOTAL_COUNT + 1))

            SVC_INFO=$(aws ecs describe-services \
                --region "$AWS_REGION" \
                --cluster "$CLUSTER_NAME" \
                --services "$svc" \
                --query 'services[0].{Status: status, Desired: desiredCount, Running: runningCount, Pending: pendingCount}' \
                --output json 2>/dev/null) || {
                printf "│ %-28s │ ${RED}%-8s${NC} │ %7s │ %7s │ ${RED}%-14s${NC} │\n" "${svc:0:28}" "ERROR" "N/A" "N/A" "NOT FOUND"
                FAILED_SERVICES="$FAILED_SERVICES$svc,"
                continue
            }

            status=$(echo "$SVC_INFO" | jq -r '.Status')
            desired=$(echo "$SVC_INFO" | jq -r '.Desired')
            running=$(echo "$SVC_INFO" | jq -r '.Running')
            pending=$(echo "$SVC_INFO" | jq -r '.Pending')

            # Determine expected running count
            expected=$desired
            if [[ -n "$EXPECTED_COUNT" ]]; then
                expected=$EXPECTED_COUNT
            fi

            # Check if verified
            if [[ "$running" -eq "$expected" && "$pending" -eq 0 ]]; then
                VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
                printf "│ %-28s │ ${GREEN}%-8s${NC} │ %7s │ %7s │ ${GREEN}%-14s${NC} │\n" \
                    "${svc:0:28}" "$status" "$desired" "$running" "✅ VERIFIED"
            else
                FAILED_SERVICES="$FAILED_SERVICES$svc,"
                if [[ "$pending" -gt 0 ]]; then
                    printf "│ %-28s │ ${YELLOW}%-8s${NC} │ %7s │ %7s │ ${YELLOW}%-14s${NC} │\n" \
                        "${svc:0:28}" "$status" "$desired" "$running" "⏳ PENDING($pending)"
                else
                    printf "│ %-28s │ %-8s │ %7s │ %7s │ ${RED}%-14s${NC} │\n" \
                        "${svc:0:28}" "$status" "$desired" "$running" "❌ MISMATCH"
                fi
            fi
        done

        echo "└──────────────────────────────┴──────────┴─────────┴─────────┴────────────────┘"
        echo ""

        # Check if all verified
        if [[ $VERIFIED_COUNT -eq $TOTAL_COUNT ]]; then
            ALL_VERIFIED=true
            break
        fi

        if [[ $ATTEMPT -lt $RETRY_COUNT ]]; then
            echo -e "${YELLOW}⏳ Not all services verified. Retrying in ${RETRY_INTERVAL}s...${NC}"
            echo ""
            sleep $RETRY_INTERVAL
        fi

        ATTEMPT=$((ATTEMPT + 1))
    done

    # Remove trailing comma
    FAILED_SERVICES="${FAILED_SERVICES%,}"
}

# Generate summary
generate_summary() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  VERIFICATION SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ "$ALL_VERIFIED" == "true" ]]; then
        echo "  ┌─────────────────────────────────────────────────────────────────┐"
        echo "  │                    ${GREEN}VERIFICATION SUCCESSFUL${NC}                      │"
        echo "  ├─────────────────────────────────────────────────────────────────┤"
        printf "  │  Cluster               : %-38s │\n" "$CLUSTER_NAME"
        printf "  │  Total Services        : %-38s │\n" "$TOTAL_COUNT"
        printf "  │  Verified Services     : %-38s │\n" "$VERIFIED_COUNT"
        printf "  │  Verification Result   : ${GREEN}%-38s${NC} │\n" "PASSED"
        echo "  └─────────────────────────────────────────────────────────────────┘"
        echo ""

        {
            echo "VERIFICATION_STATUS=success"
            echo "VERIFIED_COUNT=$VERIFIED_COUNT"
            echo "TOTAL_COUNT=$TOTAL_COUNT"
        } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

        echo -e "${GREEN}✅ All services verified successfully!${NC}"
    else
        echo "  ┌─────────────────────────────────────────────────────────────────┐"
        echo "  │                    ${RED}VERIFICATION FAILED${NC}                         │"
        echo "  ├─────────────────────────────────────────────────────────────────┤"
        printf "  │  Cluster               : %-38s │\n" "$CLUSTER_NAME"
        printf "  │  Total Services        : %-38s │\n" "$TOTAL_COUNT"
        printf "  │  Verified Services     : %-38s │\n" "$VERIFIED_COUNT"
        printf "  │  Failed Services       : %-38s │\n" "$((TOTAL_COUNT - VERIFIED_COUNT))"
        printf "  │  Verification Result   : ${RED}%-38s${NC} │\n" "FAILED"
        echo "  └─────────────────────────────────────────────────────────────────┘"
        echo ""

        if [[ -n "$FAILED_SERVICES" ]]; then
            echo "  Failed Services:"
            echo "$FAILED_SERVICES" | tr ',' '\n' | while read -r svc; do
                [[ -n "$svc" ]] && echo "    → $svc"
            done
            echo ""
        fi

        {
            echo "VERIFICATION_STATUS=failed"
            echo "VERIFIED_COUNT=$VERIFIED_COUNT"
            echo "TOTAL_COUNT=$TOTAL_COUNT"
            echo "FAILED_SERVICES=$FAILED_SERVICES"
        } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

        echo -e "${RED}❌ Verification failed! Some services not in expected state.${NC}"
    fi

    echo ""
}

# Show deployment status
show_deployments() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  RECENT DEPLOYMENTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    IFS=',' read -ra SERVICES <<< "$SERVICE_NAMES"
    for svc in "${SERVICES[@]}"; do
        svc=$(echo "$svc" | tr -d ' ')

        DEPLOYMENTS=$(aws ecs describe-services \
            --region "$AWS_REGION" \
            --cluster "$CLUSTER_NAME" \
            --services "$svc" \
            --query 'services[0].deployments[*].{Status: status, Running: runningCount, Desired: desiredCount, Pending: pendingCount, RolloutState: rolloutState}' \
            --output json 2>/dev/null) || continue

        echo "  Service: $svc"
        echo "$DEPLOYMENTS" | jq -r '.[] | "    [\(.Status)] Running: \(.Running)/\(.Desired), Pending: \(.Pending), Rollout: \(.RolloutState // "N/A")"'
        echo ""
    done
}

# Main
main() {
    verify_services
    generate_summary
    show_deployments

    if [[ "$ALL_VERIFIED" != "true" ]]; then
        exit 1
    fi
}

main "$@"
