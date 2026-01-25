#!/bin/bash
###############################################################################
# Script: create_snapshot.sh
# Purpose: Create RDS snapshots before lifecycle operations
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
AWS_REGION="${AWS_REGION:-us-east-1}"
SNAPSHOT_PREFIX="${SNAPSHOT_PREFIX:-harness-lifecycle}"
WAIT_FOR_SNAPSHOT="${WAIT_FOR_SNAPSHOT:-true}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    RDS SNAPSHOT CREATION SERVICE                         ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Generate timestamp for snapshot names
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Print configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SNAPSHOT CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Region            : $AWS_REGION"
echo "  Snapshot Prefix   : $SNAPSHOT_PREFIX"
echo "  Timestamp         : $TIMESTAMP"
echo "  Wait for Complete : $WAIT_FOR_SNAPSHOT"
echo ""
echo "  DB Instances      : ${DB_IDENTIFIERS:-None}"
echo "  Aurora Clusters   : ${CLUSTER_IDENTIFIERS:-None}"
echo ""

# Validate inputs
if [[ -z "$DB_IDENTIFIERS" && -z "$CLUSTER_IDENTIFIERS" ]]; then
    echo -e "${YELLOW}⚠️  No database identifiers provided. Skipping snapshot creation.${NC}"
    echo "SNAPSHOT_STATUS=skipped" >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true
    exit 0
fi

CREATED_SNAPSHOTS=""
FAILED_SNAPSHOTS=""

