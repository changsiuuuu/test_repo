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

variable "scale_up_capacity" {
  type    = number
  default = 0
}

variable "scale_up_cron" {
  type    = string
  default = ""
}

variable "scale_down_capacity" {
  type    = number
  default = 0
}

variable "scale_down_cron" {
  type    = string
  default = ""
}

variable "app_image_tag" {
  type    = string
  default = "latest"
  description = "Docker 이미지 태그 (rollback.yml 등에서 사용)"
}