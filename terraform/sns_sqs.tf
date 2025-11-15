# SNS topic for S3 events
resource "aws_sns_topic" "document_uploads" {
  name = "${var.project_name}-document-uploads-${local.resource_suffix}"

  tags = {
    Name = "${var.project_name}-document-uploads-${local.resource_suffix}"
  }
}

# SNS topic policy to allow S3 to publish
resource "aws_sns_topic_policy" "document_uploads" {
  arn = aws_sns_topic.document_uploads.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.document_uploads.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.documents.arn
          }
        }
      }
    ]
  })
}

# SQS queue for document processing
resource "aws_sqs_queue" "document_processing" {
  name                       = "${var.project_name}-document-processing-${local.resource_suffix}"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention
  receive_wait_time_seconds  = 20 # Enable long polling

  tags = {
    Name = "${var.project_name}-document-processing-${local.resource_suffix}"
  }
}

# SQS dead letter queue
resource "aws_sqs_queue" "document_processing_dlq" {
  name                       = "${var.project_name}-document-processing-dlq-${local.resource_suffix}"
  message_retention_seconds  = var.sqs_message_retention

  tags = {
    Name = "${var.project_name}-document-processing-dlq-${local.resource_suffix}"
  }
}

# Redrive policy for main queue to DLQ
resource "aws_sqs_queue_redrive_policy" "document_processing" {
  queue_url = aws_sqs_queue.document_processing.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.document_processing_dlq.arn
    maxReceiveCount     = 3
  })
}

# SQS queue policy to allow SNS to send messages
resource "aws_sqs_queue_policy" "document_processing" {
  queue_url = aws_sqs_queue.document_processing.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "SQS:SendMessage"
        Resource = aws_sqs_queue.document_processing.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.document_uploads.arn
          }
        }
      }
    ]
  })
}

# Subscribe SQS queue to SNS topic
resource "aws_sns_topic_subscription" "document_processing" {
  topic_arn = aws_sns_topic.document_uploads.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.document_processing.arn

  raw_message_delivery = false
}

# S3 bucket notification to SNS
resource "aws_s3_bucket_notification" "document_uploads" {
  bucket = aws_s3_bucket.documents.id

  topic {
    topic_arn = aws_sns_topic.document_uploads.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.document_uploads]
}