# Create DB instance snapshots
if [[ -n "$DB_IDENTIFIERS" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CREATING DB INSTANCE SNAPSHOTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    IFS=',' read -ra DB_ARRAY <<< "$DB_IDENTIFIERS"

    for db_id in "${DB_ARRAY[@]}"; do
        db_id=$(echo "$db_id" | tr -d ' ')
        snapshot_id="${SNAPSHOT_PREFIX}-${db_id}-${TIMESTAMP}"

        echo "📸 Creating snapshot for: $db_id"
        echo "   Snapshot ID: $snapshot_id"

        RESULT=$(aws rds create-db-snapshot \
            --region "$AWS_REGION" \
            --db-instance-identifier "$db_id" \
            --db-snapshot-identifier "$snapshot_id" \
            --output json 2>&1) || {
            echo -e "   ${RED}❌ Failed to create snapshot${NC}"
            echo "   Error: $RESULT"
            FAILED_SNAPSHOTS="$FAILED_SNAPSHOTS$snapshot_id,"
            continue
        }

        STATUS=$(echo "$RESULT" | jq -r '.DBSnapshot.Status')
        echo -e "   ${GREEN}✅ Snapshot initiated (Status: $STATUS)${NC}"
        CREATED_SNAPSHOTS="$CREATED_SNAPSHOTS$snapshot_id,"
        echo ""
    done
fi

# Create Aurora cluster snapshots
if [[ -n "$CLUSTER_IDENTIFIERS" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CREATING AURORA CLUSTER SNAPSHOTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    IFS=',' read -ra CLUSTER_ARRAY <<< "$CLUSTER_IDENTIFIERS"

    for cluster_id in "${CLUSTER_ARRAY[@]}"; do
        cluster_id=$(echo "$cluster_id" | tr -d ' ')
        snapshot_id="${SNAPSHOT_PREFIX}-${cluster_id}-${TIMESTAMP}"

        echo "📸 Creating snapshot for cluster: $cluster_id"
        echo "   Snapshot ID: $snapshot_id"

        RESULT=$(aws rds create-db-cluster-snapshot \
            --region "$AWS_REGION" \
            --db-cluster-identifier "$cluster_id" \
            --db-cluster-snapshot-identifier "$snapshot_id" \
            --output json 2>&1) || {
            echo -e "   ${RED}❌ Failed to create cluster snapshot${NC}"
            echo "   Error: $RESULT"
            FAILED_SNAPSHOTS="$FAILED_SNAPSHOTS$snapshot_id,"
            continue
        }

        STATUS=$(echo "$RESULT" | jq -r '.DBClusterSnapshot.Status')
        echo -e "   ${GREEN}✅ Cluster snapshot initiated (Status: $STATUS)${NC}"
        CREATED_SNAPSHOTS="$CREATED_SNAPSHOTS$snapshot_id,"
        echo ""
    done
fi

# Wait for snapshots to complete
if [[ "$WAIT_FOR_SNAPSHOT" == "true" && -n "$CREATED_SNAPSHOTS" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  WAITING FOR SNAPSHOTS TO COMPLETE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo -e "${YELLOW}⏳ This may take several minutes depending on database size...${NC}"
    echo ""

    # Wait for DB snapshots
    if [[ -n "$DB_IDENTIFIERS" ]]; then
        IFS=',' read -ra DB_ARRAY <<< "$DB_IDENTIFIERS"
        for db_id in "${DB_ARRAY[@]}"; do
            db_id=$(echo "$db_id" | tr -d ' ')
            snapshot_id="${SNAPSHOT_PREFIX}-${db_id}-${TIMESTAMP}"

            echo "   Waiting for snapshot: $snapshot_id"
            aws rds wait db-snapshot-available \
                --region "$AWS_REGION" \
                --db-snapshot-identifier "$snapshot_id" 2>/dev/null && {
                echo -e "   ${GREEN}✅ Snapshot available: $snapshot_id${NC}"
            } || {
                echo -e "   ${YELLOW}⚠️  Timeout waiting for snapshot (may still be in progress)${NC}"
            }
        done
    fi

    # Wait for cluster snapshots
    if [[ -n "$CLUSTER_IDENTIFIERS" ]]; then
        IFS=',' read -ra CLUSTER_ARRAY <<< "$CLUSTER_IDENTIFIERS"
        for cluster_id in "${CLUSTER_ARRAY[@]}"; do
            cluster_id=$(echo "$cluster_id" | tr -d ' ')
            snapshot_id="${SNAPSHOT_PREFIX}-${cluster_id}-${TIMESTAMP}"

            echo "   Waiting for cluster snapshot: $snapshot_id"
            aws rds wait db-cluster-snapshot-available \
                --region "$AWS_REGION" \
                --db-cluster-snapshot-identifier "$snapshot_id" 2>/dev/null && {
                echo -e "   ${GREEN}✅ Cluster snapshot available: $snapshot_id${NC}"
            } || {
                echo -e "   ${YELLOW}⚠️  Timeout waiting for cluster snapshot${NC}"
            }
        done
    fi
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SNAPSHOT SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Remove trailing commas
CREATED_SNAPSHOTS="${CREATED_SNAPSHOTS%,}"
FAILED_SNAPSHOTS="${FAILED_SNAPSHOTS%,}"

CREATED_COUNT=0
FAILED_COUNT=0

if [[ -n "$CREATED_SNAPSHOTS" ]]; then
    CREATED_COUNT=$(echo "$CREATED_SNAPSHOTS" | tr ',' '\n' | wc -l | tr -d ' ')
fi
if [[ -n "$FAILED_SNAPSHOTS" ]]; then
    FAILED_COUNT=$(echo "$FAILED_SNAPSHOTS" | tr ',' '\n' | wc -l | tr -d ' ')
fi

echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │                    SNAPSHOT RESULTS                             │"
echo "  ├─────────────────────────────────────────────────────────────────┤"
printf "  │  ${GREEN}✅ Created${NC}     : %-47s │\n" "$CREATED_COUNT snapshot(s)"
printf "  │  ${RED}❌ Failed${NC}      : %-47s │\n" "$FAILED_COUNT snapshot(s)"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""

if [[ -n "$CREATED_SNAPSHOTS" ]]; then
    echo "  Created Snapshots:"
    echo "$CREATED_SNAPSHOTS" | tr ',' '\n' | while read -r snap; do
        [[ -n "$snap" ]] && echo "    → $snap"
    done
    echo ""
fi

# Export results
{
    echo "SNAPSHOT_STATUS=success"
    echo "CREATED_SNAPSHOTS=$CREATED_SNAPSHOTS"
    echo "FAILED_SNAPSHOTS=$FAILED_SNAPSHOTS"
    echo "SNAPSHOT_TIMESTAMP=$TIMESTAMP"
} >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

if [[ -n "$FAILED_SNAPSHOTS" ]]; then
    echo -e "${YELLOW}⚠️  Some snapshots failed. Check details above.${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All snapshots created successfully!${NC}"
fi
echo ""
