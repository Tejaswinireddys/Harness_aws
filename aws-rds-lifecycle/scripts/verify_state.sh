#!/bin/bash
###############################################################################
# Script: verify_state.sh
# Purpose: Verify RDS instances are in expected state after action
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
DB_IDENTIFIERS="${DB_IDENTIFIERS:-}"
CLUSTER_IDENTIFIERS="${CLUSTER_IDENTIFIERS:-}"
EXPECTED_STATE="${EXPECTED_STATE:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_INTERVAL="${RETRY_INTERVAL:-30}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    RDS STATE VERIFICATION SERVICE                        ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Print configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VERIFICATION CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Expected State  : $EXPECTED_STATE"
echo "  Region          : $AWS_REGION"
echo "  Retry Count     : $RETRY_COUNT"
echo "  Retry Interval  : ${RETRY_INTERVAL}s"
echo ""
echo "  DB Instances    : ${DB_IDENTIFIERS:-None}"
echo "  Aurora Clusters : ${CLUSTER_IDENTIFIERS:-None}"
echo ""

# Validate inputs
if [[ -z "$DB_IDENTIFIERS" && -z "$CLUSTER_IDENTIFIERS" ]]; then
    echo -e "${YELLOW}⚠️  No database identifiers provided. Nothing to verify.${NC}"
    echo "VERIFICATION_STATUS=skipped" >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true
    exit 0
fi

if [[ -z "$EXPECTED_STATE" ]]; then
    echo -e "${RED}❌ ERROR: EXPECTED_STATE is required${NC}"
    exit 1
fi

# Verification function
verify_databases() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  VERIFYING DATABASE STATES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    ATTEMPT=1
    ALL_VERIFIED=false
    VERIFIED_COUNT=0
    TOTAL_COUNT=0
    FAILED_DBS=""

    while [[ $ATTEMPT -le $RETRY_COUNT ]]; do
        echo "Verification Attempt $ATTEMPT of $RETRY_COUNT..."
        echo ""

        VERIFIED_COUNT=0
        TOTAL_COUNT=0
        FAILED_DBS=""

        # Verify DB instances
        if [[ -n "$DB_IDENTIFIERS" ]]; then
            echo "DB Instances:"
            echo "┌──────────────────────────┬─────────────┬──────────────────┬────────────────┐"
            echo "│ DB Identifier            │ Status      │ Engine           │ Verification   │"
            echo "├──────────────────────────┼─────────────┼──────────────────┼────────────────┤"

            IFS=',' read -ra DBS <<< "$DB_IDENTIFIERS"
            for db_id in "${DBS[@]}"; do
                db_id=$(echo "$db_id" | tr -d ' ')
                TOTAL_COUNT=$((TOTAL_COUNT + 1))

                DB_INFO=$(aws rds describe-db-instances \
                    --region "$AWS_REGION" \
                    --db-instance-identifier "$db_id" \
                    --query 'DBInstances[0].{Status: DBInstanceStatus, Engine: Engine}' \
                    --output json 2>/dev/null) || {
                    printf "│ %-24s │ ${RED}%-11s${NC} │ %-16s │ ${RED}%-14s${NC} │\n" "${db_id:0:24}" "ERROR" "N/A" "NOT FOUND"
                    FAILED_DBS="$FAILED_DBS$db_id,"
                    continue
                }

                status=$(echo "$DB_INFO" | jq -r '.Status')
                engine=$(echo "$DB_INFO" | jq -r '.Engine')

                if [[ "$status" == "$EXPECTED_STATE" ]]; then
                    VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
                    printf "│ %-24s │ ${GREEN}%-11s${NC} │ %-16s │ ${GREEN}%-14s${NC} │\n" "${db_id:0:24}" "$status" "${engine:0:16}" "✅ VERIFIED"
                else
                    FAILED_DBS="$FAILED_DBS$db_id,"
                    printf "│ %-24s │ ${YELLOW}%-11s${NC} │ %-16s │ ${RED}%-14s${NC} │\n" "${db_id:0:24}" "$status" "${engine:0:16}" "❌ MISMATCH"
                fi
            done

            echo "└──────────────────────────┴─────────────┴──────────────────┴────────────────┘"
            echo ""
        fi

        # Verify Aurora clusters
        if [[ -n "$CLUSTER_IDENTIFIERS" ]]; then
            echo "Aurora Clusters:"
            echo "┌──────────────────────────┬─────────────┬──────────────────┬────────────────┐"
            echo "│ Cluster Identifier       │ Status      │ Engine           │ Verification   │"
            echo "├──────────────────────────┼─────────────┼──────────────────┼────────────────┤"

            IFS=',' read -ra CLUSTERS <<< "$CLUSTER_IDENTIFIERS"
            for cluster_id in "${CLUSTERS[@]}"; do
                cluster_id=$(echo "$cluster_id" | tr -d ' ')
                TOTAL_COUNT=$((TOTAL_COUNT + 1))

                CLUSTER_INFO=$(aws rds describe-db-clusters \
                    --region "$AWS_REGION" \
                    --db-cluster-identifier "$cluster_id" \
                    --query 'DBClusters[0].{Status: Status, Engine: Engine}' \
                    --output json 2>/dev/null) || {
                    printf "│ %-24s │ ${RED}%-11s${NC} │ %-16s │ ${RED}%-14s${NC} │\n" "${cluster_id:0:24}" "ERROR" "N/A" "NOT FOUND"
                    FAILED_DBS="$FAILED_DBS$cluster_id,"
                    continue
                }

                status=$(echo "$CLUSTER_INFO" | jq -r '.Status')
                engine=$(echo "$CLUSTER_INFO" | jq -r '.Engine')

                if [[ "$status" == "$EXPECTED_STATE" ]]; then
                    VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
                    printf "│ %-24s │ ${GREEN}%-11s${NC} │ %-16s │ ${GREEN}%-14s${NC} │\n" "${cluster_id:0:24}" "$status" "${engine:0:16}" "✅ VERIFIED"
                else
                    FAILED_DBS="$FAILED_DBS$cluster_id,"
                    printf "│ %-24s │ ${YELLOW}%-11s${NC} │ %-16s │ ${RED}%-14s${NC} │\n" "${cluster_id:0:24}" "$status" "${engine:0:16}" "❌ MISMATCH"
                fi
            done

            echo "└──────────────────────────┴─────────────┴──────────────────┴────────────────┘"
            echo ""
        fi

        # Check if all verified
        if [[ $VERIFIED_COUNT -eq $TOTAL_COUNT ]]; then
            ALL_VERIFIED=true
            break
        fi

        if [[ $ATTEMPT -lt $RETRY_COUNT ]]; then
            echo -e "${YELLOW}⏳ Not all databases verified. Retrying in ${RETRY_INTERVAL}s...${NC}"
            echo ""
            sleep $RETRY_INTERVAL
        fi

        ATTEMPT=$((ATTEMPT + 1))
    done

    # Remove trailing comma
    FAILED_DBS="${FAILED_DBS%,}"

    return 0
}

