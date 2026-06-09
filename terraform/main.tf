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
# IAM Role for SSM
# ============================================
resource "aws_iam_role" "ssm_role" {
  name = "test-pipeline-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "test-pipeline-ssm-profile"
  role = aws_iam_role.ssm_role.name
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

# EC2 Web용 SG
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

# EC2 DB용 SG
resource "aws_security_group" "db_sg" {
  name        = "test-pipeline-db-sg"
  description = "Test pipeline DB security group"
  vpc_id      = data.aws_vpc.default.id

  # PostgreSQL: Web SG에서만 접근 허용
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.test_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "test-pipeline-db-sg"
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
# DB EC2 Instance
# ============================================
resource "aws_instance" "db" {
  ami           = var.db_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum install -y jq docker
    systemctl start docker

    # 1. Tailscale 설치 및 설정
    curl -fsSL https://tailscale.com/install.sh | sh
    
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
    MAC=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/mac)
    VPC_CIDR=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-ipv4-cidr-block)

    tailscale up --authkey=${var.tailscale_auth_key} --advertise-routes=$VPC_CIDR --hostname=aws-db-node
    
    sleep 5
    DEVICE_ID=$(tailscale status --json | jq -r '.Self.ID')
    curl -s -X POST "https://api.tailscale.com/api/v2/device/$DEVICE_ID/routes" \
      -u "${var.tailscale_api_key}:" \
      -H "Content-Type: application/json" \
      -d "{\"routes\": [\"$VPC_CIDR\"]}"

    # 2. 모니터링 컨테이너 실행
    docker run -d --name node-exporter -p 9100:9100 --restart always prom/node-exporter
    docker run -d --name cadvisor -p 8080:8080 -v /:/rootfs:ro -v /var/run:/var/run:rw -v /sys:/sys:ro -v /var/lib/docker/:/var/lib/docker:ro --restart always gcr.io/cadvisor/cadvisor

    # 3. DB 컨테이너 실행
    docker pull ${var.db_image_tag}
    docker run -d \
      --name my-db \
      --restart always \
      -e POSTGRES_PASSWORD=secret \
      -e POSTGRES_USER=myuser \
      -e POSTGRES_DB=mydb \
      -p 5432:5432 \
      ${var.db_image_tag}
  EOF
  )

  tags = {
    Name    = "test-pipeline-db"
    Purpose = "db"
  }
}

# ============================================
# Launch Template (Web)
# ============================================
resource "aws_launch_template" "web" {
  name_prefix   = "test-web-lt-"
  image_id      = var.web_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  vpc_security_group_ids = [aws_security_group.test_sg.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ssm_profile.name
  }

  # AMI에 이미 Docker 설치되어 있으니 docker run만 실행
  # Web앱이 DB 주소를 알게 하기 위해 DB 내부 IP를 환경변수로 전달할 수 있습니다.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    systemctl start docker

    # 1. 모니터링 컨테이너 실행 (Node Exporter & cAdvisor)
    docker run -d --name node-exporter -p 9100:9100 --restart always prom/node-exporter
    docker run -d --name cadvisor -p 8080:8080 -v /:/rootfs:ro -v /var/run:/var/run:rw -v /sys:/sys:ro -v /var/lib/docker/:/var/lib/docker:ro --restart always gcr.io/cadvisor/cadvisor

    # 2. Web앱 컨테이너 실행
    docker pull jj3061/fastapi-app:${var.app_image_tag}
    docker run -d \
      --name fastapi-app \
      --restart always \
      -p 8000:8000 \
      -e DB_HOST=${aws_instance.db.private_ip} \
      -e DB_PORT=5432 \
      -e DB_USER=myuser \
      -e DB_PASSWORD=secret \
      -e DB_NAME=mydb \
      jj3061/fastapi-app:${var.app_image_tag}
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "test-web-asg"
      Purpose = "web"
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
  name             = "test-pipeline-asg"
  desired_capacity = var.desired_capacity
  min_size         = var.min_size
  max_size         = var.max_size

  vpc_zone_identifier       = data.aws_subnets.default.ids
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
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