#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AI-DMS Document Ingestion Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
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

# Check Lambda code exists
echo -e "${YELLOW}Checking Lambda code...${NC}"
if [ ! -f "lambda/document_processor.py" ]; then
    echo -e "${RED}Error: Lambda code not found${NC}"
    echo "Expected lambda/document_processor.py to exist"
    exit 1
fi

echo -e "${GREEN}✓ Lambda code found${NC}"
echo ""

# Build Lambda deployment package
echo -e "${YELLOW}Building Lambda deployment package...${NC}"
./build.sh

if [ ! -f "lambda_deployment.zip" ]; then
    echo -e "${RED}Error: Build failed - lambda_deployment.zip not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Lambda deployment package ready${NC}"
echo ""

# Show what will be deployed
echo -e "${YELLOW}Deployment will include:${NC}"
echo "  - Lambda function (with schema.json and prompt.txt bundled)"
echo "  - S3 bucket (documents)"
echo "  - DynamoDB table"
echo "  - SNS/SQS event chain"
echo "  - IAM roles and policies"
echo ""

# Navigate to terraform directory
cd terraform

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

echo -e "${GREEN}✓ Terraform initialized${NC}"
echo ""

# Plan deployment
echo -e "${YELLOW}Planning deployment...${NC}"
terraform plan -out=tfplan

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Review the plan above${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
read -p "Do you want to proceed with the deployment? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Deployment cancelled${NC}"
    rm -f tfplan
    exit 1
fi

# Apply deployment
echo -e "${YELLOW}Deploying infrastructure...${NC}"
echo "  - Creating S3 bucket for documents"
echo "  - Deploying Lambda function (with schema.json and prompt.txt)"
echo "  - Creating DynamoDB table"
echo "  - Setting up SNS/SQS event chain"
echo "  - Configuring IAM roles and permissions"
echo ""
terraform apply tfplan

# Clean up plan file
rm -f tfplan

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}✓ Lambda function deployed with bundled configuration${NC}"
echo -e "${GREEN}✓ All infrastructure provisioned${NC}"
echo ""
echo -e "${GREEN}Important outputs:${NC}"
terraform output

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Upload documents to the S3 bucket:"
echo "   aws s3 cp your-document.pdf s3://\$(terraform output -raw documents_bucket_name)/"
echo ""
echo "2. Query results from DynamoDB:"
echo "   aws dynamodb scan --table-name \$(terraform output -raw dynamodb_table_name)"
echo ""
echo "3. View Lambda logs:"
echo "   aws logs tail /aws/lambda/\$(terraform output -raw lambda_function_name) --follow"
echo ""
