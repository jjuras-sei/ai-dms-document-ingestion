#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}========================================${NC}"
echo -e "${RED}AI-DMS Document Ingestion Destruction${NC}"
echo -e "${RED}========================================${NC}"
echo ""

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    echo "Please install Terraform from https://www.terraform.io/downloads"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Please install AWS CLI from https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Please run 'aws configure' to set up your credentials"
    exit 1
fi

echo -e "${GREEN}✓ AWS credentials configured${NC}"
echo ""

# Navigate to terraform directory
cd terraform

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${YELLOW}Warning: No Terraform state file found${NC}"
    echo "This might mean the infrastructure was never deployed or the state file is missing."
    echo ""
    read -p "Do you want to continue anyway? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${RED}Destruction cancelled${NC}"
        exit 1
    fi
fi

# Get current deployment info
echo -e "${YELLOW}Current deployment information:${NC}"
if terraform output &> /dev/null; then
    terraform output
    echo ""
else
    echo -e "${YELLOW}Unable to retrieve deployment information${NC}"
    echo ""
fi

# Warning message
echo -e "${RED}⚠️  WARNING ⚠️${NC}"
echo -e "${RED}This will DELETE ALL resources including:${NC}"
echo -e "${RED}- S3 buckets (and all documents inside)${NC}"
echo -e "${RED}- DynamoDB table (and all data)${NC}"
echo -e "${RED}- Lambda function${NC}"
echo -e "${RED}- SNS/SQS queues${NC}"
echo -e "${RED}- IAM roles and policies${NC}"
echo ""
echo -e "${YELLOW}This action CANNOT be undone!${NC}"
echo ""

# First confirmation
read -p "Are you sure you want to destroy the infrastructure? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${GREEN}Destruction cancelled${NC}"
    exit 0
fi

# Second confirmation
echo -e "${RED}FINAL WARNING: All data will be permanently deleted!${NC}"
read -p "Type 'DESTROY' to confirm: " -r
echo ""

if [[ ! $REPLY == "DESTROY" ]]; then
    echo -e "${GREEN}Destruction cancelled${NC}"
    exit 0
fi

# Plan destruction
echo -e "${YELLOW}Planning destruction...${NC}"
terraform plan -destroy -out=tfplan

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Review the destruction plan above${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
read -p "Proceed with destruction? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${GREEN}Destruction cancelled${NC}"
    rm -f tfplan
    exit 0
fi

# Empty S3 buckets before destruction
echo -e "${YELLOW}Emptying S3 buckets...${NC}"
if terraform output documents_bucket_name &> /dev/null; then
    BUCKET_NAME=$(terraform output -raw documents_bucket_name 2>/dev/null)
    if [ ! -z "$BUCKET_NAME" ]; then
        echo "  - Emptying documents bucket: $BUCKET_NAME"
        aws s3 rm s3://$BUCKET_NAME --recursive 2>/dev/null || echo "    (Bucket already empty or doesn't exist)"
        echo -e "${GREEN}✓ S3 bucket emptied${NC}"
    fi
else
    echo "  - No buckets to empty"
fi
echo ""

# Apply destruction
echo -e "${YELLOW}Destroying infrastructure...${NC}"
terraform apply tfplan

# Clean up plan file
rm -f tfplan

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Destruction Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}All resources have been successfully destroyed.${NC}"
echo ""
