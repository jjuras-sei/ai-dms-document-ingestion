# AI-Powered Document Ingestion System

An AWS-based serverless application for automated document ingestion and analysis using AWS Bedrock, S3, Lambda, and DynamoDB.

## Overview

This application provides a generic, scalable infrastructure for processing documents uploaded to S3. When documents are uploaded, they are automatically analyzed using AWS Bedrock (Claude) to extract specific properties defined in a customizable schema. The extracted data, along with metadata, is stored in DynamoDB for querying and analysis.

## Architecture

```
┌─────────────────┐
│   S3 Bucket     │
│   (Documents)   │
└────────┬────────┘
         │ ObjectCreated Event
         ▼
┌─────────────────┐
│   SNS Topic     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   SQS Queue     │
└────────┬────────┘
         │ Triggers
         ▼
┌─────────────────┐     ┌──────────────┐
│  Lambda         │────▶│ AWS Bedrock  │
│  Function       │     │ (Claude 3.5) │
│  + schema.json  │     └──────────────┘
│  + prompt.txt   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   DynamoDB      │
│   Table         │
└─────────────────┘
```

## Key Features

- **Serverless Architecture**: Fully serverless using AWS Lambda, S3, SNS, SQS, and DynamoDB
- **Event-Driven Processing**: Automatic processing triggered by S3 upload events
- **AI-Powered Analysis**: Uses AWS Bedrock (Claude 3.5 Sonnet) for intelligent document analysis
- **Native Document Processing**: All documents sent as base64-encoded files for optimal Claude 3.5 processing
- **Generic and Customizable**: Easily fork and customize for different document types
- **Scalable**: Handles concurrent document uploads with SQS queuing
- **Error Handling**: Dead letter queue for failed processing attempts
- **Metadata Storage**: Stores extracted properties plus file hash, size, upload time, etc.
- **Multi-Format Support**: PDF, text, JSON, HTML, markdown, and other document formats

## Project Structure

```
.
├── schema.json                 # Defines properties to extract from documents
├── prompt.txt                  # Bedrock prompt template
├── build.sh                    # Build Lambda deployment package
├── deploy.sh                   # One-click deployment script
├── destroy.sh                  # One-click destruction script
├── lambda/
│   ├── document_processor.py  # Main Lambda function
│   └── requirements.txt       # Python dependencies
├── terraform/
│   ├── main.tf               # Main Terraform configuration
│   ├── variables.tf          # Input variables
│   ├── outputs.tf            # Output values
│   ├── s3.tf                 # S3 bucket configuration
│   ├── dynamodb.tf           # DynamoDB table configuration
│   ├── sns_sqs.tf            # SNS and SQS configuration
│   ├── iam.tf                # IAM roles and policies
│   └── lambda.tf             # Lambda function configuration
└── README.md
```

Note: The `build.sh` script creates a Python virtual environment, installs all dependencies from `requirements.txt`, and packages everything (Lambda code, dependencies, schema.json, and prompt.txt) into a single deployment zip file.

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured with credentials
- Terraform >= 1.0
- Python 3.11
- Access to AWS Bedrock (Claude model enabled in your region)

## Customization Guide

To create a fork for a specific document type:

### 1. Clone and Customize Schema

