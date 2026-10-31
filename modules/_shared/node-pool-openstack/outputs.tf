output "ips" {
  description = "Private IPv4 addresses of the nodes, in index order."
  value       = [for i in local.instances : i.access_ip_v4]
}

output "ids" {
  description = "Instance IDs, in index order."
  value       = [for i in local.instances : i.id]
}

output "names" {
  description = "Instance names, in index order."
  value       = [for i in local.instances : i.name]
}
