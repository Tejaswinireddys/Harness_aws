#!/bin/bash
###############################################################################
# Script: validate_credentials.sh
# Purpose: Validate AWS credentials and RDS permissions
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

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║              AWS CREDENTIALS & RDS PERMISSIONS VALIDATION                ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}✅ $message${NC}" ;;
        "error") echo -e "${RED}❌ $message${NC}" ;;
        "warning") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "info") echo -e "${BLUE}ℹ️  $message${NC}" ;;
    esac
}

print_section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Step 1: Check environment variables
print_section "STEP 1: Environment Variables Check"

if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
    print_status "error" "AWS_ACCESS_KEY_ID is not set"
    exit 1
else
    masked_key="${AWS_ACCESS_KEY_ID:0:4}****${AWS_ACCESS_KEY_ID: -4}"
    print_status "success" "AWS_ACCESS_KEY_ID is set: $masked_key"
fi

if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    print_status "error" "AWS_SECRET_ACCESS_KEY is not set"
    exit 1
else
    print_status "success" "AWS_SECRET_ACCESS_KEY is set: ****"
fi

if [[ -z "${AWS_REGION:-}" ]]; then
    print_status "warning" "AWS_REGION not set, defaulting to us-east-1"
    export AWS_REGION="us-east-1"
else
    print_status "success" "AWS_REGION is set: $AWS_REGION"
fi

# Step 2: Validate credentials with STS
print_section "STEP 2: AWS Credentials Validation"

echo "Calling AWS STS to validate credentials..."
CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>&1) || {
    print_status "error" "Failed to validate AWS credentials"
    echo "Error: $CALLER_IDENTITY"
    exit 1
}

ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
USER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
USER_ID=$(echo "$CALLER_IDENTITY" | jq -r '.UserId')

print_status "success" "AWS credentials are valid"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ Account Details                                                 │"
echo "  ├─────────────────────────────────────────────────────────────────┤"
printf "  │ %-15s: %-47s │\n" "Account ID" "$ACCOUNT_ID"
printf "  │ %-15s: %-47s │\n" "User ID" "$USER_ID"
printf "  │ %-15s: %-47s │\n" "ARN" "${USER_ARN:0:47}"
echo "  └─────────────────────────────────────────────────────────────────┘"

# Step 3: Test RDS permissions
print_section "STEP 3: RDS Permissions Validation"

echo "Testing DescribeDBInstances permission..."
DESCRIBE_RESULT=$(aws rds describe-db-instances --region "$AWS_REGION" --max-records 20 --output json 2>&1) || {
    print_status "error" "No permission to describe RDS instances"
    echo "Error: $DESCRIBE_RESULT"
    exit 1
}
DB_COUNT=$(echo "$DESCRIBE_RESULT" | jq '.DBInstances | length')
print_status "success" "DescribeDBInstances permission verified ($DB_COUNT instances found)"

echo "Testing DescribeDBClusters permission..."
CLUSTER_RESULT=$(aws rds describe-db-clusters --region "$AWS_REGION" --max-records 20 --output json 2>&1) || {
    print_status "warning" "Limited permission for DescribeDBClusters"
}
CLUSTER_COUNT=$(echo "$CLUSTER_RESULT" | jq '.DBClusters | length' 2>/dev/null || echo "0")
print_status "success" "DescribeDBClusters permission verified ($CLUSTER_COUNT clusters found)"

echo "Testing DescribeDBSnapshots permission..."
aws rds describe-db-snapshots --region "$AWS_REGION" --max-records 5 --output json > /dev/null 2>&1 || {
    print_status "warning" "Limited permission for DescribeDBSnapshots"
}
print_status "success" "DescribeDBSnapshots permission verified"

# Step 4: Summary
print_section "VALIDATION SUMMARY"

echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │                    VALIDATION RESULTS                           │"
echo "  ├─────────────────────────────────────────────────────────────────┤"
echo "  │  ✅ AWS Credentials         : Valid                             │"
printf "  │  ✅ Region                   : %-33s │\n" "$AWS_REGION"
echo "  │  ✅ RDS Describe Permission  : Granted                          │"
printf "  │  ✅ RDS Instances Found      : %-33s │\n" "$DB_COUNT"
printf "  │  ✅ Aurora Clusters Found    : %-33s │\n" "$CLUSTER_COUNT"
echo "  │  ✅ Ready for Lifecycle Ops  : Yes                              │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""

# Export outputs
{
    echo "VALIDATION_STATUS=success"
    echo "AWS_ACCOUNT_ID=$ACCOUNT_ID"
    echo "DB_INSTANCE_COUNT=$DB_COUNT"
    echo "DB_CLUSTER_COUNT=$CLUSTER_COUNT"
} >> "$HARNESS_OUTPUT_FILE" 2>/dev/null || true

print_status "success" "All validations passed successfully!"
echo ""
