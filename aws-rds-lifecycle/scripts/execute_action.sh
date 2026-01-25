#!/bin/bash
###############################################################################
# Script: execute_action.sh
# Purpose: Execute start/stop actions on RDS instances and Aurora clusters
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
DB_IDENTIFIERS="${DB_IDENTIFIERS:-}"
CLUSTER_IDENTIFIERS="${CLUSTER_IDENTIFIERS:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DRY_RUN="${DRY_RUN:-false}"
WAIT_FOR_STATE="${WAIT_FOR_STATE:-true}"
MAX_WAIT_TIME="${MAX_WAIT_TIME:-900}"

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║                    RDS LIFECYCLE ACTION EXECUTOR                         ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Validate inputs
validate_inputs() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  INPUT VALIDATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ -z "$ACTION" ]]; then
        echo -e "${RED}❌ ERROR: ACTION is required (start/stop)${NC}"
        exit 1
    fi

    if [[ "$ACTION" != "start" && "$ACTION" != "stop" ]]; then
        echo -e "${RED}❌ ERROR: ACTION must be 'start' or 'stop'. Got: $ACTION${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Action validated: $ACTION${NC}"

    if [[ -z "$DB_IDENTIFIERS" && -z "$CLUSTER_IDENTIFIERS" ]]; then
        echo -e "${RED}❌ ERROR: DB_IDENTIFIERS or CLUSTER_IDENTIFIERS required${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Database identifiers provided${NC}"

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
        echo "  │  Action          : ${GREEN}START DATABASES${NC}                          │"
    else
        echo "  │  Action          : ${RED}STOP DATABASES${NC}                           │"
    fi

    printf "  │  Region          : %-44s │\n" "$AWS_REGION"
    printf "  │  Dry Run         : %-44s │\n" "$DRY_RUN"
    printf "  │  Wait for State  : %-44s │\n" "$WAIT_FOR_STATE"
    printf "  │  Max Wait Time   : %-44s │\n" "${MAX_WAIT_TIME}s"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""

    if [[ -n "$DB_IDENTIFIERS" ]]; then
        echo "  Target DB Instances:"
        IFS=',' read -ra DBS <<< "$DB_IDENTIFIERS"
        for db in "${DBS[@]}"; do
            echo "    → $(echo "$db" | tr -d ' ')"
        done
        echo ""
    fi

    if [[ -n "$CLUSTER_IDENTIFIERS" ]]; then
        echo "  Target Aurora Clusters:"
        IFS=',' read -ra CLUSTERS <<< "$CLUSTER_IDENTIFIERS"
        for cluster in "${CLUSTERS[@]}"; do
            echo "    → $(echo "$cluster" | tr -d ' ')"
        done
        echo ""
    fi
}

