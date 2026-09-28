output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "s3_prefix_list_id" {
  description = "Used later so the ECS security group can allow traffic to the S3 gateway endpoint"
  value       = aws_vpc_endpoint.s3.prefix_list_id
}