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

# Generate GSI configuration from schema.json required fields
echo -e "${YELLOW}Analyzing schema.json for required fields...${NC}"

if [ ! -f "schema.json" ]; then
    echo -e "${RED}Error: schema.json not found${NC}"
    echo "Run build.sh first to create it from schema.json.example"
    exit 1
fi

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is not installed${NC}"
    exit 1
fi

# Parse schema.json and generate GSI configuration
GSI_CONFIG=$(python3 << 'PYTHON_SCRIPT'
import json
import sys

try:
    with open('schema.json', 'r') as f:
        schema = json.load(f)
    
    required_fields = schema.get('required', [])
    
    if not required_fields:
        print("")
        sys.exit(0)
    
    # Generate Terraform variable format
    gsi_list = []
    for field in required_fields:
        # Determine type from properties if available
        prop_type = "S"  # default to String
        if 'properties' in schema and field in schema['properties']:
            json_type = schema['properties'][field].get('type', 'string')
            if json_type == 'number' or json_type == 'integer':
                prop_type = "N"
            elif json_type == 'boolean':
                prop_type = "S"  # Store booleans as strings in DynamoDB
        
        # Create index name (PascalCase + Index)
        index_name = ''.join(word.capitalize() for word in field.split('_')) + 'Index'
        
        gsi_entry = f'''  {{
    name            = "{index_name}"
    attribute_name  = "{field}"
    attribute_type  = "{prop_type}"
    projection_type = "ALL"
  }}'''
        gsi_list.append(gsi_entry)
    
    if gsi_list:
        print("additional_gsi_attributes = [")
        print(",\n".join(gsi_list))
        print("]")
    else:
        print("")
        
except Exception as e:
    print(f"Error parsing schema.json: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to parse schema.json${NC}"
    exit 1
fi

if [ -n "$GSI_CONFIG" ]; then
    echo -e "${GREEN}✓ Found required fields in schema.json${NC}"
    echo -e "${YELLOW}  Will create GSIs for required fields${NC}"
    
    # Write to temporary tfvars file
    echo "$GSI_CONFIG" > terraform/auto_gsi.tfvars
    TFVARS_FILE="-var-file=auto_gsi.tfvars"
else
    echo -e "${YELLOW}  No required fields found in schema.json${NC}"
    TFVARS_FILE=""
fi

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
if [ -n "$TFVARS_FILE" ]; then
    terraform plan $TFVARS_FILE -out=tfplan
else
    terraform plan -out=tfplan
fi

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

# Clean up temporary files
rm -f tfplan
rm -f auto_gsi.tfvars

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
