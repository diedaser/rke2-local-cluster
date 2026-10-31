# rancher backplane

Intentionally empty. The `rancher` building block reuses the OpenStack
application credential created by `modules/rke2-cluster/backplane` (it only
needs to read and write Barbican secrets in the same project), and gets cluster
access from the parent building block through Barbican (ADR-012).
