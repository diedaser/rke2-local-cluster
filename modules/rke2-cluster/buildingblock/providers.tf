# Credentials come exclusively from the environment set by the meshStack
# definition (OS_AUTH_URL, OS_REGION_NAME, OS_AUTH_TYPE,
# OS_APPLICATION_CREDENTIAL_ID, OS_APPLICATION_CREDENTIAL_SECRET). No provider
# block is needed: the default configuration reads them.

# The project the credentials are scoped to. Checked against the meshStack
# tenant (openstack_project_id) before anything is created, see network.tf.
data "openstack_identity_auth_scope_v3" "current" {
  name = "current"
}
