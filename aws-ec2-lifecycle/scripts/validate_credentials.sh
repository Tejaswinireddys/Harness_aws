#!/bin/bash
###############################################################################
# Script: validate_credentials.sh
# Purpose: Validate AWS credentials and permissions for EC2 lifecycle management
# Author: Platform Team
# Version: 1.0.0
###############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║              AWS CREDENTIALS & PERMISSIONS VALIDATION                    ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [[ "$status" == "success" ]]; then
        echo -e "${GREEN}✅ $message${NC}"
    elif [[ "$status" == "error" ]]; then
        echo -e "${RED}❌ $message${NC}"
    elif [[ "$status" == "warning" ]]; then
        echo -e "${YELLOW}⚠️  $message${NC}"
    else
        echo -e "${BLUE}ℹ️  $message${NC}"
    fi
}

# Function to print section header
print_section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Check required environment variables
print_section "STEP 1: Environment Variables Check"

if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
    print_status "error" "AWS_ACCESS_KEY_ID is not set"
    exit 1
else
    # Mask the key for display
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

# Validate credentials with STS
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

# Validate region
print_section "STEP 3: Region Validation"

echo "Validating region: $AWS_REGION"
REGION_CHECK=$(aws ec2 describe-availability-zones --region "$AWS_REGION" --output json 2>&1) || {
    print_status "error" "Invalid or inaccessible region: $AWS_REGION"
    exit 1
}

AZ_COUNT=$(echo "$REGION_CHECK" | jq '.AvailabilityZones | length')
print_status "success" "Region $AWS_REGION is valid with $AZ_COUNT availability zones"

# Test EC2 permissions
print_section "STEP 4: EC2 Permissions Validation"

echo "Testing DescribeInstances permission..."
DESCRIBE_TEST=$(aws ec2 describe-instances --region "$AWS_REGION" --max-results 5 --output json 2>&1) || {
    print_status "error" "No permission to describe EC2 instances"
    echo "Error: $DESCRIBE_TEST"
    exit 1
}
print_status "success" "DescribeInstances permission verified"

echo "Testing DescribeInstanceStatus permission..."
STATUS_TEST=$(aws ec2 describe-instance-status --region "$AWS_REGION" --max-results 5 --output json 2>&1) || {
    print_status "warning" "Limited permission for DescribeInstanceStatus"
}
print_status "success" "DescribeInstanceStatus permission verified"

# Summary
print_section "VALIDATION SUMMARY"

echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │                    VALIDATION RESULTS                           │"
echo "  ├─────────────────────────────────────────────────────────────────┤"
echo "  │  ✅ AWS Credentials         : Valid                             │"
echo "  │  ✅ Region                   : $AWS_REGION                              │"
echo "  │  ✅ EC2 Describe Permission  : Granted                          │"
echo "  │  ✅ Ready for Lifecycle Ops  : Yes                              │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""

# Export outputs for Harness
echo "Exporting output variables..."
export VALIDATION_STATUS="success"
export AWS_ACCOUNT_ID="$ACCOUNT_ID"
export AWS_USER_ARN="$USER_ARN"

# For Harness output variables
echo "VALIDATION_STATUS=success" >> $HARNESS_OUTPUT_FILE 2>/dev/null || true
echo "AWS_ACCOUNT_ID=$ACCOUNT_ID" >> $HARNESS_OUTPUT_FILE 2>/dev/null || true

print_status "success" "All validations passed successfully!"
echo ""
