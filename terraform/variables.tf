variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "web_ami_id" {
  type        = string
  default     = "ami-0aef7d1237f8a3805"   # Amazon Linux 2 (서울 리전 기본값)
  description = "ami-build.yml이 갱신할 AMI ID"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"   # 프리티어
}

variable "key_name" {
  type        = string
  default     = "test_repo"        # 본인 키페어 이름 (SSH용)
  description = "test_repo"
}