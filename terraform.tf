terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.60.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}
