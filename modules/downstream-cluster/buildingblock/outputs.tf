# meshStack shows outputs in plaintext and has no sensitive outputs.
# Nothing secret leaves this building block (ADR-012, CONTRIBUTING.md rule 11).
# No kubeconfig: users download theirs from Rancher with their own identity.
# Update templates/summary.md.tftpl, README.md and docs/meshstack-gui-setup.md
# when outputs change.

output "cluster_name" {
  description = "Name of the cluster in Rancher (<cluster_name>-<short building block id>)."
  value       = rancher2_cluster_v2.this.name
}

output "rancher_cluster_id" {
  description = "Rancher (management v3) cluster ID, for example c-m-abcd1234."
  value       = rancher2_cluster_v2.this.cluster_v1_id
}

output "rancher_cluster_url" {
  description = "Cluster explorer in the Rancher UI."
  value       = "${local.rancher_url}/dashboard/c/${rancher2_cluster_v2.this.cluster_v1_id}/explorer"
}

output "nat_public_ip" {
  description = "Public IP all nodes use to reach Rancher. Add it to the rke2-cluster ingress_allowed_cidrs if that allow list is restricted."
  value       = aws_eip.nat.public_ip
}

output "summary" {
  description = "Markdown summary shown in meshStack after apply."
  value = templatefile("${path.module}/templates/summary.md.tftpl", {
    cluster_name        = rancher2_cluster_v2.this.name
    rancher_cluster_url = "${local.rancher_url}/dashboard/c/${rancher2_cluster_v2.this.cluster_v1_id}/explorer"
    kubernetes_version  = var.kubernetes_version
    pools               = local.pools
    nat_public_ip       = aws_eip.nat.public_ip
    region              = local.region
  })
}
