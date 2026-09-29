output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "https_listener_arn" {
  description = "CodeDeploy shifts API traffic on this listener"
  value       = aws_lb_listener.https.arn
}

output "api_target_group_arn" {
  description = "Blue target group, used when the ECS service is first created"
  value       = aws_lb_target_group.api_blue.arn

  # ECS refuses to create a service with a target group that isn't attached to a listener yet
  depends_on = [aws_lb_listener.https]
}

output "api_target_group_names" {
  description = "CodeDeploy refers to the pair by name"
  value = {
    blue  = aws_lb_target_group.api_blue.name
    green = aws_lb_target_group.api_green.name
  }
}

output "dashboard_target_group_arn" {
  value = aws_lb_target_group.dashboard.arn

  depends_on = [aws_lb_listener_rule.dashboard]
}