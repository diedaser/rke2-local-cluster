# rancher backplane

Intentionally empty. The `rancher` building block reuses the IAM user and
access key created by `modules/rke2-cluster/backplane` (it only needs to read
and write Secrets Manager secrets in the same account and region), and gets
cluster access from the parent building block through Secrets Manager
(ADR-012).
