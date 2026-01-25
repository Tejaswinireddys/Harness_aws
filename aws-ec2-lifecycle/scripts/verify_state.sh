#!/bin/bash
###############################################################################
# Script: verify_state.sh
# Purpose: Verify EC2 instances are in expected state after action
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
INSTANCE_IDS="${INSTANCE_IDS:-}"
EXPECTED_STATE="${EXPECTED_STATE:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_INTERVAL="${RETRY_INTERVAL:-10}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    EC2 STATE VERIFICATION SERVICE                        ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Validate inputs
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VERIFICATION CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Instance IDs    : $INSTANCE_IDS"
echo "  Expected State  : $EXPECTED_STATE"
echo "  Region          : $AWS_REGION"
echo "  Retry Count     : $RETRY_COUNT"
echo "  Retry Interval  : ${RETRY_INTERVAL}s"
echo ""

if [[ -z "$INSTANCE_IDS" ]]; then
    echo -e "${RED}❌ ERROR: INSTANCE_IDS is required${NC}"
    exit 1
fi

if [[ -z "$EXPECTED_STATE" ]]; then
    echo -e "${RED}❌ ERROR: EXPECTED_STATE is required${NC}"
    exit 1
fi

# Verification function
verify_instances() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  VERIFYING INSTANCE STATES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    INSTANCE_LIST=$(echo "$INSTANCE_IDS" | tr ',' ' ')
    ATTEMPT=1
    ALL_VERIFIED=false

    while [[ $ATTEMPT -le $RETRY_COUNT ]]; do
        echo "Verification Attempt $ATTEMPT of $RETRY_COUNT..."
        echo ""

        STATES=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids $INSTANCE_LIST \
            --query 'Reservations[].Instances[].{InstanceId: InstanceId, State: State.Name, Name: Tags[?Key==`Name`].Value | [0], PrivateIp: PrivateIpAddress}' \
            --output json 2>&1) || {
            echo -e "${RED}❌ ERROR: Failed to fetch instance states${NC}"
            echo "$STATES"
            exit 1
        }

        echo "┌────────────────────┬─────────────┬────────────────┬────────────────────────────┐"
        echo "│ Instance ID        │ State       │ Private IP     │ Status                     │"
        echo "├────────────────────┼─────────────┼────────────────┼────────────────────────────┤"

        VERIFIED_COUNT=0
        TOTAL_COUNT=0
        FAILED_IDS=""

        while IFS=$'\t' read -r id state ip name; do
            TOTAL_COUNT=$((TOTAL_COUNT + 1))

            if [[ "$state" == "$EXPECTED_STATE" ]]; then
                VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
                status="${GREEN}✅ VERIFIED${NC}"
            else
                FAILED_IDS="$FAILED_IDS$id,"
                status="${RED}❌ MISMATCH (got: $state)${NC}"
            fi

            printf "│ %-18s │ %-11s │ %-14s │ %-26s │\n" "$id" "$state" "${ip:-N/A}" "$status"
        done < <(echo "$STATES" | jq -r '.[] | [.InstanceId, .State, .PrivateIp // "N/A", .Name // "Unnamed"] | @tsv')

        echo "└────────────────────┴─────────────┴────────────────┴────────────────────────────┘"
        echo ""

        if [[ $VERIFIED_COUNT -eq $TOTAL_COUNT ]]; then
            ALL_VERIFIED=true
            break
        fi

        if [[ $ATTEMPT -lt $RETRY_COUNT ]]; then
            echo -e "${YELLOW}⏳ Not all instances verified. Retrying in ${RETRY_INTERVAL}s...${NC}"
            sleep $RETRY_INTERVAL
        fi

        ATTEMPT=$((ATTEMPT + 1))
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  VERIFICATION SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ "$ALL_VERIFIED" == "true" ]]; then
        echo "  ┌─────────────────────────────────────────────────────────────────┐"
        echo "  │                    ${GREEN}VERIFICATION SUCCESSFUL${NC}                      │"
        echo "  ├─────────────────────────────────────────────────────────────────┤"
        printf "  │  Total Instances     : %-40s │\n" "$TOTAL_COUNT"
        printf "  │  Verified Instances  : %-40s │\n" "$VERIFIED_COUNT"
        printf "  │  Expected State      : %-40s │\n" "$EXPECTED_STATE"
        printf "  │  Verification Result : ${GREEN}%-40s${NC} │\n" "PASSED"
        echo "  └─────────────────────────────────────────────────────────────────┘"
        echo ""

        # Export success
        {
            echo "VERIFICATION_STATUS=success"
            echo "VERIFIED_COUNT=$VERIFIED_COUNT"
            echo "TOTAL_COUNT=$TOTAL_COUNT"
        } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

        echo -e "${GREEN}✅ All instances verified in expected state: $EXPECTED_STATE${NC}"
        return 0
    else
        echo "  ┌─────────────────────────────────────────────────────────────────┐"
        echo "  │                    ${RED}VERIFICATION FAILED${NC}                         │"
        echo "  ├─────────────────────────────────────────────────────────────────┤"
        printf "  │  Total Instances     : %-40s │\n" "$TOTAL_COUNT"
        printf "  │  Verified Instances  : %-40s │\n" "$VERIFIED_COUNT"
        printf "  │  Failed Instances    : %-40s │\n" "$((TOTAL_COUNT - VERIFIED_COUNT))"
        printf "  │  Expected State      : %-40s │\n" "$EXPECTED_STATE"
        printf "  │  Verification Result : ${RED}%-40s${NC} │\n" "FAILED"
        echo "  └─────────────────────────────────────────────────────────────────┘"
        echo ""

        # Export failure
        {
            echo "VERIFICATION_STATUS=failed"
            echo "VERIFIED_COUNT=$VERIFIED_COUNT"
            echo "TOTAL_COUNT=$TOTAL_COUNT"
            echo "FAILED_INSTANCES=${FAILED_IDS%,}"
        } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

        echo -e "${RED}❌ Verification failed! Some instances are not in expected state.${NC}"
        return 1
    fi
}

# Generate detailed report
generate_detailed_report() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  DETAILED INSTANCE REPORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    INSTANCE_LIST=$(echo "$INSTANCE_IDS" | tr ',' ' ')

    DETAILS=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids $INSTANCE_LIST \
        --query 'Reservations[].Instances[]' \
        --output json 2>/dev/null)

    echo "$DETAILS" | jq -r '.[] | "
  Instance: \(.InstanceId)
  ├── Name          : \(.Tags // [] | map(select(.Key == \"Name\")) | .[0].Value // \"Unnamed\")
  ├── State         : \(.State.Name)
  ├── Type          : \(.InstanceType)
  ├── Private IP    : \(.PrivateIpAddress // \"N/A\")
  ├── Public IP     : \(.PublicIpAddress // \"N/A\")
  ├── AZ            : \(.Placement.AvailabilityZone)
  ├── VPC           : \(.VpcId)
  ├── Subnet        : \(.SubnetId)
  └── Launch Time   : \(.LaunchTime)
"'

}

# Main execution
main() {
    verify_instances
    VERIFY_RESULT=$?

    generate_detailed_report

    exit $VERIFY_RESULT
}

main "$@"
