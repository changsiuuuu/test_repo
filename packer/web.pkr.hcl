packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "ami_purpose" {
  type    = string
  default = "web"
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

source "amazon-ebs" "test" {
  ami_name      = "test-pipeline-${var.ami_purpose}-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  instance_type = "t3.micro"
  region        = var.region

  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }

  ssh_username = "ec2-user"

  tags = {
    Name    = "test-pipeline-${var.ami_purpose}"
    Purpose = var.ami_purpose
    Builder = "packer-test"
  }
}

build {
  sources = ["source.amazon-ebs.test"]

  # Docker만 깔린 베이스 AMI
  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y docker",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker ec2-user",
      "echo '✅ Base AMI ready'"
    ]
  }
}