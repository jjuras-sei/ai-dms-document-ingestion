import json
import os
import hashlib
import uuid
import base64
from datetime import datetime
from typing import Dict, Any, Optional
from urllib.parse import unquote_plus
from io import BytesIO
import boto3
from pypdf import PdfReader

# Initialize AWS clients
s3_client = boto3.client('s3')
bedrock_runtime = boto3.client('bedrock-runtime')
dynamodb = boto3.resource('dynamodb')

# Environment variables
DYNAMODB_TABLE_NAME = os.environ['DYNAMODB_TABLE_NAME']
BEDROCK_MODEL_ID = os.environ.get('BEDROCK_MODEL_ID', 'us.anthropic.claude-3-5-sonnet-20241022-v2:0')
BEDROCK_TEMPERATURE = float(os.environ.get('BEDROCK_TEMPERATURE', '0.0'))

# File paths (relative to Lambda function directory)
SCHEMA_FILE = 'schema.json'
PROMPT_FILE = 'prompt.txt'

# Get DynamoDB table
table = dynamodb.Table(DYNAMODB_TABLE_NAME)


def calculate_file_hash(content: bytes) -> str:
    """Calculate SHA256 hash of file content."""
    return hashlib.sha256(content).hexdigest()


def get_page_count(document_content: bytes, content_type: str) -> Optional[int]:
    """Extract page count from PDF documents."""
    try:
        # Only process PDF documents
        if 'pdf' in content_type.lower():
            pdf_file = BytesIO(document_content)
            pdf_reader = PdfReader(pdf_file)
            return len(pdf_reader.pages)
        return None
    except Exception as e:
        print(f"Warning: Could not extract page count: {str(e)}")
        return None


def load_schema() -> Dict[str, Any]:
    """Load the schema.json file from the Lambda package."""
    try:
        # Get the directory where this Lambda function is located
        lambda_dir = os.path.dirname(os.path.abspath(__file__))
        schema_path = os.path.join(lambda_dir, SCHEMA_FILE)
        
        with open(schema_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        raise Exception(f"Failed to load schema from {SCHEMA_FILE}: {str(e)}")


def load_prompt_template() -> str:
    """Load the prompt.txt file from the Lambda package."""
    try:
        # Get the directory where this Lambda function is located
        lambda_dir = os.path.dirname(os.path.abspath(__file__))
        prompt_path = os.path.join(lambda_dir, PROMPT_FILE)
        
        with open(prompt_path, 'r') as f:
            return f.read()
    except Exception as e:
        raise Exception(f"Failed to load prompt from {PROMPT_FILE}: {str(e)}")


def invoke_bedrock_with_document(prompt_text: str, document_content: bytes, media_type: str) -> Dict[str, Any]:
    """Invoke AWS Bedrock with a document using base64 encoding."""
    try:
        # Encode document to base64
        document_base64 = base64.b64encode(document_content).decode('utf-8')
        
        # Prepare the request body with document
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "document",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": document_base64
                            }
                        },
                        {
                            "type": "text",
                            "text": prompt_text
                        }
                    ]
                }
            ],
            "temperature": BEDROCK_TEMPERATURE
        }
        
        response = bedrock_runtime.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            body=json.dumps(request_body)
        )
        
        response_body = json.loads(response['body'].read())
        
        # Extract the text from Claude's response
        content = response_body['content'][0]['text']
        
        # Parse the JSON response
        return parse_json_response(content)
            
    except Exception as e:
        raise Exception(f"Failed to invoke Bedrock with document: {str(e)}")


def parse_json_response(content: str) -> Dict[str, Any]:
    """Parse JSON from Claude's response, handling various formats."""
    try:
        # If the response contains markdown code blocks, extract JSON
        if '```json' in content:
            start = content.find('```json') + 7
            end = content.find('```', start)
            content = content[start:end].strip()
        elif '```' in content:
            start = content.find('```') + 3
            end = content.find('```', start)
            content = content[start:end].strip()
        
        return json.loads(content)
    except json.JSONDecodeError:
        # If parsing fails, try to parse the entire response
        return json.loads(content)


def process_document(bucket: str, key: str, upload_time: str) -> Dict[str, Any]:
    """Process a single document."""
    print(f"Processing document: s3://{bucket}/{key}")
    
    # Download document from S3
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        document_content = response['Body'].read()
        content_type = response.get('ContentType', 'application/octet-stream')
        document_size = len(document_content)
    except Exception as e:
        raise Exception(f"Failed to download document from S3: {str(e)}")
    
    # Calculate file hash
    file_hash = calculate_file_hash(document_content)
    
    # Extract page count for PDF documents
    page_count = get_page_count(document_content, content_type)
    
    # Load schema and prompt template
    schema = load_schema()
    prompt_template = load_prompt_template()
    
    # Build prompt from template
    prompt_text = prompt_template.format(schema=json.dumps(schema, indent=2))
    
    print(f"Processing {content_type} document with base64 encoding")
    
    # Invoke Bedrock with document as base64
    extracted_properties = invoke_bedrock_with_document(prompt_text, document_content, content_type)
    
    # Generate unique ID
    record_id = str(uuid.uuid4())
    
    # Prepare record for DynamoDB - flatten extracted properties as top-level columns
    record = {
        'id': record_id,
        'document_name': key,
        'bucket': bucket,
        'upload_time': upload_time,
        'processing_time': datetime.utcnow().isoformat(),
        'file_hash': file_hash,
        'file_size': document_size,
        'content_type': content_type
    }
    
    # Add page count if available (PDF documents only)
    if page_count is not None:
        record['page_count'] = page_count
    
    # Add each extracted property as a top-level column
    # This allows querying individual properties directly
    for prop_name, prop_value in extracted_properties.items():
        record[prop_name] = prop_value
    
    # Store in DynamoDB
    try:
        table.put_item(Item=record)
        print(f"Stored record with ID: {record_id}")
    except Exception as e:
        raise Exception(f"Failed to store record in DynamoDB: {str(e)}")
    
    return record


def lambda_handler(event, context):
    """Lambda handler function triggered by SQS."""
    print(f"Received event: {json.dumps(event)}")
    
    results = []
    errors = []
    
    # Process each SQS record
    for sqs_record in event['Records']:
        try:
            # Parse SNS message from SQS
            sns_message = json.loads(sqs_record['body'])
            
            # Parse S3 event from SNS
            s3_event = json.loads(sns_message['Message'])
            
            # Process each S3 record
            for s3_record in s3_event['Records']:
                bucket = s3_record['s3']['bucket']['name']
                # URL decode the key to handle special characters
                key = unquote_plus(s3_record['s3']['object']['key'])
                upload_time = s3_record['eventTime']
                
                try:
                    result = process_document(bucket, key, upload_time)
                    results.append({
                        'status': 'success',
                        'document': key,
                        'record_id': result['id']
                    })
                except Exception as e:
                    error_msg = f"Failed to process {key}: {str(e)}"
                    print(error_msg)
                    errors.append({
                        'status': 'error',
                        'document': key,
                        'error': str(e)
                    })
                    
        except Exception as e:
            error_msg = f"Failed to parse SQS message: {str(e)}"
            print(error_msg)
            errors.append({
                'status': 'error',
                'error': str(e)
            })
    
    return {
        'statusCode': 200 if not errors else 207,
        'body': json.dumps({
            'processed': len(results),
            'errors': len(errors),
            'results': results,
            'errors_detail': errors
        })
    }