Edit `schema.json` to define the properties you want to extract:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Invoice Property Extraction",
  "description": "Properties to extract from invoice documents",
  "type": "object",
  "properties": {
    "invoice_number": {
      "type": "string",
      "description": "The invoice number"
    },
    "total_amount": {
      "type": "number",
      "description": "Total invoice amount"
    },
    "vendor_name": {
      "type": "string",
      "description": "Name of the vendor"
    }
  },
  "required": ["invoice_number", "total_amount"]
}
```

### 2. Customize Prompt

Edit `prompt.txt` to tailor the instructions for your use case. The template uses the placeholder:
- `{schema}` - Automatically replaced with your schema.json content

Note: Documents are sent as base64-encoded files directly to Claude 3.5 Sonnet, not as extracted text.

### 3. Configure Variables (Optional)

Create a `terraform/terraform.tfvars` file to override defaults:

```hcl
project_name         = "invoice-processor"
aws_region          = "us-east-1"
bedrock_model_id    = "anthropic.claude-3-sonnet-20240229-v1:0"
lambda_timeout      = 300
lambda_memory_size  = 512
```

## Deployment

### Quick Deploy (Recommended)

Use the one-click deployment script:

```bash
./deploy.sh
```

This script will:
1. Check prerequisites (Terraform, AWS CLI, credentials)
2. Initialize Terraform
3. Show deployment plan
4. Deploy infrastructure after confirmation
5. Display all output values and next steps

### Manual Deployment

If you prefer manual deployment:

#### Step 1: Initialize Terraform

```bash
cd terraform
terraform init
```

#### Step 2: Review Plan

```bash
terraform plan
```

#### Step 3: Deploy Infrastructure

```bash
terraform apply
```

Review the changes and type `yes` to confirm.

#### Step 4: Note Output Values

After deployment, Terraform will output important values:

```bash
terraform output
```

Save these values for future reference:
- `documents_bucket_name` - Upload documents here
- `dynamodb_table_name` - Query results from this table
- `lambda_function_name` - View logs for this function

## Usage

### Upload a Document

Using AWS CLI:

```bash
aws s3 cp your-document.pdf s3://$(terraform output -raw documents_bucket_name)/
```

Using AWS Console:
1. Navigate to S3
2. Find the bucket (name from `documents_bucket_name` output)
3. Upload your document

### Query Results

Using AWS CLI:

```bash
aws dynamodb scan --table-name $(terraform output -raw dynamodb_table_name)
```

Using AWS Console:
1. Navigate to DynamoDB
2. Find the table (name from `dynamodb_table_name` output)
3. Explore items

### View Logs

Using AWS CLI:

```bash
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow
```

Using AWS Console:
1. Navigate to CloudWatch Logs
2. Find the log group for your Lambda function
3. View recent log streams

## DynamoDB Schema

Each processed document creates a record with the following structure:

```json
{
  "id": "uuid-here",
  "document_name": "path/to/file.pdf",
  "bucket": "bucket-name",
  "upload_time": "2024-01-15T10:30:00Z",
  "processing_time": "2024-01-15T10:30:15Z",
  "file_hash": "sha256-hash",
  "file_size": 12345,
  "content_type": "application/pdf",
  "page_count": 42,
  "property1": "value1",
  "property2": "value2"
}
```

**Note**: All properties defined in `schema.json` are stored as top-level columns in DynamoDB, making them easily queryable. For example, if your schema defines properties like `invoice_number`, `vendor_name`, and `total_amount`, they will appear as direct columns in the DynamoDB table, not nested in a sub-object.

**page_count**: Automatically extracted for PDF documents only. This field will only be present for PDF files and contains the number of pages in the document.

### Global Secondary Indexes

- **DocumentNameIndex**: Query by document name
- **UploadTimeIndex**: Query by upload time
- **FileHashIndex**: Find duplicate documents

## Cost Considerations

- **S3**: Storage costs for documents and config files
- **Lambda**: Pay per invocation and compute time
- **Bedrock**: Pay per API call and tokens processed
- **DynamoDB**: Pay-per-request pricing
- **SNS/SQS**: Minimal costs for message passing

For typical usage (100 documents/day):
- Estimated cost: $5-20/month (varies by document size and Bedrock usage)

## Troubleshooting

### Documents Not Processing

1. Check Lambda logs:
   ```bash
   aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow
   ```

2. Check SQS dead letter queue:
   ```bash
   aws sqs receive-message --queue-url $(terraform output -raw sqs_dlq_url)
   ```

### Bedrock Access Denied

Ensure AWS Bedrock is enabled in your region and you have requested access to Claude models:
1. Go to AWS Bedrock console
2. Navigate to Model Access
3. Request access to Anthropic Claude models

### Permission Errors

Verify IAM roles have correct permissions. The Lambda execution role needs:
- S3 read access to documents and config buckets
- DynamoDB write access
- Bedrock invoke access
- SQS read/delete access

## Cleanup

### Quick Destroy (Recommended)

Use the one-click destruction script:

```bash
./destroy.sh
```

This script will:
1. Check prerequisites and AWS credentials
2. Display current deployment information
3. Show multiple warnings about data loss
4. Require multiple confirmations (including typing 'DESTROY')
5. Show destruction plan
6. Destroy all infrastructure after final confirmation

### Manual Destruction

If you prefer manual destruction:

```bash
cd terraform
terraform destroy
```

Review the destruction plan and type `yes` to confirm.

**⚠️ WARNING**: This will delete all data including documents and DynamoDB records. Back up any important data first.

## Security Considerations

- All S3 buckets have encryption at rest enabled
- Public access is blocked on all buckets
- DynamoDB table has encryption enabled
- Lambda execution role follows least privilege principle
- Consider enabling VPC for Lambda if processing sensitive documents

## Advanced Configuration

### Multiple Document Types

To process different document types simultaneously, deploy multiple instances with different configurations:

```bash
# Deploy invoice processor
terraform apply -var="project_name=invoice-processor" -var="resource_suffix=invoices"

# Deploy contract processor
terraform apply -var="project_name=contract-processor" -var="resource_suffix=contracts"
```

### Custom Bedrock Models

To use different Bedrock models, update the `bedrock_model_id` variable:

```hcl
bedrock_model_id = "anthropic.claude-3-opus-20240229-v1:0"
```

### Batch Processing

The Lambda function processes documents one at a time by default. To increase throughput:

1. Increase Lambda concurrency in `terraform/lambda.tf`
2. Increase SQS batch size (with corresponding Lambda timeout adjustments)

## Contributing

This is a generic template designed to be forked and customized. Feel free to adapt it for your specific use cases.

## License

This project is provided as-is for demonstration and development purposes.

## Support

For AWS-related issues, consult AWS documentation:
- [AWS Lambda](https://docs.aws.amazon.com/lambda/)
- [AWS Bedrock](https://docs.aws.amazon.com/bedrock/)
- [Amazon DynamoDB](https://docs.aws.amazon.com/dynamodb/)
