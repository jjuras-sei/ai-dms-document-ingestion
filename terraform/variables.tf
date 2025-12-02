variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "doc-ingestion"
}

variable "resource_suffix" {
  description = "Optional suffix for resource names (auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "bedrock_model_id" {
  description = "Bedrock model ID to use for document analysis"
  type        = string
  default     = "us.anthropic.claude-3-5-sonnet-20241022-v2:0"
}

variable "bedrock_temperature" {
  description = "Temperature parameter for Bedrock model inference (0.0-1.0)"
  type        = number
  default     = 0.0
}

variable "additional_gsi_attributes" {
  description = "List of additional global secondary indices to create on the DynamoDB table"
  type = list(object({
    name            = string
    attribute_name  = string
    attribute_type  = string
    projection_type = string
  }))
  default = []
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "sqs_visibility_timeout" {
  description = "SQS visibility timeout in seconds (should be >= lambda timeout)"
  type        = number
  default     = 360
}

variable "sqs_message_retention" {
  description = "SQS message retention period in seconds"
  type        = number
  default     = 1209600 # 14 days
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days. Set to null for indefinite retention."
  type        = number
  default     = 7
  nullable    = true
}
