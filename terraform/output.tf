output "instance_id" {
  value = aws_instance.test_web.id
}

output "public_ip" {
  value = aws_instance.test_web.public_ip
}

output "public_dns" {
  value = aws_instance.test_web.public_dns
}

output "app_url" {
  value = "http://${aws_instance.test_web.public_ip}:8000"
}