output "alb_dns_name" {
  value       = aws_lb.web.dns_name
  description = "Access the app via this DNS"
}

output "asg_name" {
  value = aws_autoscaling_group.web.name
}

output "current_capacity" {
  value = aws_autoscaling_group.web.desired_capacity
}