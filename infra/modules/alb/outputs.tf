output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "https_listener_arn" {
  description = "CodeDeploy shifts traffic on this listener"
  value       = aws_lb_listener.https.arn
}

output "blue_target_group_arns" {
  description = "ECS services register here on first creation"
  value       = { for name, tg in aws_lb_target_group.blue : name => tg.arn }
}

output "target_group_names" {
  description = "CodeDeploy refers to the blue/green pair by name"
  value = {
    for name in keys(var.services) : name => {
      blue  = aws_lb_target_group.blue[name].name
      green = aws_lb_target_group.green[name].name
    }
  }
}