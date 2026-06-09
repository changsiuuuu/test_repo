# ============================================
# Network (기본 VPC 사용)
# ============================================
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ============================================
# Security Groups
# ============================================

# ALB용 SG
resource "aws_security_group" "alb_sg" {
  name        = "test-pipeline-alb-sg"
  description = "ALB security group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "test-pipeline-alb-sg"
  }
}

# EC2용 SG
resource "aws_security_group" "test_sg" {
  name        = "test-pipeline-sg"
  description = "Test pipeline security group"
  vpc_id      = data.aws_vpc.default.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # FastAPI: ALB에서만 접근
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "test-pipeline-sg"
  }
}

# ============================================
# Application Load Balancer
# ============================================
resource "aws_lb" "web" {
  name               = "test-pipeline-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "test-pipeline-alb"
  }
}

resource "aws_lb_target_group" "web" {
  name     = "test-pipeline-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "test-pipeline-tg"
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ============================================
# Launch Template
# ============================================
resource "aws_launch_template" "web" {
  name_prefix   = "test-web-lt-"
  image_id      = var.web_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  vpc_security_group_ids = [aws_security_group.test_sg.id]

  # AMI에 이미 Docker 설치되어 있으니 docker run만 실행
  user_data = base64encode(<<-EOF
    #!/bin/bash
    systemctl start docker
    docker pull jj3061/fastapi-app:${var.app_image_tag}
    docker run -d \
      --name fastapi-app \
      --restart always \
      -p 8000:8000 \
      jj3061/fastapi-app:${var.app_image_tag}
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "test-web-asg"
      Role = "web"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================
# Auto Scaling Group
# ============================================
resource "aws_autoscaling_group" "web" {
  name                = "test-pipeline-asg"
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.web.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "test-web-asg"
    propagate_at_launch = true
  }
}

# Scale Up 스케줄
resource "aws_autoscaling_schedule" "scale_up" {
  count = var.scale_up_cron != "" ? 1 : 0
  
  scheduled_action_name  = "scheduled-scale-up"
  autoscaling_group_name = aws_autoscaling_group.web.name
  
  desired_capacity = var.scale_up_capacity
  min_size         = var.min_size
  max_size         = var.max_size
  recurrence       = var.scale_up_cron
  time_zone        = "Asia/Seoul"
}

# Scale Down 스케줄
resource "aws_autoscaling_schedule" "scale_down" {
  count = var.scale_down_cron != "" ? 1 : 0
  
  scheduled_action_name  = "scheduled-scale-down"
  autoscaling_group_name = aws_autoscaling_group.web.name
  
  desired_capacity = var.scale_down_capacity
  min_size         = var.min_size
  max_size         = var.max_size
  recurrence       = var.scale_down_cron
  time_zone        = "Asia/Seoul"
}