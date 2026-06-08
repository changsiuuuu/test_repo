variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "web_ami_id" {
  type        = string
  default     = "ami-0aef7d1237f8a3805"
  description = "ami-build.yml이 갱신할 AMI ID"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type        = string
  default     = "test_repo"
  description = "SSH 키페어 이름"
}

# ✨ Scaling 관련 변수
variable "desired_capacity" {
  type    = number
  default = 1
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 4
}