# Pre-flight check
preflight_check() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  PRE-FLIGHT CHECK"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Fetching current database states..."
    echo ""

    # Check DB instances
    if [[ -n "$DB_IDENTIFIERS" ]]; then
        echo "┌──────────────────────────┬─────────────┬──────────────────┬────────────────┐"
        echo "│ DB Identifier            │ Status      │ Engine           │ Action         │"
        echo "├──────────────────────────┼─────────────┼──────────────────┼────────────────┤"

        IFS=',' read -ra DBS <<< "$DB_IDENTIFIERS"
        for db_id in "${DBS[@]}"; do
            db_id=$(echo "$db_id" | tr -d ' ')

            DB_INFO=$(aws rds describe-db-instances \
                --region "$AWS_REGION" \
                --db-instance-identifier "$db_id" \
                --query 'DBInstances[0].{Status: DBInstanceStatus, Engine: Engine, ReadReplica: ReadReplicaSourceDBInstanceIdentifier}' \
                --output json 2>/dev/null) || {
                printf "│ %-24s │ ${RED}%-11s${NC} │ %-16s │ ${RED}%-14s${NC} │\n" "$db_id" "NOT FOUND" "N/A" "ERROR"
                continue
            }

            status=$(echo "$DB_INFO" | jq -r '.Status')
            engine=$(echo "$DB_INFO" | jq -r '.Engine')
            read_replica=$(echo "$DB_INFO" | jq -r '.ReadReplica')

            # Check if read replica
            if [[ "$read_replica" != "null" && "$ACTION" == "stop" ]]; then
                printf "│ %-24s │ %-11s │ %-16s │ ${YELLOW}%-14s${NC} │\n" "${db_id:0:24}" "$status" "${engine:0:16}" "SKIP (REPLICA)"
                continue
            fi

            # Determine action needed
            if [[ "$ACTION" == "start" && "$status" == "available" ]]; then
                printf "│ %-24s │ ${GREEN}%-11s${NC} │ %-16s │ ${YELLOW}%-14s${NC} │\n" "${db_id:0:24}" "$status" "${engine:0:16}" "SKIP (RUNNING)"
            elif [[ "$ACTION" == "stop" && "$status" == "stopped" ]]; then
                printf "│ %-24s │ ${RED}%-11s${NC} │ %-16s │ ${YELLOW}%-14s${NC} │\n" "${db_id:0:24}" "$status" "${engine:0:16}" "SKIP (STOPPED)"
            else
                printf "│ %-24s │ %-11s │ %-16s │ ${GREEN}%-14s${NC} │\n" "${db_id:0:24}" "$status" "${engine:0:16}" "EXECUTE"
            fi
        done

        echo "└──────────────────────────┴─────────────┴──────────────────┴────────────────┘"
        echo ""
    fi

    # Check Aurora clusters
    if [[ -n "$CLUSTER_IDENTIFIERS" ]]; then
        echo "Aurora Clusters:"
        echo "┌──────────────────────────┬─────────────┬──────────────────┬────────────────┐"
        echo "│ Cluster Identifier       │ Status      │ Engine           │ Action         │"
        echo "├──────────────────────────┼─────────────┼──────────────────┼────────────────┤"

        IFS=',' read -ra CLUSTERS <<< "$CLUSTER_IDENTIFIERS"
        for cluster_id in "${CLUSTERS[@]}"; do
            cluster_id=$(echo "$cluster_id" | tr -d ' ')

            CLUSTER_INFO=$(aws rds describe-db-clusters \
                --region "$AWS_REGION" \
                --db-cluster-identifier "$cluster_id" \
                --query 'DBClusters[0].{Status: Status, Engine: Engine}' \
                --output json 2>/dev/null) || {
                printf "│ %-24s │ ${RED}%-11s${NC} │ %-16s │ ${RED}%-14s${NC} │\n" "$cluster_id" "NOT FOUND" "N/A" "ERROR"
                continue
            }

            status=$(echo "$CLUSTER_INFO" | jq -r '.Status')
            engine=$(echo "$CLUSTER_INFO" | jq -r '.Engine')

            if [[ "$ACTION" == "start" && "$status" == "available" ]]; then
                printf "│ %-24s │ ${GREEN}%-11s${NC} │ %-16s │ ${YELLOW}%-14s${NC} │\n" "${cluster_id:0:24}" "$status" "${engine:0:16}" "SKIP (RUNNING)"
            elif [[ "$ACTION" == "stop" && "$status" == "stopped" ]]; then
                printf "│ %-24s │ ${RED}%-11s${NC} │ %-16s │ ${YELLOW}%-14s${NC} │\n" "${cluster_id:0:24}" "$status" "${engine:0:16}" "SKIP (STOPPED)"
            else
                printf "│ %-24s │ %-11s │ %-16s │ ${GREEN}%-14s${NC} │\n" "${cluster_id:0:24}" "$status" "${engine:0:16}" "EXECUTE"
            fi
        done

        echo "└──────────────────────────┴─────────────┴──────────────────┴────────────────┘"
        echo ""
    fi
}

