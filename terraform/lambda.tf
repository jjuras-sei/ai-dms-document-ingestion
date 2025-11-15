# Lambda function
resource "aws_lambda_function" "document_processor" {
  filename         = "${path.module}/../lambda_deployment.zip"
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "document_processor.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/../lambda_deployment.zip")
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.documents.name
      BEDROCK_MODEL_ID    = var.bedrock_model_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_custom
  ]

  tags = {
    Name = local.function_name
  }
}

# Lambda event source mapping from SQS
resource "aws_lambda_event_source_mapping" "document_processing" {
  event_source_arn = aws_sqs_queue.document_processing.arn
  function_name    = aws_lambda_function.document_processor.arn
  batch_size       = 1
  enabled          = true

  # Optional: Configure scaling behavior
  scaling_config {
    maximum_concurrency = 10
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14

  tags = {
    Name = "${local.function_name}-logs"
  }
}
