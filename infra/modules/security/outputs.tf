output "service_security_group_ids" {
  description = "Map of service name to security group ID"
  value       = { for name, sg in aws_security_group.service : name => sg.id }
}