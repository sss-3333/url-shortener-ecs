output "certificate_arn" {
  description = "Taken from the validation resource so anything using it waits for validation to finish"
  value       = aws_acm_certificate_validation.this.certificate_arn
}