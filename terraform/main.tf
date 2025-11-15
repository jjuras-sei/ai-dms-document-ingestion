terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# Generate a unique suffix for resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  function_name   = "${var.project_name}-processor-${local.resource_suffix}"
}
