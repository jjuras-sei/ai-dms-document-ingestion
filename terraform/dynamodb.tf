# DynamoDB table for storing document analysis results
resource "aws_dynamodb_table" "documents" {
  name           = "${var.project_name}-documents-${local.resource_suffix}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "document_name"
    type = "S"
  }

  attribute {
    name = "upload_time"
    type = "S"
  }

  attribute {
    name = "file_hash"
    type = "S"
  }

  # Dynamic attributes for additional GSIs
  dynamic "attribute" {
    for_each = var.additional_gsi_attributes
    content {
      name = attribute.value.attribute_name
      type = attribute.value.attribute_type
    }
  }

  # Global secondary index for querying by document name
  global_secondary_index {
    name            = "DocumentNameIndex"
    hash_key        = "document_name"
    projection_type = "ALL"
  }

  # Global secondary index for querying by upload time
  global_secondary_index {
    name            = "UploadTimeIndex"
    hash_key        = "upload_time"
    projection_type = "ALL"
  }

  # Global secondary index for querying by file hash (to find duplicates)
  global_secondary_index {
    name            = "FileHashIndex"
    hash_key        = "file_hash"
    projection_type = "ALL"
  }

  # Dynamic global secondary indices from variable
  dynamic "global_secondary_index" {
    for_each = var.additional_gsi_attributes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.attribute_name
      projection_type = global_secondary_index.value.projection_type
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}
