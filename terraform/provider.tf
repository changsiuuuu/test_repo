# 테스트용 03:12

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }


  # terraform 상태관리 (CI/CD)
  backend "s3" {
    bucket         = "tfstate-bucket-0917b0f7"
    key            = "deployment/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-lock" # 미리 준비된 dynamodb 테이블
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}