# Generate detailed report
generate_report() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  VERIFICATION SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ "$ALL_VERIFIED" == "true" ]]; then
        echo "  ┌─────────────────────────────────────────────────────────────────┐"
        echo "  │                    ${GREEN}VERIFICATION SUCCESSFUL${NC}                      │"
        echo "  ├─────────────────────────────────────────────────────────────────┤"
        printf "  │  Total Databases       : %-38s │\n" "$TOTAL_COUNT"
        printf "  │  Verified Databases    : %-38s │\n" "$VERIFIED_COUNT"
        printf "  │  Expected State        : %-38s │\n" "$EXPECTED_STATE"
        printf "  │  Verification Result   : ${GREEN}%-38s${NC} │\n" "PASSED"
        echo "  └─────────────────────────────────────────────────────────────────┘"
        echo ""

        {
            echo "VERIFICATION_STATUS=success"
            echo "VERIFIED_COUNT=$VERIFIED_COUNT"
            echo "TOTAL_COUNT=$TOTAL_COUNT"
        } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

        echo -e "${GREEN}✅ All databases verified in expected state: $EXPECTED_STATE${NC}"
    else
        echo "  ┌─────────────────────────────────────────────────────────────────┐"
        echo "  │                    ${RED}VERIFICATION FAILED${NC}                         │"
        echo "  ├─────────────────────────────────────────────────────────────────┤"
        printf "  │  Total Databases       : %-38s │\n" "$TOTAL_COUNT"
        printf "  │  Verified Databases    : %-38s │\n" "$VERIFIED_COUNT"
        printf "  │  Failed Databases      : %-38s │\n" "$((TOTAL_COUNT - VERIFIED_COUNT))"
        printf "  │  Expected State        : %-38s │\n" "$EXPECTED_STATE"
        printf "  │  Verification Result   : ${RED}%-38s${NC} │\n" "FAILED"
        echo "  └─────────────────────────────────────────────────────────────────┘"
        echo ""

        if [[ -n "$FAILED_DBS" ]]; then
            echo "  Failed Databases:"
            echo "$FAILED_DBS" | tr ',' '\n' | while read -r db; do
                [[ -n "$db" ]] && echo "    → $db"
            done
            echo ""
        fi

        {
            echo "VERIFICATION_STATUS=failed"
            echo "VERIFIED_COUNT=$VERIFIED_COUNT"
            echo "TOTAL_COUNT=$TOTAL_COUNT"
            echo "FAILED_DATABASES=$FAILED_DBS"
        } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

        echo -e "${RED}❌ Verification failed! Some databases not in expected state.${NC}"
    fi

    echo ""

    # Show 7-day reminder for stopped instances
    if [[ "$EXPECTED_STATE" == "stopped" ]]; then
        echo "  ┌─────────────────────────────────────────────────────────────────┐"
        echo "  │  ${YELLOW}⚠️  REMINDER: RDS INSTANCES AUTO-START AFTER 7 DAYS${NC}            │"
        echo "  │                                                                 │"
        echo "  │  Stopped RDS instances will automatically start after 7 days.  │"
        echo "  │  Plan accordingly or implement scheduled stop operations.      │"
        echo "  └─────────────────────────────────────────────────────────────────┘"
        echo ""
    fi
}

# Main
main() {
    verify_databases
    generate_report

    if [[ "$ALL_VERIFIED" != "true" ]]; then
        exit 1
    fi
}

main "$@"
