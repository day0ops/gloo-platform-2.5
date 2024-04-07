output "bastion_security_group_id" {
  description = "Security group ID for Bastion"
  value       = try(aws_security_group.bastion_host_security_group[0].id, null)
}