# Execute action
execute_action() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  EXECUTING ACTION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
        echo ""
        if [[ -n "$DB_IDENTIFIERS" ]]; then
            echo "Would execute for DB instances: $DB_IDENTIFIERS"
        fi
        if [[ -n "$CLUSTER_IDENTIFIERS" ]]; then
            echo "Would execute for clusters: $CLUSTER_IDENTIFIERS"
        fi
        echo ""
        echo "ACTION_RESULT=dry_run_success" >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true
        return 0
    fi

    SUCCESS_COUNT=0
    FAILED_COUNT=0
    EXECUTED_DBS=""
    EXECUTED_CLUSTERS=""

    # Execute on DB instances
    if [[ -n "$DB_IDENTIFIERS" ]]; then
        echo "Processing DB Instances..."
        echo ""

        IFS=',' read -ra DBS <<< "$DB_IDENTIFIERS"
        for db_id in "${DBS[@]}"; do
            db_id=$(echo "$db_id" | tr -d ' ')

            if [[ "$ACTION" == "start" ]]; then
                echo -e "  🚀 Starting: $db_id"
                RESULT=$(aws rds start-db-instance \
                    --region "$AWS_REGION" \
                    --db-instance-identifier "$db_id" \
                    --output json 2>&1) || {
                    echo -e "     ${RED}❌ Failed: $RESULT${NC}"
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    continue
                }
            else
                echo -e "  ⏹️  Stopping: $db_id"
                RESULT=$(aws rds stop-db-instance \
                    --region "$AWS_REGION" \
                    --db-instance-identifier "$db_id" \
                    --output json 2>&1) || {
                    echo -e "     ${RED}❌ Failed: $RESULT${NC}"
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    continue
                }
            fi

            NEW_STATUS=$(echo "$RESULT" | jq -r '.DBInstance.DBInstanceStatus')
            echo -e "     ${GREEN}✅ Success (Status: $NEW_STATUS)${NC}"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            EXECUTED_DBS="$EXECUTED_DBS$db_id,"
        done
        echo ""
    fi

    # Execute on Aurora clusters
    if [[ -n "$CLUSTER_IDENTIFIERS" ]]; then
        echo "Processing Aurora Clusters..."
        echo ""

        IFS=',' read -ra CLUSTERS <<< "$CLUSTER_IDENTIFIERS"
        for cluster_id in "${CLUSTERS[@]}"; do
            cluster_id=$(echo "$cluster_id" | tr -d ' ')

            if [[ "$ACTION" == "start" ]]; then
                echo -e "  🚀 Starting cluster: $cluster_id"
                RESULT=$(aws rds start-db-cluster \
                    --region "$AWS_REGION" \
                    --db-cluster-identifier "$cluster_id" \
                    --output json 2>&1) || {
                    echo -e "     ${RED}❌ Failed: $RESULT${NC}"
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    continue
                }
            else
                echo -e "  ⏹️  Stopping cluster: $cluster_id"
                RESULT=$(aws rds stop-db-cluster \
                    --region "$AWS_REGION" \
                    --db-cluster-identifier "$cluster_id" \
                    --output json 2>&1) || {
                    echo -e "     ${RED}❌ Failed: $RESULT${NC}"
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    continue
                }
            fi

            NEW_STATUS=$(echo "$RESULT" | jq -r '.DBCluster.Status')
            echo -e "     ${GREEN}✅ Success (Status: $NEW_STATUS)${NC}"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            EXECUTED_CLUSTERS="$EXECUTED_CLUSTERS$cluster_id,"
        done
        echo ""
    fi

    echo "Action Results: $SUCCESS_COUNT succeeded, $FAILED_COUNT failed"
    echo ""

    # Export results
    {
        echo "ACTION_RESULT=success"
        echo "SUCCESS_COUNT=$SUCCESS_COUNT"
        echo "FAILED_COUNT=$FAILED_COUNT"
        echo "EXECUTED_DBS=${EXECUTED_DBS%,}"
        echo "EXECUTED_CLUSTERS=${EXECUTED_CLUSTERS%,}"
    } >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

    if [[ $FAILED_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Some operations failed${NC}"
    fi
}

# Wait for state
wait_for_state() {
    if [[ "$WAIT_FOR_STATE" != "true" || "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}⏭️  Skipping state wait${NC}"
        return 0
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  WAITING FOR TARGET STATE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    TARGET_STATE=""
    if [[ "$ACTION" == "start" ]]; then
        TARGET_STATE="available"
        echo -e "Waiting for databases to reach ${GREEN}available${NC} state..."
    else
        TARGET_STATE="stopped"
        echo -e "Waiting for databases to reach ${RED}stopped${NC} state..."
    fi
    echo ""
    echo -e "${YELLOW}⏳ This may take several minutes...${NC}"
    echo ""

    # Wait for DB instances
    if [[ -n "$DB_IDENTIFIERS" ]]; then
        IFS=',' read -ra DBS <<< "$DB_IDENTIFIERS"
        for db_id in "${DBS[@]}"; do
            db_id=$(echo "$db_id" | tr -d ' ')
            echo "   Waiting for $db_id..."

            if [[ "$ACTION" == "start" ]]; then
                aws rds wait db-instance-available \
                    --region "$AWS_REGION" \
                    --db-instance-identifier "$db_id" 2>/dev/null && {
                    echo -e "   ${GREEN}✅ $db_id is now available${NC}"
                } || {
                    echo -e "   ${YELLOW}⚠️  Timeout waiting for $db_id${NC}"
                }
            else
                aws rds wait db-instance-stopped \
                    --region "$AWS_REGION" \
                    --db-instance-identifier "$db_id" 2>/dev/null && {
                    echo -e "   ${GREEN}✅ $db_id is now stopped${NC}"
                } || {
                    echo -e "   ${YELLOW}⚠️  Timeout waiting for $db_id${NC}"
                }
            fi
        done
    fi

    # Note: Aurora clusters don't have built-in wait commands
    if [[ -n "$CLUSTER_IDENTIFIERS" ]]; then
        echo ""
        echo -e "${YELLOW}Note: Aurora clusters are being processed. Check status manually.${NC}"
    fi

    echo ""
}

# Main
main() {
    validate_inputs
    display_config
    preflight_check
    execute_action
    wait_for_state

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ACTION COMPLETE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${GREEN}✅ RDS lifecycle action completed!${NC}"

    if [[ "$ACTION" == "stop" ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  REMINDER: Stopped RDS instances will auto-start after 7 days${NC}"
    fi
    echo ""
}

main "$@"
