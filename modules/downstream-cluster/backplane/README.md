# downstream-cluster backplane

Intentionally empty. The `downstream-cluster` building block reuses the runner
IAM user of `modules/rke2-cluster/backplane` (VPC, NAT, security group, Secrets
Manager) and the node-driver IAM user created there (`node-driver.tf`), whose key
Rancher uses to create the EC2 instances (ADR-015).
