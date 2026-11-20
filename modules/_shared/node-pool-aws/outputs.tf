output "ips" {
  description = "Private IPv4 addresses of the nodes, in index order."
  value       = [for i in local.instances : i.private_ip]
}

output "ids" {
  description = "EC2 instance IDs, in index order."
  value       = [for i in local.instances : i.id]
}

output "names" {
  description = "Instance names (Name tag), in index order."
  value       = local.names
}

output "iam_instance_profile" {
  description = "IAM instance profile name applied to every node of the pool (null without one)."
  value       = var.iam_instance_profile
}
